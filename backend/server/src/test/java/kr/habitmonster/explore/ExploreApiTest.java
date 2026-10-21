package kr.habitmonster.explore;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import com.jayway.jsonpath.JsonPath;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.monster.Dice;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * 탐색 · 남은 등장 · 볼 던지기 (API 명세 v5 "5. 챗봇 — 탐색", 3-4단계).
 *
 * <p>랜덤은 {@link Dice}를 가짜로 바꿔 고정한다. 굴리는 순서: 탐색 = ① 꽝인지(0.35 미만이면 꽝) ② 어느 종인지, 포획 = ① 잡히는지.
 * 기본 온보딩(운동 · 공부)이면 스타터 불씨 원숭이(1번) · 찌릿 쥐(6번)를 가진 채 시작한다.
 */
class ExploreApiTest extends PostgresTest {

	static final String E = "a@habit.kr";

	@MockitoBean
	Dice dice;

	@MockitoSpyBean
	BusinessDates dates;

	ResultActions as(String access, MockHttpServletRequestBuilder req) throws Exception {
		return mvc.perform(req.header("Authorization", "Bearer " + access));
	}

	ResultActions send(String access, MockHttpServletRequestBuilder req, String key, LocalDate day) throws Exception {
		return as(access, req.header(IdempotencyFilter.HEADER, key).contentType(MediaType.APPLICATION_JSON)
			.content("{\"businessDate\": \"" + day + "\"}"));
	}

	ResultActions explore(String access) throws Exception {
		return send(access, post("/explores"), UUID.randomUUID().toString(), dates.today());
	}

	ResultActions capture(String access, long exploreId) throws Exception {
		return send(access, post("/explores/" + exploreId + "/capture"), UUID.randomUUID().toString(), dates.today());
	}

	static long idOf(ResultActions r) throws Exception {
		return ((Number) JsonPath.read(r.andReturn().getResponse().getContentAsString(), "$.exploreId")).longValue();
	}

	/** 기본 온보딩 + 오늘 체크인(아침 러닝 30분 = 20점, 탐색 3번). */
	String checkedIn(String email) throws Exception {
		String access = onboardedUser(email);
		long habit = jdbc.queryForObject("select h.id from habit.habit h where h.user_id = ?", Long.class, userIdOf(email));
		submitCheckin(access, habit);
		return access;
	}

	void submitCheckin(String access, long habitId) throws Exception {
		as(access, post("/checkins/today").header(IdempotencyFilter.HEADER, UUID.randomUUID().toString())
			.contentType(MediaType.APPLICATION_JSON)
			.content("{\"businessDate\": \"" + dates.today() + "\", \"answers\": [{\"habitId\": " + habitId
					+ ", \"done\": true, \"value\": 30}]}"))
			.andExpect(status().isCreated());
	}

	/** 운동 · 공부를 Lv.3으로 → 깡총 불토끼(2번) · 번개뿔 사슴(7번)이 후보가 된다. */
	void level3(String email) {
		jdbc.update("update habit.user_category set exp_total = 30, level = 3 where user_id = ?", userIdOf(email));
	}

	void balls(String email, int n) {
		jdbc.update("insert into shop.inventory (user_id, item_code, quantity) values (?, 'BALL', ?)", userIdOf(email), n);
	}

	int ballCount(String email) {
		return jdbc.queryForObject("select quantity from shop.inventory where user_id = ? and item_code = 'BALL'", Integer.class,
				userIdOf(email));
	}

	long gold(String email) {
		return jdbc.queryForObject("select balance from wallet.wallet where user_id = ?", Long.class, userIdOf(email));
	}

	String outcomeOf(long exploreId) {
		return jdbc.queryForObject("select outcome from monster.explore_log where id = ?", String.class, exploreId);
	}

	/** Lv.3 후보(종 번호 순): 원숭이 60 · 불토끼 60×2 · 쥐 60 · 사슴 60×2 = 360. 0.3 → 108 = 불토끼, 0.9 → 324 = 사슴. */
	static final double RABBIT = 0.3, DEER = 0.9, NOT_MISS = 0.5, MISS = 0.1;

