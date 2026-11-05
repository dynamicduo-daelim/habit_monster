package kr.habitmonster.checkin;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import com.jayway.jsonpath.JsonPath;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.support.PostgresTest;

import org.hamcrest.Matchers;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * 체크인 근거 · 자기보고 상한 · 경험치 계수 (API 명세 v6 4-1 · 5장, 결정 D-62).
 * 습관: 아침 러닝(운동 시간 30분, 선택지 10 · 15 · 25 · 30 · 45 · 60) · 7시간 자기(수면 범위) · 영양제(O·X).
 */
class EvidenceApiTest extends PostgresTest {

	static final String ONBOARDING = """
		{"categories": ["ex", "sl", "fd"],
		 "habits": [
		   {"categoryCode": "ex", "measureTypeId": 1, "name": "아침 러닝", "dailyTarget": 30, "periodCode": "D30"},
		   {"categoryCode": "sl", "measureTypeId": 16, "name": "7시간 자기", "dailyTarget": 7, "periodCode": "D30"},
		   {"categoryCode": "fd", "measureTypeId": 9, "name": "영양제", "dailyTarget": 1, "periodCode": "D30"}]}""";

	@Autowired
	BusinessDates dates;

	String access;
	long run;
	long sleep;
	long pill;

	@BeforeEach
	void user() throws Exception {
		access = signUp("e@habit.kr");
		onboard(access, ONBOARDING).andExpect(status().isCreated());
		run = id("아침 러닝");
		sleep = id("7시간 자기");
		pill = id("영양제");
	}

	long id(String name) {
		return jdbc.queryForObject("select id from habit.habit where name = ?", Long.class, name);
	}

	ResultActions send(MockHttpServletRequestBuilder req, String body) throws Exception {
		return mvc.perform(req.header("Authorization", "Bearer " + access)
			.header(IdempotencyFilter.HEADER, UUID.randomUUID().toString()).contentType(MediaType.APPLICATION_JSON)
			.content(body));
	}

	String answers(String runAnswer) {
		return "{\"businessDate\": \"" + dates.today() + "\", \"answers\": [" + runAnswer + ", "
				+ "{\"habitId\": " + sleep + ", \"done\": true, \"value\": 7}, "
				+ "{\"habitId\": " + pill + ", \"done\": true, \"value\": 1}]}";
	}

	String run(Object value, String evidence) {
		return "{\"habitId\": " + run + ", \"done\": true, \"value\": " + value
				+ (evidence == null ? "" : ", \"evidence\": \"" + evidence + "\"") + "}";
	}

	/** 아침 러닝 타이머로 {@code minutes}분 잰 것으로 (시작 시각을 당긴 뒤 끝냄). */
	void timed(int minutes) throws Exception {
		String res = send(post("/timers"), "{\"businessDate\": \"" + dates.today() + "\", \"habitId\": " + run + "}")
			.andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
		long timer = ((Number) JsonPath.read(res, "$.timerId")).longValue();
		jdbc.update("update habit.habit_timer set started_at = started_at - make_interval(mins => ?) where id = ?", minutes, timer);
		send(patch("/timers/" + timer), "{\"action\": \"STOP\"}").andExpect(status().isOk());
	}

	@Test
	void 직접_적으면_목표를_넘겨도_20점_경험치는_방식별_계수() throws Exception {
		send(post("/checkins/today"), answers(run(45, "DETAILED"))).andExpect(status().isCreated())
			// 러닝 45분(목표 30) = 공식 25 → 자기보고 상한 20, 경험치 20 × 1.0
			.andExpect(jsonPath("$.habits[0].score").value(20))
			.andExpect(jsonPath("$.habits[0].evidence").value("DETAILED"))
			.andExpect(jsonPath("$.habits[0].scoreCapped").value(true))
			.andExpect(jsonPath("$.habits[0].expGained").value(20))
			// 수면 범위 안 20 → 경험치 20 × 0.9 = 18, 영양제 O 20 → 20 × 0.8 = 16 (원래 최대 20이라 상한에 안 걸림)
			.andExpect(jsonPath("$.habits[1].scoreCapped").value(false))
			.andExpect(jsonPath("$.habits[1].expGained").value(18))
			.andExpect(jsonPath("$.habits[2].expGained").value(16))
			.andExpect(jsonPath("$.categoryExp[?(@.categoryCode == 'sl')].expGained").value(Matchers.contains(18)))
			.andExpect(jsonPath("$.categoryExp[?(@.categoryCode == 'fd')].expGained").value(Matchers.contains(16)))
			// 골드는 점수 그대로 1점 = 1G
			.andExpect(jsonPath("$.goldBreakdown.score").value(60));
		long user = userIdOf("e@habit.kr");
		assertThat(jdbc.queryForObject("select exp_total from habit.user_category where user_id = ? and category_code = 'sl'",
				Integer.class, user)).isEqualTo(18);
		assertThat(jdbc.queryForMap("select evidence, rewarded_evidence, score_capped from habit.habit_checkin where habit_id = ?", run))
			.containsEntry("evidence", "DETAILED").containsEntry("rewarded_evidence", "DETAILED").containsEntry("score_capped", true);
	}

