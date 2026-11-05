package kr.habitmonster.checkin;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
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

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/** 체크인 (API 명세 v5 "5. 챗봇 — 체크인", 3-3단계) — 명세 예시를 그대로 테스트로. */
class CheckinApiTest extends PostgresTest {

	@Autowired
	BusinessDates dates;

	/** 명세 예시의 습관 4개: 스쿼트(횟수 3) · 걷기(30분) · 전공 공부(60분, 기간을 채우는 습관) · 영양제(O/X). */
	static final String SPEC_ONBOARDING = """
		{"categories": ["ex", "st", "fd"],
		 "habits": [
		   {"categoryCode": "ex", "measureTypeId": 2, "name": "스쿼트", "dailyTarget": 3, "periodCode": "D30"},
		   {"categoryCode": "ex", "measureTypeId": 1, "name": "걷기", "dailyTarget": 30, "periodCode": "D30"},
		   {"categoryCode": "st", "measureTypeId": 4, "name": "전공 공부", "dailyTarget": 60, "periodCode": "D30"},
		   {"categoryCode": "fd", "measureTypeId": 9, "name": "영양제", "dailyTarget": 1, "periodCode": "D30"}]}""";

	ResultActions as(String access, MockHttpServletRequestBuilder req) throws Exception {
		return mvc.perform(req.header("Authorization", "Bearer " + access));
	}

	ResultActions send(String access, MockHttpServletRequestBuilder req, String key, String body) throws Exception {
		return as(access, req.header(IdempotencyFilter.HEADER, key).contentType(MediaType.APPLICATION_JSON).content(body));
	}

	ResultActions submit(String access, String answers) throws Exception {
		return send(access, post("/checkins/today"), UUID.randomUUID().toString(), body(dates.today(), answers));
	}

	ResultActions resubmit(String access, String answers) throws Exception {
		return send(access, put("/checkins/today"), UUID.randomUUID().toString(), body(dates.today(), answers));
	}

	static String body(LocalDate day, String answers) {
		return "{\"businessDate\": \"" + day + "\", \"answers\": [" + answers + "]}";
	}

	static String done(long habitId, Object value) {
		return "{\"habitId\": " + habitId + ", \"done\": true, \"value\": " + value + "}";
	}

	static String missed(long habitId) {
		return "{\"habitId\": " + habitId + ", \"done\": false}";
	}

	String user(String email, String onboarding) throws Exception {
		String access = signUp(email);
		onboard(access, onboarding).andExpect(status().isCreated());
		return access;
	}

	long habit(String email, String name) {
		return jdbc.queryForObject("select h.id from habit.habit h join identity.users u on u.id = h.user_id where u.email = ? and h.name = ?",
				Long.class, email, name);
	}

	long gold(String email) {
		return jdbc.queryForObject("select balance from wallet.wallet where user_id = ?", Long.class, userIdOf(email));
	}

	/** 명세 예시 상황: ex Lv.3(경험치 20) · st Lv.8 · fd Lv.5, 전공 공부는 29일을 채워 반영 점수 540, 지갑 340G. */
	String specUser() throws Exception {
		String access = user("a@habit.kr", SPEC_ONBOARDING);
		long user = userIdOf("a@habit.kr");
		jdbc.update("update habit.user_category set exp_total = 50, level = 3 where user_id = ? and category_code = 'ex'", user);
		jdbc.update("update habit.user_category set exp_total = 280, level = 8 where user_id = ? and category_code = 'st'", user);
		jdbc.update("update habit.user_category set exp_total = 100, level = 5 where user_id = ? and category_code = 'fd'", user);
		jdbc.update("update habit.habit_period set filled_days = 29, counted_score_sum = 540 where habit_id = ?",
				habit("a@habit.kr", "전공 공부"));
		jdbc.update("update wallet.wallet set balance = 340 where user_id = ?", user);
		return access;
	}

	String specAnswers() {
		return String.join(",", done(habit("a@habit.kr", "스쿼트"), 2), missed(habit("a@habit.kr", "걷기")),
				done(habit("a@habit.kr", "전공 공부"), 60), done(habit("a@habit.kr", "영양제"), 1));
	}

