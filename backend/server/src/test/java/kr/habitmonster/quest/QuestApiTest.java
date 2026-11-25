package kr.habitmonster.quest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.hamcrest.Matchers.hasSize;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.doThrow;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
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
import kr.habitmonster.config.BalanceConfig;
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
 * 퀘스트 2단계 — 일일 퀘스트 (API 명세 v8 10장, 결정 D-85 · D-87).
 * 기본 온보딩이면 "아침 러닝"(운동 시간, 분 = 시간 습관)이 있어 타이머 퀘스트가 열려 있고, 필드에 원숭이(1번) · 쥐(6번)가 있다.
 */
class QuestApiTest extends PostgresTest {

	static final String E = "q@habit.kr";

	/** 시간 습관 없이 (학습량 p만) — 타이머 퀘스트가 잠긴다. */
	static final String NO_TIMER_ONBOARDING = """
		{"categories": ["ex", "st"],
		 "habits": [{"categoryCode": "st", "measureTypeId": 5, "name": "문제집", "dailyTarget": 20, "periodCode": "D30"}],
		 "goals": [{"goalType": "WEEKLY", "title": "헬스장 3번 가기"}]}""";

	@MockitoBean
	Dice dice;

	@MockitoSpyBean
	BusinessDates dates;

	@MockitoSpyBean
	BalanceConfig config;

	@MockitoSpyBean
	QuestRepository questRepo;

	ResultActions as(String access, MockHttpServletRequestBuilder req) throws Exception {
		return mvc.perform(req.header("Authorization", "Bearer " + access));
	}

	ResultActions send(String access, MockHttpServletRequestBuilder req, String body) throws Exception {
		return as(access, req.header(IdempotencyFilter.HEADER, UUID.randomUUID().toString())
			.contentType(MediaType.APPLICATION_JSON).content(body));
	}

	ResultActions quests(String access) throws Exception {
		return as(access, get("/quests"));
	}

	ResultActions pet(String access, long monster) throws Exception {
		return as(access, post("/monsters/" + monster + "/affection").contentType(MediaType.APPLICATION_JSON)
			.content("{\"action\": \"PET\"}"));
	}

	ResultActions checkin(String access, MockHttpServletRequestBuilder req) throws Exception {
		return send(access, req, "{\"businessDate\": \"" + dates.today() + "\", \"answers\": [{\"habitId\": "
				+ habit("아침 러닝") + ", \"done\": true, \"value\": 30}]}");
	}

	long monster(int speciesId) {
		return jdbc.queryForObject("select id from monster.user_monster where user_id = ? and species_id = ?", Long.class,
				userIdOf(E), speciesId);
	}

	long habit(String name) {
		return jdbc.queryForObject("select id from habit.habit where user_id = ? and name = ?", Long.class, userIdOf(E),
				name);
	}

	/** 퀘스트로 받은 골드 원장 (사유 QUEST_DAILY) — 금액 목록. */
	List<Integer> questGold() {
		return jdbc.queryForList("select amount from wallet.wallet_ledger where user_id = ? and reason_code = 'QUEST_DAILY'",
				Integer.class, userIdOf(E));
	}

	int rows() {
		return jdbc.queryForObject("select count(*) from quest.user_quest where user_id = ?", Integer.class, userIdOf(E));
	}

	// ---------- 조회 ----------
	@Test
	void 첫_조회에_일일_4개가_생기고_다시_조회해도_4개() throws Exception {
		String access = onboardedUser(E);
		quests(access).andExpect(status().isOk())
			.andExpect(jsonPath("$.businessDate").value(dates.today().toString()))
			.andExpect(jsonPath("$.enabled").value(true))
			.andExpect(jsonPath("$.daily", hasSize(4)))
			.andExpect(jsonPath("$.daily[0].code").value("DAILY_CHECKIN"))
			.andExpect(jsonPath("$.daily[0].title").value("오늘의 기록"))
			.andExpect(jsonPath("$.daily[0].rewardGold").value(3))
			.andExpect(jsonPath("$.daily[0].progress").value(0))
			.andExpect(jsonPath("$.daily[0].target").value(1))
			.andExpect(jsonPath("$.daily[0].status").value("IN_PROGRESS"))
			.andExpect(jsonPath("$.daily[0].lockReason").doesNotExist())
			.andExpect(jsonPath("$.daily[1].code").value("DAILY_PET"))
			.andExpect(jsonPath("$.daily[2].code").value("DAILY_TIMER"))
			.andExpect(jsonPath("$.daily[2].status").value("IN_PROGRESS")) // 아침 러닝 = 시간 습관
			.andExpect(jsonPath("$.daily[3].code").value("DAILY_TALK"));
		quests(access).andExpect(jsonPath("$.daily", hasSize(4)));
		assertThat(rows()).isEqualTo(4);
	}

