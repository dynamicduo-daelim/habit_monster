package kr.habitmonster.quest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doReturn;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;
import java.util.List;
import java.util.UUID;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * 퀘스트 3단계 — 주간 퀘스트 (API 명세 v9 10장, 결정 D-88). 진행도는 이번 주 출석 · 체크인 기록에서 계산한다.
 * 날짜는 다음 주 월요일부터 하루씩 옮겨 가며 흉내 낸다 (습관은 그 전에 만들어져 있으므로 체크인할 수 있다).
 * 기본 온보딩은 카테고리 2개(운동 · 공부)라 카테고리 퀘스트가 잠겨 있다.
 */
class QuestWeeklyApiTest extends PostgresTest {

	static final String E = "w@habit.kr";

	/** 카테고리 3개 — 걷기(운동, 30분) · 전공 공부(공부, 60분) · 영양제(식습관, O/X). */
	static final String THREE_CATEGORIES = """
		{"categories": ["ex", "st", "fd"],
		 "habits": [
		   {"categoryCode": "ex", "measureTypeId": 1, "name": "걷기", "dailyTarget": 30, "periodCode": "D30"},
		   {"categoryCode": "st", "measureTypeId": 4, "name": "전공 공부", "dailyTarget": 60, "periodCode": "D30"},
		   {"categoryCode": "fd", "measureTypeId": 9, "name": "영양제", "dailyTarget": 1, "periodCode": "D30"}],
		 "goals": [{"goalType": "WEEKLY", "title": "헬스장 3번 가기"}]}""";

	@MockitoSpyBean
	BusinessDates dates;

	@MockitoSpyBean
	BalanceConfig config;

	LocalDate monday;

	@BeforeEach
	void nextMonday() {
		monday = dates.today().with(TemporalAdjusters.next(DayOfWeek.MONDAY));
	}

	/** 그 주의 n번째 날 (0 = 월요일)로 옮긴다. */
	void day(int n) {
		doReturn(monday.plusDays(n)).when(dates).today();
	}

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

	void attend(String access) throws Exception {
		as(access, post("/me/attendance")).andExpect(status().isOk());
	}

	ResultActions checkin(String access, MockHttpServletRequestBuilder req, String... answers) throws Exception {
		return send(access, req, "{\"businessDate\": \"" + dates.today() + "\", \"answers\": [" + String.join(",", answers) + "]}");
	}

	String done(String name, Object value) {
		return "{\"habitId\": " + habit(name) + ", \"done\": true, \"value\": " + value + "}";
	}

	String missed(String name) {
		return "{\"habitId\": " + habit(name) + ", \"done\": false}";
	}

	long habit(String name) {
		return jdbc.queryForObject("select id from habit.habit where user_id = ? and name = ?", Long.class, userIdOf(E),
				name);
	}

	/** 주간 퀘스트 보상으로 생긴 선물 금액 (v10부터 선물함으로, D-89). */
	List<Integer> weeklyGold() {
		return jdbc.queryForList("select gold from gift.gift where user_id = ? and source_code = 'QUEST_WEEKLY'",
				Integer.class, userIdOf(E));
	}

	String threeCategoryUser() throws Exception {
		String access = signUp(E);
		onboard(access, THREE_CATEGORIES).andExpect(status().isCreated());
		return access;
	}

	// ---------- 조회 ----------
	@Test
	void 이번_주_3개가_월요일부터() throws Exception {
		String access = onboardedUser(E);
		day(2); // 수요일
		quests(access).andExpect(status().isOk())
			.andExpect(jsonPath("$.weekStart").value(monday.toString()))
			.andExpect(jsonPath("$.weekly.length()").value(3))
			.andExpect(jsonPath("$.weekly[0].code").value("WEEKLY_ATTEND"))
			.andExpect(jsonPath("$.weekly[0].title").value("주 4일 출석"))
			.andExpect(jsonPath("$.weekly[0].target").value(4))
			.andExpect(jsonPath("$.weekly[0].rewardGold").value(5))
			.andExpect(jsonPath("$.weekly[0].status").value("IN_PROGRESS"))
			.andExpect(jsonPath("$.weekly[1].code").value("WEEKLY_GOOD_DAYS"))
			.andExpect(jsonPath("$.weekly[1].target").value(2))
			.andExpect(jsonPath("$.weekly[2].code").value("WEEKLY_CATEGORIES"))
			.andExpect(jsonPath("$.weekly[2].status").value("LOCKED")) // 기본 온보딩은 카테고리 2개
			.andExpect(jsonPath("$.weekly[2].lockReason").value("NOT_ENOUGH_CATEGORIES"));
	}

	// ---------- B1 출석 ----------
	@Test
	void 출석은_연속이_아니어도_4일이면_완료() throws Exception {
		String access = onboardedUser(E);
		for (int d : new int[] { 0, 2, 4 }) { // 월 · 수 · 금
			day(d);
			attend(access);
			attend(access); // 같은 날 두 번은 하루
		}
		quests(access).andExpect(jsonPath("$.weekly[0].progress").value(3))
			.andExpect(jsonPath("$.weekly[0].status").value("IN_PROGRESS"));
		assertThat(weeklyGold()).isEmpty();

		day(6); // 일요일
		attend(access);
		quests(access).andExpect(jsonPath("$.weekly[0].progress").value(4))
			.andExpect(jsonPath("$.weekly[0].status").value("DONE"));
		assertThat(weeklyGold()).containsExactly(5);
	}