	@Test
	void 명세_예시_그대로() throws Exception {
		String access = specUser();
		long squat = habit("a@habit.kr", "스쿼트");
		long walk = habit("a@habit.kr", "걷기");
		long study = habit("a@habit.kr", "전공 공부");
		long pill = habit("a@habit.kr", "영양제");

		submit(access, specAnswers()).andExpect(status().isCreated())
			.andExpect(jsonPath("$.revision").value(1))
			.andExpect(jsonPath("$.habits[0].habitId").value(squat))
			.andExpect(jsonPath("$.habits[0].score").value(13))
			.andExpect(jsonPath("$.habits[0].counted").value(true))
			.andExpect(jsonPath("$.habits[1].habitId").value(walk))
			.andExpect(jsonPath("$.habits[1].score").value(0))
			.andExpect(jsonPath("$.habits[1].counted").value(false))
			.andExpect(jsonPath("$.habits[2].score").value(20))
			.andExpect(jsonPath("$.habits[3].score").value(20))
			.andExpect(jsonPath("$.overallRate").value(88))
			.andExpect(jsonPath("$.goldEarned").value(353))
			.andExpect(jsonPath("$.goldBreakdown.score").value(53))
			.andExpect(jsonPath("$.goldBreakdown.levelUp").value(20))
			.andExpect(jsonPath("$.goldBreakdown.periodBonus").value(280))
			.andExpect(jsonPath("$.categoryExp.length()").value(3))
			.andExpect(jsonPath("$.categoryExp[0].categoryCode").value("ex"))
			.andExpect(jsonPath("$.categoryExp[0].expGained").value(13))
			.andExpect(jsonPath("$.categoryExp[0].levelBefore").value(3))
			.andExpect(jsonPath("$.categoryExp[0].levelAfter").value(4))
			.andExpect(jsonPath("$.categoryExp[0].levelUpGold").value(20))
			.andExpect(jsonPath("$.categoryExp[0].expInLevel").value(3))
			.andExpect(jsonPath("$.categoryExp[0].expRequired").value(40))
			.andExpect(jsonPath("$.categoryExp[1].categoryCode").value("st"))
			.andExpect(jsonPath("$.categoryExp[1].levelAfter").value(8))
			.andExpect(jsonPath("$.categoryExp[1].levelUpGold").value(0))
			.andExpect(jsonPath("$.categoryExp[2].categoryCode").value("fd"))
			.andExpect(jsonPath("$.categoryExp[2].levelAfter").value(5))
			.andExpect(jsonPath("$.periodBonuses.length()").value(1))
			.andExpect(jsonPath("$.periodBonuses[0].habitId").value(study))
			.andExpect(jsonPath("$.periodBonuses[0].periodCode").value("D30"))
			.andExpect(jsonPath("$.periodBonuses[0].multiplier").value(1.5))
			.andExpect(jsonPath("$.periodBonuses[0].periodScore").value(560))
			.andExpect(jsonPath("$.periodBonuses[0].bonusGold").value(280))
			.andExpect(jsonPath("$.unlockedSpecies.length()").value(0))
			.andExpect(jsonPath("$.exploreTotal").value(3))
			.andExpect(jsonPath("$.gold").value(693));

		long user = userIdOf("a@habit.kr");
		long checkinId = jdbc.queryForObject("select id from habit.daily_checkin where user_id = ?", Long.class, user);
		// 원장: 체크인 53 · 레벨업 20 (ref = 체크인 id:카테고리) · 기간 보너스 280 (ref = 기간 id)
		assertThat(jdbc.queryForList("select reason_code || '/' || ref_id || '/' || amount from wallet.wallet_ledger where user_id = ? order by id",
				String.class, user))
			.containsExactly("CHECKIN/" + checkinId + "/53", "LEVELUP/" + checkinId + ":ex/20",
					"PERIOD_BONUS/" + jdbc.queryForObject("select id from habit.habit_period where habit_id = ?", Long.class, study) + "/280");
		// 기간을 채운 습관은 ENDED, 기간에 끝난 날 · 보너스
		assertThat(jdbc.queryForObject("select status from habit.habit where id = ?", String.class, study)).isEqualTo("ENDED");
		assertThat(jdbc.queryForMap("select filled_days, counted_score_sum, ended_on, period_bonus from habit.habit_period where habit_id = ?", study))
			.containsEntry("filled_days", 30).containsEntry("counted_score_sum", 560).containsEntry("period_bonus", 280)
			.containsEntry("ended_on", java.sql.Date.valueOf(dates.today()));
		// 채운 날: "했어"인 습관만 (못했어인 걷기는 그대로)
		assertThat(jdbc.queryForObject("select filled_days from habit.habit_period where habit_id = ?", Integer.class, walk)).isZero();
		assertThat(jdbc.queryForObject("select filled_days from habit.habit_period where habit_id = ?", Integer.class, pill)).isEqualTo(1);
		// 카테고리: ex 13 → 누적 63 · Lv.4
		assertThat(jdbc.queryForMap("select exp_total, level from habit.user_category where user_id = ? and category_code = 'ex'", user))
			.containsEntry("exp_total", 63).containsEntry("level", 4);
		// 탐색 기회 3 + 연 카테고리 전부 (B4)
		assertThat(jdbc.queryForObject("select base_count from monster.daily_explore_quota where user_id = ?", Integer.class, user)).isEqualTo(3);
		assertThat(jdbc.queryForList("select category_code from monster.explore_quota_category where user_id = ? order by category_code",
				String.class, user)).containsExactly("ex", "fd", "st");
		// 상단 바도 서버 값
		as(access, get("/me/status")).andExpect(jsonPath("$.checkedInToday").value(true))
			.andExpect(jsonPath("$.exploreRemaining").value(3)).andExpect(jsonPath("$.gold").value(693))
			.andExpect(jsonPath("$.endedHabitCount").value(1));
		as(access, get("/me/today")).andExpect(jsonPath("$.goldEarned").value(353)).andExpect(jsonPath("$.overallRate").value(88));
	}

