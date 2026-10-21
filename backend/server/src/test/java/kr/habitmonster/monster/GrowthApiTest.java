package kr.habitmonster.monster;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
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

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Test;
import org.skyscreamer.jsonassert.JSONAssert;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * 성장 · 교감 (API 명세 v5 "3. 메인 화면", 3-5단계): 간식(물약) · 쓰다듬기/놀아주기 · 말 걸기 · 필드/가방 · 대화 상대.
 * 기본 온보딩이면 스타터 불씨 원숭이(1번) · 찌릿 쥐(6번)가 필드에 있고 호감도 3 (설정 {@code starter_affection}).
 */
class GrowthApiTest extends PostgresTest {

	static final String E = "a@habit.kr";

	@MockitoBean
	Dice dice;

	@MockitoSpyBean
	BusinessDates dates;

	ResultActions as(String access, MockHttpServletRequestBuilder req) throws Exception {
		return mvc.perform(req.header("Authorization", "Bearer " + access));
	}

	ResultActions json(String access, MockHttpServletRequestBuilder req, String body) throws Exception {
		return as(access, req.contentType(MediaType.APPLICATION_JSON).content(body));
	}

	ResultActions feed(String access, long monster, String key, String item) throws Exception {
		return json(access, post("/monsters/" + monster + "/feed").header(IdempotencyFilter.HEADER, key),
				"{\"itemCode\": \"" + item + "\"}");
	}

	ResultActions feed(String access, long monster, String item) throws Exception {
		return feed(access, monster, UUID.randomUUID().toString(), item);
	}

	ResultActions act(String access, long monster, String action) throws Exception {
		return json(access, post("/monsters/" + monster + "/affection"), "{\"action\": \"" + action + "\"}");
	}

	ResultActions move(String access, long monster, String location) throws Exception {
		return json(access, patch("/monsters/" + monster + "/location"), "{\"location\": \"" + location + "\"}");
	}

	/** 그 사용자의 그 종 몬스터 id. */
	long monster(String email, int speciesId) {
		return jdbc.queryForObject("select id from monster.user_monster where user_id = ? and species_id = ?", Long.class,
				userIdOf(email), speciesId);
	}

	void potions(String email, String item, int n) {
		jdbc.update("insert into shop.inventory (user_id, item_code, quantity) values (?, ?, ?)", userIdOf(email), item, n);
	}

	int potionCount(String item) {
		return jdbc.queryForObject("select quantity from shop.inventory where user_id = ? and item_code = ?", Integer.class,
				userIdOf(E), item);
	}

	int affection(long monster) {
		return jdbc.queryForObject("select affection from monster.user_monster where id = ?", Integer.class, monster);
	}