	// ---------- 탐색 ----------
	@Test
	void 꽝() throws Exception {
		String access = checkedIn(E);
		when(dice.roll()).thenReturn(MISS);
		explore(access).andExpect(status().isCreated())
			.andExpect(jsonPath("$.result").value("MISS"))
			.andExpect(jsonPath("$.species").isEmpty())
			.andExpect(jsonPath("$.newlySeen").value(false))
			.andExpect(jsonPath("$.goldAwarded").value(0))
			.andExpect(jsonPath("$.exploreRemaining").value(2));
	}

	@Test
	void 가진_종은_볼_없이_15G() throws Exception {
		String access = checkedIn(E); // Lv.2라 후보는 스타터 둘뿐 → 가진 종
		long before = gold(E);
		when(dice.roll()).thenReturn(NOT_MISS, 0.0);
		long id = idOf(explore(access).andExpect(status().isCreated())
			.andExpect(jsonPath("$.result").value("DUPLICATE"))
			.andExpect(jsonPath("$.species.speciesId").value(1))
			.andExpect(jsonPath("$.species.imageKey").value("monkey"))
			.andExpect(jsonPath("$.species.captureRate").isEmpty())
			.andExpect(jsonPath("$.goldAwarded").value(15))
			.andExpect(jsonPath("$.gold").value(before + 15)));
		assertThat(gold(E)).isEqualTo(before + 15);
		assertThat(jdbc.queryForObject("select amount from wallet.wallet_ledger where reason_code = 'DUPLICATE' and ref_id = ?",
				Integer.class, String.valueOf(id))).isEqualTo(15);
	}

	@Test
	void 안_가진_종은_등장_처음만_newlySeen_다시_탐색하면_SKIPPED() throws Exception {
		String access = checkedIn(E);
		level3(E);
		when(dice.roll()).thenReturn(NOT_MISS, RABBIT, NOT_MISS, RABBIT);
		long first = idOf(explore(access).andExpect(status().isCreated())
			.andExpect(jsonPath("$.result").value("ENCOUNTER"))
			.andExpect(jsonPath("$.species.speciesId").value(2))
			.andExpect(jsonPath("$.species.name").value("깡총 불토끼"))
			.andExpect(jsonPath("$.species.rarity").value(1))
			.andExpect(jsonPath("$.species.captureRate").value(0.8))
			.andExpect(jsonPath("$.newlySeen").value(true))
			.andExpect(jsonPath("$.skippedExploreId").isEmpty()));

		as(access, get("/explores/pending")).andExpect(status().isOk())
			.andExpect(jsonPath("$.exploreId").value(first))
			.andExpect(jsonPath("$.newlySeen").value(false))
			.andExpect(jsonPath("$.exploreRemaining").value(2));

		explore(access).andExpect(status().isCreated())
			.andExpect(jsonPath("$.species.speciesId").value(2))
			.andExpect(jsonPath("$.newlySeen").value(false)) // 두 번째 만남
			.andExpect(jsonPath("$.skippedExploreId").value(first))
			.andExpect(jsonPath("$.exploreRemaining").value(1));
		assertThat(outcomeOf(first)).isEqualTo("SKIPPED");
	}

	@Test
	void 기회를_다_쓰면_422() throws Exception {
		String access = checkedIn(E);
		when(dice.roll()).thenReturn(MISS);
		for (int i = 0; i < 3; i++) {
			explore(access).andExpect(status().isCreated());
		}
		explore(access).andExpect(status().isUnprocessableContent())
			.andExpect(jsonPath("$.code").value("NO_EXPLORE_LEFT"));
		assertThat(jdbc.queryForObject("select used_count from monster.daily_explore_quota", Integer.class)).isEqualTo(3);
	}