	@Test
	void 레벨업으로_새_종이_탐색_후보가_된다() throws Exception {
		String access = user("a@habit.kr", DEFAULT_ONBOARDING); // 운동 · 공부, 아침 러닝 30분
		jdbc.update("update habit.user_category set exp_total = 25 where user_id = ? and category_code = 'ex'", userIdOf("a@habit.kr"));
		// 60분(목표 30)을 직접 적음 → 자기보고 상한 20 (명세 v6). Lv.1 누적 25 + 20 = 45 → Lv.3 (누적 30)
		// — 출현 레벨 3인 깡총 불토끼(2번)가 새로 나온다
		submit(access, done(habit("a@habit.kr", "아침 러닝"), 60)).andExpect(status().isCreated())
			.andExpect(jsonPath("$.habits[0].score").value(20))
			.andExpect(jsonPath("$.habits[0].scoreCapped").value(true))
			.andExpect(jsonPath("$.habits[0].evidence").value("SHORT"))
			.andExpect(jsonPath("$.categoryExp[0].levelBefore").value(1))
			.andExpect(jsonPath("$.categoryExp[0].levelAfter").value(3))
			.andExpect(jsonPath("$.categoryExp[0].levelUpGold").value(40))
			.andExpect(jsonPath("$.unlockedSpecies.length()").value(1))
			.andExpect(jsonPath("$.unlockedSpecies[0].speciesId").value(2))
			.andExpect(jsonPath("$.unlockedSpecies[0].categoryCode").value("ex"))
			.andExpect(jsonPath("$.goldEarned").value(60));
	}

