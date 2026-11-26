package kr.habitmonster.gift;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.mockito.Mockito.doReturn;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import com.jayway.jsonpath.JsonPath;

import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * 퀘스트 3.5단계 — 선물함 (API 명세 v10 11장, 결정 D-89).
 * 퀘스트를 완료하면 지갑이 아니라 선물함에 한 줄 생기고, 받을 때 지갑 · 가방에 들어간다.
 * 기본 온보딩이면 필드에 원숭이(1번) · 쥐(6번)가 있다 — 쓰다듬기 1G · 말 걸기 1G 퀘스트로 선물을 만든다.
 */
class GiftApiTest extends PostgresTest {

	static final String E = "g@habit.kr";

	// 바꿔 끼우는 빈은 BalanceConfig 하나만 — CheckinApiTest와 같은 조합이라 Spring 테스트 컨텍스트를 같이 쓴다.
	// 조합이 하나 늘 때마다 컨텍스트(DB 연결 10개)가 하나 더 떠서, 9개째에 PostgreSQL 연결 한도(100)를 넘었다 (11-26).
	@MockitoSpyBean
	BalanceConfig config;

	ResultActions as(String access, MockHttpServletRequestBuilder req) throws Exception {
		return mvc.perform(req.header("Authorization", "Bearer " + access));
	}

	ResultActions claim(String access, long giftId, String key) throws Exception {
		return as(access, post("/gifts/" + giftId + "/claim").header(IdempotencyFilter.HEADER, key));
	}

	ResultActions claim(String access, long giftId) throws Exception {
		return claim(access, giftId, UUID.randomUUID().toString());
	}

	ResultActions claimAll(String access) throws Exception {
		return as(access, post("/gifts/claim-all").header(IdempotencyFilter.HEADER, UUID.randomUUID().toString()));
	}

	/** 원숭이 쓰다듬기 → "몬스터 쓰다듬기" 퀘스트 완료 → 1G 선물. */
	void pet(String access, String email) throws Exception {
		as(access, post("/monsters/" + monster(email, 1) + "/affection").contentType(MediaType.APPLICATION_JSON)
			.content("{\"action\": \"PET\"}")).andExpect(status().isOk());
	}

	/** 말 걸기 → "몬스터에게 말 걸기" 퀘스트 완료 → 1G 선물. */
	void talk(String access, String email) throws Exception {
		as(access, get("/monsters/" + monster(email, 1) + "/line")).andExpect(status().isOk());
	}

	long monster(String email, int speciesId) {
		return jdbc.queryForObject("select id from monster.user_monster where user_id = ? and species_id = ?", Long.class,
				userIdOf(email), speciesId);
	}

	long onlyGift(String email) {
		return jdbc.queryForObject("select id from gift.gift where user_id = ?", Long.class, userIdOf(email));
	}

	long balance(String email) {
		return jdbc.queryForObject("select balance from wallet.wallet where user_id = ?", Long.class, userIdOf(email));
	}

	int ledger(String email, String reason) {
		return jdbc.queryForObject("select count(*) from wallet.wallet_ledger where user_id = ? and reason_code = ?",
				Integer.class, userIdOf(email), reason);
	}

	// ---------- 만들기 · 조회 · 받기 ----------
	@Test
	void 퀘스트를_완료하면_선물이_생기고_받으면_골드가_들어간다() throws Exception {
		String access = onboardedUser(E);
		long before = balance(E);
		pet(access, E);

		assertThat(balance(E)).isEqualTo(before); // 완료만으로는 지갑 그대로
		long id = onlyGift(E);
		as(access, get("/gifts")).andExpect(status().isOk())
			.andExpect(jsonPath("$.gifts", hasSize(1)))
			.andExpect(jsonPath("$.gifts[0].id").value(id))
			.andExpect(jsonPath("$.gifts[0].source").value("QUEST_DAILY"))
			.andExpect(jsonPath("$.gifts[0].title").value("몬스터 쓰다듬기"))
			.andExpect(jsonPath("$.gifts[0].gold").value(1))
			.andExpect(jsonPath("$.gifts[0].itemCode").isEmpty())
			.andExpect(jsonPath("$.gifts[0].quantity").value(0))
			.andExpect(jsonPath("$.gifts[0].createdAt").isNotEmpty());
		as(access, get("/me/status")).andExpect(jsonPath("$.hasGift").value(true));

		claim(access, id).andExpect(status().isOk())
			.andExpect(jsonPath("$.claimedCount").value(1))
			.andExpect(jsonPath("$.goldReceived").value(1))
			.andExpect(jsonPath("$.items", hasSize(0)))
			.andExpect(jsonPath("$.gold").value(before + 1));
		assertThat(balance(E)).isEqualTo(before + 1);
		// 원장 사유 = 출처, ref_id = 선물 id
		assertThat(jdbc.queryForObject("select ref_id from wallet.wallet_ledger where user_id = ? and reason_code = 'QUEST_DAILY'",
				String.class, userIdOf(E))).isEqualTo(String.valueOf(id));
		as(access, get("/gifts")).andExpect(jsonPath("$.gifts", hasSize(0))); // 받은 선물은 안 보인다
		as(access, get("/me/status")).andExpect(jsonPath("$.hasGift").value(false));
	}

	@Test
	void 선물이_없으면_빈_목록이고_점도_없다() throws Exception {
		String access = onboardedUser(E);
		as(access, get("/gifts")).andExpect(status().isOk()).andExpect(jsonPath("$.gifts", hasSize(0)));
		as(access, get("/me/status")).andExpect(jsonPath("$.hasGift").value(false));
	}