	// ---------- 간식(물약) ----------
	@Test
	void 물약을_먹이면_경험치_레벨_성장_기록() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(E, 1);
		potions(E, "POTION_L", 2);
		feed(access, monkey, "POTION_L").andExpect(status().isOk()) // 500 EXP ÷ 125 → Lv.5
			.andExpect(jsonPath("$.expGained").value(500))
			.andExpect(jsonPath("$.levelBefore").value(1))
			.andExpect(jsonPath("$.levelAfter").value(5))
			.andExpect(jsonPath("$.stageBefore").value(0))
			.andExpect(jsonPath("$.stageAfter").value(0))
			.andExpect(jsonPath("$.evolved").value(false))
			.andExpect(jsonPath("$.remainingQuantity").value(1));
		as(access, get("/monsters/" + monkey)).andExpect(jsonPath("$.level").value(5))
			.andExpect(jsonPath("$.expInLevel").value(0));
		assertThat(jdbc.queryForObject("select level_after from monster.monster_growth_log", Integer.class)).isEqualTo(5);
		assertThat(jdbc.queryForObject("select count(*) from shop.item_consumption where consumer_key like 'FEED:%'",
				Integer.class)).isEqualTo(1);
	}

	@Test
	void Lv10에_닿으면_진화() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(E, 1);
		jdbc.update("update monster.user_monster set exp_total = 1100, level = 9 where id = ?", monkey);
		potions(E, "POTION_M", 1);
		feed(access, monkey, "POTION_M").andExpect(status().isOk()) // 1100 + 100 = 1200 → Lv.10 = 1차 진화
			.andExpect(jsonPath("$.levelAfter").value(10))
			.andExpect(jsonPath("$.stageAfter").value(1))
			.andExpect(jsonPath("$.evolved").value(true));
	}

	@Test
	void 최대_레벨이면_422_물약은_그대로() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(E, 1);
		jdbc.update("update monster.user_monster set exp_total = 2375, level = 20 where id = ?", monkey);
		potions(E, "POTION_S", 1);
		feed(access, monkey, "POTION_S").andExpect(status().isUnprocessableContent())
			.andExpect(jsonPath("$.code").value("MAX_LEVEL"));
		assertThat(potionCount("POTION_S")).isEqualTo(1);
	}

	@Test
	void 물약이_없으면_422_물약이_아니면_400() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(E, 1);
		feed(access, monkey, "POTION_S").andExpect(status().isUnprocessableContent())
			.andExpect(jsonPath("$.code").value("NO_ITEM"));
		feed(access, monkey, "BALL").andExpect(status().isBadRequest());
	}

	@Test
	void 같은_키로_다시_보내면_물약은_한_개만() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(E, 1);
		potions(E, "POTION_S", 3);
		String key = UUID.randomUUID().toString();
		String first = feed(access, monkey, key, "POTION_S").andExpect(status().isOk()).andReturn().getResponse()
			.getContentAsString();
		String again = feed(access, monkey, key, "POTION_S").andExpect(status().isOk()).andReturn().getResponse()
			.getContentAsString();
		JSONAssert.assertEquals(first, again, true); // 재전송은 저장해 둔 첫 응답 (JSON 필드 순서만 다를 수 있음)
		assertThat(potionCount("POTION_S")).isEqualTo(2);
	}

	// ---------- 교감 ----------
	@Test
	void 쓰다듬기_놀아주기는_하루_한_번씩() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(E, 1);
		act(access, monkey, "PET").andExpect(status().isOk()) // 3 + 2 = 5 → MID (4 이상)
			.andExpect(jsonPath("$.gain").value(2))
			.andExpect(jsonPath("$.affection").value(5))
			.andExpect(jsonPath("$.affectionTier").value("MID"));
		act(access, monkey, "PET").andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("ALREADY_DONE_TODAY"));
		act(access, monkey, "PLAY").andExpect(status().isOk()).andExpect(jsonPath("$.gain").value(1));
		as(access, get("/monsters/" + monkey)).andExpect(jsonPath("$.todayActions.pet").value(true))
			.andExpect(jsonPath("$.todayActions.play").value(true));
		assertThat(affection(monkey)).isEqualTo(6);

		doReturn(dates.today().plusDays(1)).when(dates).today(); // 다음 날엔 다시
		act(access, monkey, "PET").andExpect(status().isOk()).andExpect(jsonPath("$.affection").value(8));
	}

	@Test
	void 호감도가_최대면_gain_0() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(E, 1);
		jdbc.update("update monster.user_monster set affection = 10 where id = ?", monkey);
		act(access, monkey, "PET").andExpect(status().isOk())
			.andExpect(jsonPath("$.gain").value(0))
			.andExpect(jsonPath("$.affection").value(10))
			.andExpect(jsonPath("$.affectionTier").value("HIGH"));
		act(access, monkey, "PET").andExpect(status().isConflict()); // 0이어도 오늘 한 것
	}

	@Test
	void 다른_행동이면_400() throws Exception {
		String access = onboardedUser(E);
		act(access, monster(E, 1), "DRAG").andExpect(status().isBadRequest()); // 필드 끌기는 명세 · DB에 없음 (D-46)
	}

	@Test
	void 동시에_두_번_쓰다듬어도_한_번만() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(E, 1);
		CountDownLatch start = new CountDownLatch(1);
		ExecutorService pool = Executors.newFixedThreadPool(2);
		List<Future<Integer>> results = new ArrayList<>();
		for (int i = 0; i < 2; i++) {
			results.add(pool.submit(() -> {
				start.await();
				return act(access, monkey, "PET").andReturn().getResponse().getStatus();
			}));
		}
		start.countDown();
		List<Integer> statuses = new ArrayList<>();
		for (Future<Integer> f : results) {
			statuses.add(f.get(20, TimeUnit.SECONDS));
		}
		pool.shutdown();

		assertThat(statuses).containsExactlyInAnyOrder(200, 409);
		assertThat(affection(monkey)).isEqualTo(5);
	}

	// ---------- 말 걸기 ----------
	@Test
	void 말_걸기는_호감도_단계의_대사() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(E, 1);
		String first = jdbc.queryForObject(
				"select line_text from monster.species_line where species_id = 1 and affection_tier = 'LOW' order by id limit 1",
				String.class);
		when(dice.roll()).thenReturn(0.0);
		as(access, get("/monsters/" + monkey + "/line")).andExpect(status().isOk())
			.andExpect(jsonPath("$.affectionTier").value("LOW")) // 호감도 3
			.andExpect(jsonPath("$.line").value(first));
	}

	// ---------- 필드 · 가방 ----------
	@Test
	void 필드에_1마리면_못_넣고_꽉_차면_못_꺼낸다() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(E, 1);
		long mouse = monster(E, 6);
		move(access, monkey, "BAG").andExpect(status().isOk())
			.andExpect(jsonPath("$.location").value("BAG"))
			.andExpect(jsonPath("$.fieldCount").value(1));
		move(access, mouse, "BAG").andExpect(status().isUnprocessableContent())
			.andExpect(jsonPath("$.code").value("FIELD_LIMIT"));
		move(access, monkey, "FIELD").andExpect(status().isOk()).andExpect(jsonPath("$.fieldCount").value(2));

		long user = userIdOf(E);
		for (int species : new int[] { 2, 3, 7 }) { // 필드 5마리로
			jdbc.update("insert into monster.user_monster (user_id, species_id, location, acquired_via) values (?, ?, 'FIELD', 'EXPLORE')",
					user, species);
		}
		jdbc.update("insert into monster.user_monster (user_id, species_id, location, acquired_via) values (?, 8, 'BAG', 'EXPLORE')", user);
		move(access, monster(E, 8), "FIELD").andExpect(status().isUnprocessableContent())
			.andExpect(jsonPath("$.code").value("FIELD_LIMIT"));
		move(access, monkey, "SKY").andExpect(status().isBadRequest());
	}

	// ---------- 대화 상대 ----------
	@Test
	void 대화_상대는_한_마리_가방에_있어도_된다() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(E, 1);
		long mouse = monster(E, 6);
		long other = jdbc.queryForObject("select id from monster.user_monster where user_id = ? and not is_partner", Long.class,
				userIdOf(E));
		move(access, other, "BAG").andExpect(status().isOk());
		json(access, put("/me/partner"), "{\"userMonsterId\": " + other + "}").andExpect(status().isOk())
			.andExpect(jsonPath("$.partnerMonsterId").value(other));
		assertThat(jdbc.queryForList("select id from monster.user_monster where user_id = ? and is_partner", Long.class,
				userIdOf(E))).containsExactly(other);
		assertThat(List.of(monkey, mouse)).contains(other);
	}

	@Test
	void 남의_몬스터는_404() throws Exception {
		onboardedUser(E);
		long monkey = monster(E, 1);
		String other = onboardedUser("b@habit.kr");
		potions("b@habit.kr", "POTION_S", 1);
		feed(other, monkey, "POTION_S").andExpect(status().isNotFound());
		act(other, monkey, "PET").andExpect(status().isNotFound());
		as(other, get("/monsters/" + monkey + "/line")).andExpect(status().isNotFound());
		move(other, monkey, "BAG").andExpect(status().isNotFound());
		json(other, put("/me/partner"), "{\"userMonsterId\": " + monkey + "}").andExpect(status().isNotFound());
		assertThat(affection(monkey)).isEqualTo(3);
	}
}