	@Test
	void 동점이면_등록_순서로_상위_3개만_반영() throws Exception {
		String access = user("a@habit.kr", """
			{"categories": ["fd", "md"],
			 "habits": [
			   {"categoryCode": "fd", "measureTypeId": 9, "name": "영양제", "dailyTarget": 1, "periodCode": "D30"},
			   {"categoryCode": "fd", "measureTypeId": 10, "name": "야식 참기", "dailyTarget": 1, "periodCode": "D30"},
			   {"categoryCode": "md", "measureTypeId": 13, "name": "일기", "dailyTarget": 1, "periodCode": "D30"},
			   {"categoryCode": "md", "measureTypeId": 14, "name": "독서", "dailyTarget": 1, "periodCode": "D30"},
			   {"categoryCode": "md", "measureTypeId": 12, "name": "명상", "dailyTarget": 10, "periodCode": "D30"}]}""");
		String e = "a@habit.kr";
		// 넷이 20점 동점 → 먼저 등록한 셋, 명상(5분 = 10점)은 빠짐
		submit(access, String.join(",", done(habit(e, "영양제"), 1), done(habit(e, "야식 참기"), 1), done(habit(e, "일기"), 1),
				done(habit(e, "독서"), 1), done(habit(e, "명상"), 5)))
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.habits[0].counted").value(true))
			.andExpect(jsonPath("$.habits[1].counted").value(true))
			.andExpect(jsonPath("$.habits[2].counted").value(true))
			.andExpect(jsonPath("$.habits[3].counted").value(false))
			.andExpect(jsonPath("$.habits[4].score").value(10))
			.andExpect(jsonPath("$.habits[4].counted").value(false))
			.andExpect(jsonPath("$.goldBreakdown.score").value(60))
			.andExpect(jsonPath("$.overallRate").value(100));
		// 반영 안 됐어도 "했어"면 채운 날 +1 (B1)
		assertThat(jdbc.queryForObject("select filled_days from habit.habit_period where habit_id = ?", Integer.class, habit(e, "독서")))
			.isEqualTo(1);
	}

	@Test
	void 전부_못했어면_탐색_1번_골드_0() throws Exception {
		String access = user("a@habit.kr", SPEC_ONBOARDING);
		String e = "a@habit.kr";
		submit(access, String.join(",", missed(habit(e, "스쿼트")), missed(habit(e, "걷기")), missed(habit(e, "전공 공부")),
				missed(habit(e, "영양제"))))
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.goldEarned").value(0))
			.andExpect(jsonPath("$.overallRate").value(0))
			.andExpect(jsonPath("$.exploreTotal").value(1))
			.andExpect(jsonPath("$.gold").value(0));
		assertThat(jdbc.queryForObject("select count(*) from wallet.wallet_ledger", Integer.class)).isZero(); // 0원은 원장에 안 씀
	}

	@Test
	void 마지막_날_반영되지_않은_습관도_기간_보너스를_받고_ENDED() throws Exception {
		String access = user("a@habit.kr", SPEC_ONBOARDING);
		String e = "a@habit.kr";
		long walk = habit(e, "걷기");
		jdbc.update("update habit.habit_period set filled_days = 29, counted_score_sum = 100 where habit_id = ?", walk);
		// 걷기는 10분(7점)이라 상위 3개(13 · 20 · 20)에 못 들지만 오늘로 30일을 채운다 → 100 × 0.5 = 50G
		submit(access, String.join(",", done(habit(e, "스쿼트"), 2), done(walk, 10), done(habit(e, "전공 공부"), 60),
				done(habit(e, "영양제"), 1)))
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.habits[1].score").value(7))
			.andExpect(jsonPath("$.habits[1].counted").value(false))
			.andExpect(jsonPath("$.periodBonuses[0].habitId").value(walk))
			.andExpect(jsonPath("$.periodBonuses[0].periodScore").value(100))
			.andExpect(jsonPath("$.periodBonuses[0].bonusGold").value(50));
		assertThat(jdbc.queryForObject("select status from habit.habit where id = ?", String.class, walk)).isEqualTo("ENDED");
	}