	@Test
	void 체크인_전이면_409() throws Exception {
		String access = onboardedUser(E);
		explore(access).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("CHECKIN_REQUIRED"));
	}

	@Test
	void 날짜가_다르면_409() throws Exception {
		String access = checkedIn(E);
		send(access, post("/explores"), UUID.randomUUID().toString(), dates.today().minusDays(1))
			.andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("BUSINESS_DATE_CHANGED"));
	}

	@Test
	void 같은_키로_다시_보내면_첫_결과_그대로() throws Exception {
		String access = checkedIn(E);
		when(dice.roll()).thenReturn(MISS);
		String key = UUID.randomUUID().toString();
		long first = idOf(send(access, post("/explores"), key, dates.today()).andExpect(status().isCreated()));
		send(access, post("/explores"), key, dates.today()).andExpect(status().isCreated())
			.andExpect(jsonPath("$.exploreId").value(first))
			.andExpect(jsonPath("$.exploreRemaining").value(2));
		assertThat(jdbc.queryForObject("select count(*) from monster.explore_log", Integer.class)).isEqualTo(1);
	}

	@Test
	void 남은_등장이_없으면_204() throws Exception {
		String access = checkedIn(E);
		as(access, get("/explores/pending")).andExpect(status().isNoContent());
	}

	// ---------- 볼 던지기 ----------
	@Test
	void 잡으면_필드로_도감_등록_볼_1개() throws Exception {
		String access = checkedIn(E);
		level3(E);
		balls(E, 3);
		when(dice.roll()).thenReturn(NOT_MISS, RABBIT, 0.1); // 0.1 < 포획률 0.8
		long id = idOf(explore(access));
		capture(access, id).andExpect(status().isOk())
			.andExpect(jsonPath("$.outcome").value("CAPTURED"))
			.andExpect(jsonPath("$.monster.name").value("깡총 불토끼"))
			.andExpect(jsonPath("$.monster.imageKey").value("rabbit"))
			.andExpect(jsonPath("$.monster.location").value("FIELD"))
			.andExpect(jsonPath("$.ballCount").value(2))
			.andExpect(jsonPath("$.dex.dexCount").value(3))
			.andExpect(jsonPath("$.dex.newSlotAvailable").value(false));
		assertThat(outcomeOf(id)).isEqualTo("CAPTURED");
		assertThat(jdbc.queryForObject("select count(*) from shop.item_consumption where consumer_key like 'CAPTURE:%'",
				Integer.class)).isEqualTo(1);
		as(access, get("/explores/pending")).andExpect(status().isNoContent());
	}

	@Test
	void 놓치면_도망가고_다시_던질_수_없다() throws Exception {
		String access = checkedIn(E);
		level3(E);
		balls(E, 3);
		when(dice.roll()).thenReturn(NOT_MISS, RABBIT, 0.9); // 0.9 ≥ 0.8
		long id = idOf(explore(access));
		capture(access, id).andExpect(status().isOk())
			.andExpect(jsonPath("$.outcome").value("ESCAPED"))
			.andExpect(jsonPath("$.monster").isEmpty())
			.andExpect(jsonPath("$.ballCount").value(2))
			.andExpect(jsonPath("$.dex.dexCount").value(2));
		capture(access, id).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("ENCOUNTER_CLOSED"));
		assertThat(ballCount(E)).isEqualTo(2);
	}

	@Test
	void 볼이_없으면_422_등장은_남는다() throws Exception {
		String access = checkedIn(E);
		level3(E);
		when(dice.roll()).thenReturn(NOT_MISS, RABBIT);
		long id = idOf(explore(access));
		capture(access, id).andExpect(status().isUnprocessableContent()).andExpect(jsonPath("$.code").value("NO_BALL"));
		assertThat(outcomeOf(id)).isNull();
		as(access, get("/explores/pending")).andExpect(status().isOk());
	}

	@Test
	void 꽝이나_가진_종에는_던질_수_없다() throws Exception {
		String access = checkedIn(E);
		balls(E, 3);
		when(dice.roll()).thenReturn(MISS, NOT_MISS, 0.0);
		long miss = idOf(explore(access));
		long duplicate = idOf(explore(access));
		capture(access, miss).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("ENCOUNTER_CLOSED"));
		capture(access, duplicate).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("ENCOUNTER_CLOSED"));
		assertThat(ballCount(E)).isEqualTo(3);
	}

	@Test
	void 남의_탐색에_던지면_404() throws Exception {
		String mine = checkedIn(E);
		level3(E);
		when(dice.roll()).thenReturn(NOT_MISS, RABBIT);
		long id = idOf(explore(mine));
		String other = checkedIn("b@habit.kr");
		balls("b@habit.kr", 3);
		capture(other, id).andExpect(status().isNotFound());
		assertThat(outcomeOf(id)).isNull();
	}

	@Test
	void 날짜가_바뀌면_어제_등장은_던질_수_없고_다음_탐색에서_EXPIRED() throws Exception {
		String access = checkedIn(E);
		level3(E);
		balls(E, 3);
		when(dice.roll()).thenReturn(NOT_MISS, RABBIT, MISS);
		long yesterday = idOf(explore(access));

		doReturn(dates.today().plusDays(1)).when(dates).today(); // 다음 날
		as(access, get("/explores/pending")).andExpect(status().isNoContent());
		capture(access, yesterday).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("ENCOUNTER_CLOSED"));
		submitCheckin(access, jdbc.queryForObject("select id from habit.habit", Long.class));
		explore(access).andExpect(status().isCreated())
			.andExpect(jsonPath("$.skippedExploreId").isEmpty()); // 지난 날 등장은 넘긴 게 아니라 만료
		assertThat(outcomeOf(yesterday)).isEqualTo("EXPIRED");
		assertThat(ballCount(E)).isEqualTo(3);
	}

	@Test
	void 같은_등장에_다른_키로_동시에_두_번_던져도_볼은_하나() throws Exception {
		String access = checkedIn(E);
		level3(E);
		balls(E, 3);
		when(dice.roll()).thenReturn(NOT_MISS, RABBIT, 0.9); // 놓침
		long id = idOf(explore(access));
		CountDownLatch start = new CountDownLatch(1);
		ExecutorService pool = Executors.newFixedThreadPool(2);
		List<Future<Integer>> results = new ArrayList<>();
		for (int i = 0; i < 2; i++) {
			results.add(pool.submit(() -> {
				start.await();
				return capture(access, id).andReturn().getResponse().getStatus();
			}));
		}
		start.countDown();
		List<Integer> statuses = new ArrayList<>();
		for (Future<Integer> f : results) {
			statuses.add(f.get(20, TimeUnit.SECONDS));
		}
		pool.shutdown();

		assertThat(statuses).containsExactlyInAnyOrder(200, 409);
		assertThat(ballCount(E)).isEqualTo(2);
		assertThat(jdbc.queryForObject("select count(*) from shop.item_consumption", Integer.class)).isEqualTo(1);
	}

	@Test
	void 가진_종_5마리째에_해금권_한_번_필드가_꽉_차면_가방() throws Exception {
		String access = checkedIn(E);
		level3(E);
		balls(E, 3);
		long user = userIdOf(E);
		// 이미 횃불 닭(3) · 천둥 백조(8)도 가진 상태로: 도감 4 · 필드 4
		for (int species : new int[] { 3, 8 }) {
			jdbc.update("insert into monster.user_monster (user_id, species_id, location, acquired_via) values (?, ?, 'FIELD', 'EXPLORE')",
					user, species);
			jdbc.update("insert into monster.dex_entry (user_id, species_id) values (?, ?)", user, species);
		}
		jdbc.update("update monster.monster_user set dex_count = 4 where user_id = ?", user);

		when(dice.roll()).thenReturn(NOT_MISS, RABBIT, 0.1, NOT_MISS, DEER, 0.1);
		capture(access, idOf(explore(access))).andExpect(status().isOk())
			.andExpect(jsonPath("$.monster.location").value("FIELD"))
			.andExpect(jsonPath("$.dex.dexCount").value(5))
			.andExpect(jsonPath("$.dex.newSlotAvailable").value(true));
		capture(access, idOf(explore(access))).andExpect(status().isOk())
			.andExpect(jsonPath("$.monster.name").value("번개뿔 사슴"))
			.andExpect(jsonPath("$.monster.location").value("BAG")) // 필드 5마리
			.andExpect(jsonPath("$.dex.dexCount").value(6))
			.andExpect(jsonPath("$.dex.newSlotAvailable").value(false));
		assertThat(jdbc.queryForList("select milestone from habit.category_unlock_ticket where user_id = ?", Integer.class, user))
			.containsExactly(5);
	}
}