	@Test
	void 날짜가_바뀌면_새_퀘스트() throws Exception {
		String access = onboardedUser(E);
		pet(access, monster(1));
		quests(access).andExpect(jsonPath("$.daily[1].status").value("DONE"));

		LocalDate tomorrow = dates.today().plusDays(1);
		doReturn(tomorrow).when(dates).today();
		quests(access).andExpect(jsonPath("$.businessDate").value(tomorrow.toString()))
			.andExpect(jsonPath("$.daily[1].status").value("IN_PROGRESS"))
			.andExpect(jsonPath("$.daily[1].progress").value(0));
		assertThat(rows()).isEqualTo(8);
	}

	// ---------- 진행 · 지급 ----------
	@Test
	void 체크인_첫_제출이면_오늘의_기록_완료_3G_다시_체크는_무관() throws Exception {
		String access = onboardedUser(E);
		String res = checkin(access, post("/checkins/today")).andExpect(status().isCreated())
			.andReturn().getResponse().getContentAsString();
		long wallet = jdbc.queryForObject("select balance from wallet.wallet where user_id = ?", Long.class, userIdOf(E));
		assertThat(((Number) JsonPath.read(res, "$.gold")).longValue()).isEqualTo(wallet); // 응답 잔액에 퀘스트 3G까지
		assertThat(((Number) JsonPath.read(res, "$.goldEarned")).longValue()).isEqualTo(wallet - 3); // 체크인 보상엔 없음
		quests(access).andExpect(jsonPath("$.daily[0].status").value("DONE"))
			.andExpect(jsonPath("$.daily[0].progress").value(1));
		assertThat(questGold()).containsExactly(3);

		checkin(access, put("/checkins/today")).andExpect(status().isOk());
		assertThat(questGold()).containsExactly(3); // 다시 체크는 퀘스트와 무관
	}

	@Test
	void 쓰다듬기는_한_번만_지급되고_놀아주기_끌기는_세지_않는다() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(1);
		as(access, post("/monsters/" + monkey + "/affection").contentType(MediaType.APPLICATION_JSON)
			.content("{\"action\": \"PLAY\"}")).andExpect(status().isOk());
		as(access, post("/monsters/" + monkey + "/affection").contentType(MediaType.APPLICATION_JSON)
			.content("{\"action\": \"DRAG\"}")).andExpect(status().isOk());
		quests(access).andExpect(jsonPath("$.daily[1].status").value("IN_PROGRESS"));
		assertThat(questGold()).isEmpty();