	@Test
	void 타이머_기록_이하로_적으면_확인됨_25점_경험치_곱하기_1_2() throws Exception {
		timed(45);
		send(post("/checkins/today"), answers(run(45, null))).andExpect(status().isCreated())
			.andExpect(jsonPath("$.habits[0].evidence").value("VERIFIED"))
			.andExpect(jsonPath("$.habits[0].score").value(25))
			.andExpect(jsonPath("$.habits[0].scoreCapped").value(false))
			.andExpect(jsonPath("$.habits[0].expGained").value(30)); // 25 × 1.0 × 1.2
		assertThat(jdbc.queryForObject("select rewarded_evidence from habit.habit_checkin where habit_id = ?", String.class, run))
			.isEqualTo("VERIFIED");
	}

	@Test
	void 타이머보다_많이_적으면_전체가_자기보고() throws Exception {
		timed(40);
		send(post("/checkins/today"), answers(run(45, null))).andExpect(status().isCreated())
			.andExpect(jsonPath("$.habits[0].evidence").value("SHORT"))
			.andExpect(jsonPath("$.habits[0].score").value(20))
			.andExpect(jsonPath("$.habits[0].scoreCapped").value(true));
	}

	@Test
	void 목표만큼은_타이머로_재도_20점_확인되면_경험치만_1_2배() throws Exception {
		timed(40);
		send(post("/checkins/today"), answers(run(30, null))).andExpect(status().isCreated())
			.andExpect(jsonPath("$.habits[0].evidence").value("VERIFIED"))
			.andExpect(jsonPath("$.habits[0].score").value(20))
			.andExpect(jsonPath("$.habits[0].expGained").value(24));
	}

	@Test
	void 도는_타이머는_판정에_넣지_않는다() throws Exception {
		String res = send(post("/timers"), "{\"businessDate\": \"" + dates.today() + "\", \"habitId\": " + run + "}")
			.andReturn().getResponse().getContentAsString();
		jdbc.update("update habit.habit_timer set started_at = started_at - interval '50 minutes' where id = ?",
				((Number) JsonPath.read(res, "$.timerId")).longValue());
		send(post("/checkins/today"), answers(run(45, null))).andExpect(jsonPath("$.habits[0].evidence").value("SHORT"));
	}

	@Test
	void 앱은_VERIFIED를_보낼_수_없다() throws Exception {
		send(post("/checkins/today"), answers(run(30, "VERIFIED"))).andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.errors[0].field").value("answers[0].evidence"));
		send(post("/checkins/today"), answers(run(30, "PHOTO"))).andExpect(status().isBadRequest());
	}

	@Test
	void 체크인_조회에_오늘_타이머_분() throws Exception {
		mvc.perform(get("/checkins/today").header("Authorization", "Bearer " + access))
			.andExpect(jsonPath("$.tabs[?(@.categoryCode == 'ex')].habits[0].timerMinutes").value(Matchers.contains(0)))
			.andExpect(jsonPath("$.tabs[?(@.categoryCode == 'sl')].habits[0].timerMinutes").value(Matchers.contains(Matchers.nullValue())));
		timed(40);
		mvc.perform(get("/checkins/today").header("Authorization", "Bearer " + access))
			.andExpect(jsonPath("$.tabs[?(@.categoryCode == 'ex')].habits[0].timerMinutes").value(Matchers.contains(40)));
	}

	@Test
	void 다시_체크는_최신_근거만_바뀌고_보상_근거는_첫_제출() throws Exception {
		send(post("/checkins/today"), answers(run(45, null))).andExpect(jsonPath("$.habits[0].score").value(20));
		timed(45);
		send(put("/checkins/today"), answers(run(45, null))).andExpect(status().isOk())
			.andExpect(jsonPath("$.habits[0].evidence").value("VERIFIED"))
			.andExpect(jsonPath("$.habits[0].score").value(25))
			.andExpect(jsonPath("$.habits[0].scoreCapped").value(false));
		assertThat(jdbc.queryForMap("select score, rewarded_score, evidence, rewarded_evidence from habit.habit_checkin where habit_id = ?", run))
			.containsEntry("score", 25).containsEntry("rewarded_score", 20)
			.containsEntry("evidence", "VERIFIED").containsEntry("rewarded_evidence", "SHORT");
	}
}