	// ---------- 한 번만 ----------
	@Test
	void 이미_받은_선물을_새_요청으로_받으면_409_같은_키_재전송은_첫_200() throws Exception {
		String access = onboardedUser(E);
		pet(access, E);
		long id = onlyGift(E);
		String key = UUID.randomUUID().toString();
		String first = claim(access, id, key).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();

		claim(access, id).andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("GIFT_ALREADY_CLAIMED"));
		String again = claim(access, id, key).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
		for (String field : List.of("$.claimedCount", "$.goldReceived", "$.gold")) { // 저장된 첫 결과 그대로
			assertThat((Object) JsonPath.read(again, field)).isEqualTo(JsonPath.read(first, field));
		}
		assertThat(ledger(E, "QUEST_DAILY")).isEqualTo(1);
	}

	@Test
	void 동시에_두_번_받아도_골드는_한_번() throws Exception {
		String access = onboardedUser(E);
		long before = balance(E);
		pet(access, E);
		long id = onlyGift(E);
		CountDownLatch start = new CountDownLatch(1);
		ExecutorService pool = Executors.newFixedThreadPool(2);
		List<Future<Integer>> results = new ArrayList<>();
		for (int i = 0; i < 2; i++) {
			results.add(pool.submit(() -> {
				start.await();
				return claim(access, id).andReturn().getResponse().getStatus();
			}));
		}
		start.countDown();
		List<Integer> statuses = new ArrayList<>();
		for (Future<Integer> f : results) {
			statuses.add(f.get(20, TimeUnit.SECONDS)); // 교착이면 시간 초과
		}
		pool.shutdown();

		assertThat(statuses).containsExactlyInAnyOrder(200, 409);
		assertThat(balance(E)).isEqualTo(before + 1);
		assertThat(ledger(E, "QUEST_DAILY")).isEqualTo(1);
	}

	// ---------- 모두 받기 ----------
	@Test
	void 모두_받기는_합계를_주고_받을_게_없으면_0개() throws Exception {
		String access = onboardedUser(E);
		long before = balance(E);
		pet(access, E);
		talk(access, E);
		as(access, get("/gifts")).andExpect(jsonPath("$.gifts", hasSize(2)))
			.andExpect(jsonPath("$.gifts[0].title").value("몬스터에게 말 걸기")) // 최신순
			.andExpect(jsonPath("$.gifts[1].title").value("몬스터 쓰다듬기"));

		claimAll(access).andExpect(status().isOk())
			.andExpect(jsonPath("$.claimedCount").value(2))
			.andExpect(jsonPath("$.goldReceived").value(2))
			.andExpect(jsonPath("$.gold").value(before + 2));
		assertThat(ledger(E, "QUEST_DAILY")).isEqualTo(2);

		claimAll(access).andExpect(status().isOk())
			.andExpect(jsonPath("$.claimedCount").value(0))
			.andExpect(jsonPath("$.goldReceived").value(0))
			.andExpect(jsonPath("$.gold").value(before + 2));
	}

	// ---------- 소유권 ----------
	@Test
	void 남의_선물이나_없는_번호는_404() throws Exception {
		String owner = onboardedUser(E);
		pet(owner, E);
		long id = onlyGift(E);
		String other = onboardedUser("other@habit.kr");

		claim(other, id).andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("NOT_FOUND"));
		claim(other, 999_999_999L).andExpect(status().isNotFound());
		as(owner, get("/gifts")).andExpect(jsonPath("$.gifts", hasSize(1))); // 주인 것은 그대로
	}

	// ---------- 아이템 선물 (월간 배지 성실볼 대비) ----------
	@Test
	void 볼_선물을_받으면_가방에_들어가고_원장은_없다() throws Exception {
		String access = onboardedUser(E);
		long before = balance(E);
		jdbc.update("""
			insert into gift.gift (user_id, source_code, source_ref, title, item_code, item_quantity)
			values (?, 'QUEST_WEEKLY', 'test-ball', '성실볼 시험', 'BALL', 1)""", userIdOf(E));
		long id = onlyGift(E);
		as(access, get("/gifts")).andExpect(jsonPath("$.gifts[0].itemCode").value("BALL"))
			.andExpect(jsonPath("$.gifts[0].itemName").value("성실볼"))
			.andExpect(jsonPath("$.gifts[0].quantity").value(1))
			.andExpect(jsonPath("$.gifts[0].gold").value(0));

		String res = claim(access, id).andExpect(status().isOk())
			.andExpect(jsonPath("$.items[0].itemCode").value("BALL"))
			.andExpect(jsonPath("$.items[0].quantity").value(1))
			.andExpect(jsonPath("$.goldReceived").value(0))
			.andReturn().getResponse().getContentAsString();
		int balls = ((Number) JsonPath.read(res, "$.ballCount")).intValue();
		assertThat(balls).isEqualTo(jdbc.queryForObject(
				"select quantity from shop.inventory where user_id = ? and item_code = 'BALL'", Integer.class, userIdOf(E)));
		assertThat(balls).isEqualTo(1);
		as(access, get("/me/status")).andExpect(jsonPath("$.ballCount").value(1));
		assertThat(balance(E)).isEqualTo(before);
		assertThat(ledger(E, "QUEST_WEEKLY")).isZero();
	}

	// ---------- 끄기 스위치 ----------
	@Test
	void 퀘스트를_꺼도_이미_생긴_선물은_받을_수_있다() throws Exception {
		String access = onboardedUser(E);
		pet(access, E);
		long id = onlyGift(E);
		doReturn(false).when(config).questEnabled();
		claim(access, id).andExpect(status().isOk()).andExpect(jsonPath("$.goldReceived").value(1));
	}
}