		pet(access, monkey).andExpect(status().isOk());
		pet(access, monkey).andExpect(status().isConflict()); // 거절된 쓰다듬기는 이벤트 없음
		pet(access, monster(6)).andExpect(status().isOk()); // 다른 몬스터 — 퀘스트는 이미 끝
		quests(access).andExpect(jsonPath("$.daily[1].status").value("DONE"));
		assertThat(questGold()).containsExactly(1);
	}

	@Test
	void 말_걸기면_말_걸기_퀘스트_완료() throws Exception {
		String access = onboardedUser(E);
		as(access, get("/monsters/" + monster(1) + "/line")).andExpect(status().isOk());
		as(access, get("/monsters/" + monster(1) + "/line")).andExpect(status().isOk());
		quests(access).andExpect(jsonPath("$.daily[3].status").value("DONE"));
		assertThat(questGold()).containsExactly(1);
	}

	@Test
	void 타이머를_끝내면_완료_일시정지는_세지_않는다() throws Exception {
		String access = onboardedUser(E);
		String started = send(access, post("/timers"),
				"{\"businessDate\": \"" + dates.today() + "\", \"habitId\": " + habit("아침 러닝") + "}")
			.andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
		long timer = ((Number) JsonPath.read(started, "$.timerId")).longValue();

		send(access, patch("/timers/" + timer), "{\"action\": \"PAUSE\"}").andExpect(status().isOk());
		quests(access).andExpect(jsonPath("$.daily[2].status").value("IN_PROGRESS"));

		send(access, patch("/timers/" + timer), "{\"action\": \"STOP\"}").andExpect(status().isOk()); // 0분이어도
		quests(access).andExpect(jsonPath("$.daily[2].status").value("DONE"));
		assertThat(questGold()).containsExactly(1);
	}

	// ---------- 잠금 ----------
	@Test
	void 시간_습관이_없으면_타이머_퀘스트가_잠기고_등록하면_바로_풀린다() throws Exception {
		String access = signUp(E);
		onboard(access, NO_TIMER_ONBOARDING).andExpect(status().isCreated());
		quests(access).andExpect(jsonPath("$.daily[2].code").value("DAILY_TIMER"))
			.andExpect(jsonPath("$.daily[2].status").value("LOCKED"))
			.andExpect(jsonPath("$.daily[2].lockReason").value("NO_TIMER_HABIT"))
			.andExpect(jsonPath("$.daily[1].status").value("IN_PROGRESS")); // 다른 퀘스트는 그대로

		send(access, post("/habits"), """
			{"categoryCode": "ex", "measureTypeId": 1, "name": "걷기", "dailyTarget": 30, "periodCode": "D30"}""")
			.andExpect(status().isCreated());
		quests(access).andExpect(jsonPath("$.daily[2].status").value("IN_PROGRESS"))
			.andExpect(jsonPath("$.daily[2].lockReason").doesNotExist());
	}

	// ---------- 끄기 스위치 ----------
	@Test
	void 퀘스트를_끄면_조회는_비고_진행_지급도_없다() throws Exception {
		String access = onboardedUser(E);
		doReturn(false).when(config).questEnabled();
		quests(access).andExpect(status().isOk())
			.andExpect(jsonPath("$.enabled").value(false))
			.andExpect(jsonPath("$.daily", hasSize(0)));
		pet(access, monster(1)).andExpect(status().isOk()); // 원래 행동은 그대로 된다
		assertThat(rows()).isZero();
		assertThat(questGold()).isEmpty();
	}

	// ---------- 같은 트랜잭션 (D-85) ----------
	@Test
	void 퀘스트가_실패하면_원래_행동도_취소된다() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(1);
		doThrow(new IllegalStateException("퀘스트 오류 흉내")).when(questRepo).advance(anyLong(), any(), eq("DAILY_PET"));
		// MockMvc는 처리되지 않은 예외를 500 응답 대신 그대로 던진다 (실제 서버에선 500)
		assertThatThrownBy(() -> pet(access, monkey)).hasRootCauseMessage("퀘스트 오류 흉내");
		assertThat(jdbc.queryForObject("select count(*) from monster.affection_action where user_monster_id = ?",
				Integer.class, monkey)).isZero(); // 쓰다듬기 기록도 롤백
		assertThat(jdbc.queryForObject("select affection from monster.user_monster where id = ?", Integer.class, monkey))
			.isEqualTo(5);
	}

	// ---------- 동시성 (D-87) ----------
	@Test
	void 동시에_두_마리를_쓰다듬어도_골드는_한_번() throws Exception {
		String access = onboardedUser(E);
		List<Long> monsters = List.of(monster(1), monster(6));
		CountDownLatch start = new CountDownLatch(1);
		ExecutorService pool = Executors.newFixedThreadPool(2);
		List<Future<Integer>> results = new ArrayList<>();
		for (long m : monsters) {
			results.add(pool.submit(() -> {
				start.await();
				return pet(access, m).andReturn().getResponse().getStatus();
			}));
		}
		start.countDown();
		List<Integer> statuses = new ArrayList<>();
		for (Future<Integer> f : results) {
			statuses.add(f.get(20, TimeUnit.SECONDS));
		}
		pool.shutdown();

		assertThat(statuses).containsExactly(200, 200);
		assertThat(questGold()).containsExactly(1);
		assertThat(rows()).isEqualTo(4); // 두 요청이 동시에 만들어도 한 벌
	}

	@Test
	void 체크인과_쓰다듬기가_동시에_와도_멈추지_않는다() throws Exception {
		String access = onboardedUser(E);
		long monkey = monster(1);
		CountDownLatch start = new CountDownLatch(1);
		ExecutorService pool = Executors.newFixedThreadPool(2);
		Future<Integer> c = pool.submit(() -> {
			start.await();
			return checkin(access, post("/checkins/today")).andReturn().getResponse().getStatus();
		});
		Future<Integer> p = pool.submit(() -> {
			start.await();
			return pet(access, monkey).andReturn().getResponse().getStatus();
		});
		start.countDown();
		assertThat(c.get(20, TimeUnit.SECONDS)).isEqualTo(201); // 교착이면 여기서 시간 초과
		assertThat(p.get(20, TimeUnit.SECONDS)).isEqualTo(200);
		pool.shutdown();
		assertThat(questGold()).containsExactlyInAnyOrder(3, 1);
	}
}