	@Test
	void 주가_바뀌면_새로_센다() throws Exception {
		String access = onboardedUser(E);
		for (int d = 0; d < 4; d++) {
			day(d);
			attend(access);
		}
		quests(access).andExpect(jsonPath("$.weekly[0].status").value("DONE"));

		day(7); // 다음 주 월요일
		attend(access);
		quests(access).andExpect(jsonPath("$.weekStart").value(monday.plusDays(7).toString()))
			.andExpect(jsonPath("$.weekly[0].progress").value(1))
			.andExpect(jsonPath("$.weekly[0].status").value("IN_PROGRESS"));
		assertThat(weeklyGold()).containsExactly(5);
	}

	@Test
	void 퀘스트를_주_중간에_켜도_그_주_출석을_센다() throws Exception {
		String access = onboardedUser(E);
		doReturn(false).when(config).questEnabled();
		for (int d = 0; d < 3; d++) {
			day(d);
			attend(access);
		}
		assertThat(jdbc.queryForObject("select count(*) from quest.user_quest", Integer.class)).isZero();

		doReturn(true).when(config).questEnabled();
		day(3);
		attend(access); // 기록에서 계산하므로 꺼져 있던 월 ~ 수도 센다
		quests(access).andExpect(jsonPath("$.weekly[0].progress").value(4))
			.andExpect(jsonPath("$.weekly[0].status").value("DONE"));
		assertThat(weeklyGold()).containsExactly(5);
	}

	// ---------- B2 성실도 좋은 날 ----------
	@Test
	void 성실도_좋은_날은_첫_제출_기준이라_다시_체크로_늘지_않는다() throws Exception {
		String access = onboardedUser(E);
		day(0);
		checkin(access, post("/checkins/today"), done("아침 러닝", 30)).andExpect(status().isCreated()); // 100%
		quests(access).andExpect(jsonPath("$.weekly[1].progress").value(1));

		day(1);
		checkin(access, post("/checkins/today"), missed("아침 러닝")).andExpect(status().isCreated()); // 0%
		checkin(access, put("/checkins/today"), done("아침 러닝", 30)).andExpect(status().isOk()); // 다시 체크로 100%
		quests(access).andExpect(jsonPath("$.weekly[1].progress").value(1)); // 그대로

		day(3);
		checkin(access, post("/checkins/today"), done("아침 러닝", 30)).andExpect(status().isCreated());
		quests(access).andExpect(jsonPath("$.weekly[1].progress").value(2))
			.andExpect(jsonPath("$.weekly[1].status").value("DONE"));
		assertThat(weeklyGold()).containsExactly(5);
	}

	@Test
	void 성실도_기준_N은_설정값() throws Exception {
		String access = onboardedUser(E);
		doReturn(101).when(config).questWeeklyRateThreshold(); // 100%로도 못 넘게
		day(0);
		checkin(access, post("/checkins/today"), done("아침 러닝", 30)).andExpect(status().isCreated());
		quests(access).andExpect(jsonPath("$.weekly[1].progress").value(0));
	}

	// ---------- B3 카테고리 ----------
	@Test
	void 서로_다른_카테고리_3곳을_했어로_체크인하면_완료() throws Exception {
		String access = threeCategoryUser();
		day(0);
		checkin(access, post("/checkins/today"), done("걷기", 30), missed("전공 공부"), missed("영양제"))
			.andExpect(status().isCreated());
		day(1);
		checkin(access, post("/checkins/today"), done("걷기", 30), done("전공 공부", 60), missed("영양제"))
			.andExpect(status().isCreated());
		quests(access).andExpect(jsonPath("$.weekly[2].status").value("IN_PROGRESS"))
			.andExpect(jsonPath("$.weekly[2].progress").value(2)); // 같은 카테고리를 두 번 해도 1곳

		day(2);
		checkin(access, post("/checkins/today"), missed("걷기"), missed("전공 공부"), done("영양제", 1))
			.andExpect(status().isCreated());
		quests(access).andExpect(jsonPath("$.weekly[2].progress").value(3))
			.andExpect(jsonPath("$.weekly[2].status").value("DONE"));
		assertThat(weeklyGold()).contains(5);
	}

	@Test
	void 카테고리가_모자라면_잠기고_주_중간에_열면_그_주_기록도_센다() throws Exception {
		String access = onboardedUser(E); // 운동 · 공부
		day(0);
		send(access, post("/habits"), """
			{"categoryCode": "st", "measureTypeId": 4, "name": "전공 공부", "dailyTarget": 60, "periodCode": "D30"}""")
			.andExpect(status().isCreated());
		checkin(access, post("/checkins/today"), done("아침 러닝", 30), done("전공 공부", 60)).andExpect(status().isCreated());
		quests(access).andExpect(jsonPath("$.weekly[2].status").value("LOCKED"))
			.andExpect(jsonPath("$.weekly[2].progress").value(0)); // 잠겨 있으면 계산 안 함

		day(1); // 해금권으로 식습관을 연다
		jdbc.update("insert into habit.category_unlock_ticket (user_id, milestone) values (?, 5)", userIdOf(E));
		send(access, post("/categories/fd/unlock"), "").andExpect(status().isCreated());
		quests(access).andExpect(jsonPath("$.weekly[2].status").value("IN_PROGRESS"))
			.andExpect(jsonPath("$.weekly[2].progress").value(2)); // 월요일 기록(운동 · 공부)도 센다

		send(access, post("/habits"), """
			{"categoryCode": "fd", "measureTypeId": 9, "name": "영양제", "dailyTarget": 1, "periodCode": "D30"}""")
			.andExpect(status().isCreated());
		checkin(access, post("/checkins/today"), missed("아침 러닝"), missed("전공 공부"), done("영양제", 1))
			.andExpect(status().isCreated());
		quests(access).andExpect(jsonPath("$.weekly[2].status").value("DONE"));
	}
}