	@Test
	void 체크인_화면_조회_제출_전과_후() throws Exception {
		String access = user("a@habit.kr", SPEC_ONBOARDING);
		as(access, get("/checkins/today")).andExpect(status().isOk())
			.andExpect(jsonPath("$.businessDate").value(dates.today().toString()))
			.andExpect(jsonPath("$.submitted").value(false))
			.andExpect(jsonPath("$.revision").value(0))
			.andExpect(jsonPath("$.partner.name").value("불씨 원숭이"))
			.andExpect(jsonPath("$.partner.imageKey").value("monkey"))
			.andExpect(jsonPath("$.partner.affectionTier").value("LOW"))
			.andExpect(jsonPath("$.tabs.length()").value(3))
			.andExpect(jsonPath("$.tabs[0].categoryCode").value("ex"))
			.andExpect(jsonPath("$.tabs[0].categoryName").value("운동"))
			.andExpect(jsonPath("$.tabs[0].habits[0].name").value("스쿼트"))
			.andExpect(jsonPath("$.tabs[0].habits[0].scoringMode").value("TARGET_RATIO"))
			.andExpect(jsonPath("$.tabs[0].habits[0].options").value(org.hamcrest.Matchers.contains(1, 2, 3, 5, 6)))
			.andExpect(content().string(containsString("\"previousValue\":null")))
			.andExpect(jsonPath("$.tabs[0].habits[1].options").value(org.hamcrest.Matchers.contains(10, 15, 25, 30, 45, 60)))
			.andExpect(jsonPath("$.tabs[0].habits[1].filledDays").value(0))
			.andExpect(jsonPath("$.tabs[0].habits[1].periodDays").value(30))
			.andExpect(jsonPath("$.tabs[2].habits[0].scoringMode").value("BINARY"))
			.andExpect(jsonPath("$.tabs[2].habits[0].options").value(org.hamcrest.Matchers.contains(1)));

		String e = "a@habit.kr";
		submit(access, String.join(",", done(habit(e, "스쿼트"), 2), missed(habit(e, "걷기")), done(habit(e, "전공 공부"), 60),
				done(habit(e, "영양제"), 1))).andExpect(status().isCreated());
		as(access, get("/checkins/today"))
			.andExpect(jsonPath("$.submitted").value(true))
			.andExpect(jsonPath("$.revision").value(1))
			.andExpect(jsonPath("$.tabs[0].habits[0].previousValue").value(2))
			.andExpect(jsonPath("$.tabs[0].habits[1].previousValue").value(0))
			.andExpect(jsonPath("$.tabs[0].habits[0].filledDays").value(1));
	}

	@Test
	void 다시_체크는_값과_점수만_바뀌고_보상은_그대로() throws Exception {
		String access = specUser();
		String e = "a@habit.kr";
		submit(access, specAnswers()).andExpect(status().isCreated());
		String key = UUID.randomUUID().toString();
		String again = body(dates.today(), String.join(",", done(habit(e, "스쿼트"), 5), missed(habit(e, "걷기")),
				done(habit(e, "전공 공부"), 60), done(habit(e, "영양제"), 1)));

		// 명세 예시: 40분 → 23점 (여기선 스쿼트 5회 = 20 + 10 × (5/3 − 1) = 26.7 → 25인데, 직접 적은 값이라 상한 20 — 명세 v6)
		String first = send(access, put("/checkins/today"), key, again).andExpect(status().isOk())
			.andExpect(jsonPath("$.revision").value(2))
			.andExpect(jsonPath("$.habits[0].value").value(5))
			.andExpect(jsonPath("$.habits[0].score").value(20))
			.andExpect(jsonPath("$.habits[0].scoreCapped").value(true))
			.andExpect(jsonPath("$.habits[1].value").value(0))
			.andExpect(jsonPath("$.overallRate").value(100))
			.andReturn().getResponse().getContentAsString();
		// 같은 키로 다시 보내면 같은 응답 (revision이 또 오르지 않음)
		send(access, put("/checkins/today"), key, again).andExpect(status().isOk()).andExpect(content().json(first, true));

		long user = userIdOf(e);
		assertThat(gold(e)).isEqualTo(693);
		assertThat(jdbc.queryForObject("select count(*) from wallet.wallet_ledger where user_id = ?", Integer.class, user)).isEqualTo(3);
		assertThat(jdbc.queryForMap("select revision, total_score, counted_score from habit.daily_checkin where user_id = ?", user))
			.containsEntry("revision", 2).containsEntry("total_score", 60).containsEntry("counted_score", 53);
		assertThat(jdbc.queryForMap("select value, score, rewarded_score from habit.habit_checkin where habit_id = ?", habit(e, "스쿼트")))
			.containsEntry("score", 20).containsEntry("rewarded_score", 13);
		assertThat(jdbc.queryForObject("select level from habit.user_category where user_id = ? and category_code = 'ex'", Integer.class, user))
			.isEqualTo(4);
		assertThat(jdbc.queryForObject("select count(*) from habit.checkin_submission", Integer.class)).isEqualTo(2);
		// 기간을 채워 ENDED가 된 전공 공부도 다시 체크 대상 — 빼면 400
		resubmit(access, String.join(",", done(habit(e, "스쿼트"), 5), missed(habit(e, "걷기")), done(habit(e, "영양제"), 1)))
			.andExpect(status().isBadRequest());
	}

	@Test
	void 오늘_제출이_없으면_다시_체크는_404() throws Exception {
		String access = user("a@habit.kr", DEFAULT_ONBOARDING);
		resubmit(access, done(habit("a@habit.kr", "아침 러닝"), 30)).andExpect(status().isNotFound())
			.andExpect(jsonPath("$.code").value("CHECKIN_NOT_FOUND"));
	}

	@Test
	void 날짜가_다르면_409() throws Exception {
		String access = user("a@habit.kr", DEFAULT_ONBOARDING);
		send(access, post("/checkins/today"), UUID.randomUUID().toString(),
				body(dates.today().minusDays(1), done(habit("a@habit.kr", "아침 러닝"), 30)))
			.andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("BUSINESS_DATE_CHANGED"));
	}

	@Test
	void 이미_제출했으면_409() throws Exception {
		String access = user("a@habit.kr", DEFAULT_ONBOARDING);
		String answer = done(habit("a@habit.kr", "아침 러닝"), 30);
		submit(access, answer).andExpect(status().isCreated());
		submit(access, answer).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("ALREADY_SUBMITTED"));
	}

	@Test
	void 대상_습관이_없으면_409() throws Exception {
		String access = user("a@habit.kr", DEFAULT_ONBOARDING);
		jdbc.update("update habit.habit_period set started_on = started_on + 1"); // 내일 시작
		as(access, get("/checkins/today")).andExpect(jsonPath("$.tabs.length()").value(0));
		submit(access, done(habit("a@habit.kr", "아침 러닝"), 30)).andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("NO_ACTIVE_HABIT"));
	}

	@Test
	void 빠진_습관_남의_습관_선택지_밖_값은_400() throws Exception {
		String access = user("a@habit.kr", SPEC_ONBOARDING);
		user("b@habit.kr", DEFAULT_ONBOARDING);
		String e = "a@habit.kr";
		submit(access, String.join(",", done(habit(e, "스쿼트"), 2), done(habit(e, "걷기"), 27),
				done(habit("b@habit.kr", "아침 러닝"), 30), done(habit(e, "영양제"), 1)))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
			.andExpect(jsonPath("$.errors[0].field").value("answers[1].value"))
			.andExpect(jsonPath("$.errors[1].field").value("answers[2].habitId"))
			.andExpect(jsonPath("$.errors[2].field").value("answers"));
		assertThat(jdbc.queryForObject("select count(*) from habit.daily_checkin", Integer.class)).isZero();
	}

	@Test
	void 같은_날_다른_키로_동시에_두_번_제출해도_하나만() throws Exception {
		String access = user("a@habit.kr", DEFAULT_ONBOARDING);
		String answer = done(habit("a@habit.kr", "아침 러닝"), 30);
		CountDownLatch start = new CountDownLatch(1);
		ExecutorService pool = Executors.newFixedThreadPool(2);
		List<Future<Integer>> results = new ArrayList<>();
		for (int i = 0; i < 2; i++) {
			results.add(pool.submit(() -> {
				start.await();
				return submit(access, answer).andReturn().getResponse().getStatus();
			}));
		}
		start.countDown();
		List<Integer> statuses = new ArrayList<>();
		for (Future<Integer> f : results) {
			statuses.add(f.get(20, TimeUnit.SECONDS));
		}
		pool.shutdown();

		assertThat(statuses).containsExactlyInAnyOrder(201, 409);
		assertThat(jdbc.queryForObject("select count(*) from habit.daily_checkin", Integer.class)).isEqualTo(1);
		assertThat(gold("a@habit.kr")).isEqualTo(40); // 한 번만: 점수 20 + 운동 Lv.1 → 2 레벨업 20
	}
}
