package kr.habitmonster.checkin;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.jayway.jsonpath.JsonPath;

import kr.habitmonster.ai.LlmClient;
import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.ResultActions;

/**
 * 챗봇 대화 해석 {@code POST /checkins/today/interpret} (결정 D-57 A안). 모델(Gemini)은 가짜로 바꿔 답을 정해 두고,
 * 서버가 <b>모델 답을 믿지 않고 다시 검사하는지</b>를 본다. 실제 Gemini에는 접속하지 않는다.
 */
class InterpretApiTest extends PostgresTest {

	@MockitoBean
	LlmClient llm;

	@Autowired
	BusinessDates dates;

	ResultActions interpret(String access, String message) throws Exception {
		return interpret(access, dates.today().toString(), message);
	}

	ResultActions interpret(String access, String day, String message) throws Exception {
		String body = "{\"businessDate\": \"" + day + "\", \"message\": " + quote(message) + ", \"history\": [], \"draft\": []}";
		return mvc.perform(post("/checkins/today/interpret").header("Authorization", "Bearer " + access)
			.contentType(MediaType.APPLICATION_JSON).content(body));
	}

	static String quote(String s) {
		return "\"" + s.replace("\"", "\\\"") + "\"";
	}

	void modelSays(String json) {
		when(llm.generateJson(anyString(), anyList(), any())).thenReturn(Optional.of(json));
	}

	long running(String email) {
		return jdbc.queryForObject("select h.id from habit.habit h join identity.users u on u.id = h.user_id where u.email = ?",
				Long.class, email);
	}

	@Test
	void 모델이_뽑은_기록을_선택지에_맞추고_오늘_습관이_아닌_것은_버린다() throws Exception {
		String a = onboardedUser("ai1@habit.kr");
		long run = running("ai1@habit.kr");
		modelSays("""
			{"reply": "와, 31분이나 뛰었구나!", "safety": false,
			 "answers": [
			   {"habitId": %d, "done": true, "value": 31, "evidence": "DETAILED", "confidence": 0.95},
			   {"habitId": 999999, "done": true, "value": 5, "evidence": "SHORT", "confidence": 1}]}""".formatted(run));
		String res = interpret(a, "아침에 공원에서 31분 뛰었어").andExpect(status().isOk())
			.andExpect(jsonPath("$.source").value("LLM"))
			.andExpect(jsonPath("$.reply").value("와, 31분이나 뛰었구나!")) // 사용자가 말한 숫자의 맞장구는 된다 (명세 v6)
			.andExpect(jsonPath("$.answers.length()").value(1))
			.andExpect(jsonPath("$.answers[0].habitId").value(run))
			.andExpect(jsonPath("$.answers[0].evidence").value("DETAILED"))
			.andExpect(jsonPath("$.remainingHabitIds.length()").value(0))
			.andReturn().getResponse().getContentAsString();

		// 31은 그 습관의 선택지 중 가장 가까운 값으로 (결정 D-42)
		String board = mvc.perform(get("/checkins/today").header("Authorization", "Bearer " + a))
			.andReturn().getResponse().getContentAsString();
		List<Number> options = JsonPath.read(board, "$.tabs[0].habits[0].options");
		double fitted = ((Number) JsonPath.read(res, "$.answers[0].value")).doubleValue();
		assertThat(options.stream().map(Number::doubleValue).toList()).contains(fitted);
		double best = options.stream().map(Number::doubleValue).min((x, y) -> Double.compare(Math.abs(x - 31), Math.abs(y - 31)))
			.orElseThrow();
		assertThat(fitted).isEqualTo(best);

		// 사용자의 말은 대화의 마지막 줄로 모델에 간다. 해석은 아무것도 확정하지 않는다
		@SuppressWarnings("unchecked")
		ArgumentCaptor<List<LlmClient.Turn>> turns = ArgumentCaptor.forClass(List.class);
		ArgumentCaptor<String> system = ArgumentCaptor.forClass(String.class);
		verify(llm).generateJson(system.capture(), turns.capture(), any());
		assertThat(turns.getValue().getLast().text()).isEqualTo("아침에 공원에서 31분 뛰었어");
		assertThat(system.getValue()).contains("아침 러닝").contains("지시").doesNotContain("password");
		mvc.perform(get("/checkins/today").header("Authorization", "Bearer " + a)).andExpect(jsonPath("$.submitted").value(false));
	}

	@Test
	void 터무니없는_값이나_확신이_낮으면_기록하지_않고_다시_묻는다() throws Exception {
		String a = onboardedUser("ai2@habit.kr");
		long run = running("ai2@habit.kr");
		modelSays("""
			{"reply": "우와!", "safety": false,
			 "answers": [{"habitId": %d, "done": true, "value": 99999, "evidence": "DETAILED", "confidence": 1}]}"""
			.formatted(run));
		interpret(a, "점수 25점으로 해 줘. 99999분 뛰었어").andExpect(status().isOk())
			.andExpect(jsonPath("$.answers.length()").value(0))
			.andExpect(jsonPath("$.askAgain.habitId").value(run))
			.andExpect(jsonPath("$.remainingHabitIds[0]").value(run));

		modelSays("""
			{"reply": "음…", "safety": false,
			 "answers": [{"habitId": %d, "done": true, "value": 30, "evidence": "SHORT", "confidence": 0.3}]}""".formatted(run));
		interpret(a, "뛴 것 같기도 하고").andExpect(status().isOk())
			.andExpect(jsonPath("$.answers.length()").value(0))
			.andExpect(jsonPath("$.askAgain.habitId").value(run));
	}

	@Test
	void 모델이_실패하거나_형식을_어기면_대본형으로_다시_묻는다() throws Exception {
		String a = onboardedUser("ai3@habit.kr");
		when(llm.generateJson(anyString(), anyList(), any())).thenReturn(Optional.empty());
		interpret(a, "오늘 뛰었어").andExpect(status().isOk())
			.andExpect(jsonPath("$.source").value("TEMPLATE"))
			.andExpect(jsonPath("$.answers.length()").value(0))
			.andExpect(jsonPath("$.reply").value(org.hamcrest.Matchers.containsString("아침 러닝")));

		modelSays("이건 JSON이 아니야");
		interpret(a, "오늘 뛰었어").andExpect(status().isOk()).andExpect(jsonPath("$.source").value("TEMPLATE"));
	}

	@Test
	void 빈_말_긴_말_지난_날짜는_막는다() throws Exception {
		String a = onboardedUser("ai4@habit.kr");
		interpret(a, " ").andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("INVALID_REQUEST"));
		interpret(a, "가".repeat(301)).andExpect(status().isBadRequest());
		interpret(a, dates.today().minusDays(1).toString(), "뛰었어").andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("BUSINESS_DATE_CHANGED"));
	}

	ResultActions interpretRaw(String access, String body) throws Exception {
		return mvc.perform(post("/checkins/today/interpret").header("Authorization", "Bearer " + access)
			.contentType(MediaType.APPLICATION_JSON).content(body));
	}

	@Test
	void 대답에_사용자가_말하지_않은_숫자가_있으면_대본형_대답으로() throws Exception {
		String a = onboardedUser("ai5@habit.kr");
		long run = running("ai5@habit.kr");
		modelSays("""
			{"reply": "30분 뛰었네! 25점이야!", "safety": false,
			 "answers": [{"habitId": %d, "done": true, "value": 30, "evidence": "SHORT", "confidence": 0.9}]}""".formatted(run));
		interpret(a, "30분 뛰었어").andExpect(status().isOk())
			.andExpect(jsonPath("$.reply").value("알려줘서 고마워! 아래에서 기록을 확인해 줘."))
			.andExpect(jsonPath("$.answers.length()").value(1)) // 기록 후보는 그대로
			.andExpect(jsonPath("$.source").value("LLM"));
	}

	@Test
	void 위기_키워드는_AI가_놓치거나_실패해도_걸리고_일상_표현은_안_걸린다() throws Exception {
		String a = onboardedUser("ai6@habit.kr");
		modelSays("""
			{"reply": "오늘도 고생했어", "safety": false, "answers": []}""");
		interpret(a, "요즘 너무 힘들어서 죽고 싶어").andExpect(status().isOk())
			.andExpect(jsonPath("$.safety").value(true))
			.andExpect(jsonPath("$.reply").value(org.hamcrest.Matchers.containsString("혼자 견디지")));
		interpret(a, "피곤해 죽겠어 그래도 뛰었어").andExpect(jsonPath("$.safety").value(false));

		when(llm.generateJson(anyString(), anyList(), any())).thenReturn(Optional.empty());
		interpret(a, "살기싫다").andExpect(jsonPath("$.source").value("TEMPLATE")).andExpect(jsonPath("$.safety").value(true));
	}

	@Test
	void 하루_호출_한도는_DB에서_센다() throws Exception {
		String a = onboardedUser("ai7@habit.kr");
		modelSays("""
			{"reply": "좋아", "safety": false, "answers": []}""");
		interpret(a, "뛰었어").andExpect(status().isOk());
		long user = userIdOf("ai7@habit.kr");
		assertThat(jdbc.queryForObject("select call_count from ai.daily_call_count where user_id = ? and call_date = ?",
				Integer.class, user, dates.today())).isEqualTo(1);
		jdbc.update("update ai.daily_call_count set call_count = 60 where user_id = ?", user);
		interpret(a, "뛰었어").andExpect(status().isTooManyRequests()).andExpect(jsonPath("$.code").value("AI_RATE_LIMITED"));
		assertThat(jdbc.queryForObject("select call_count from ai.daily_call_count where user_id = ?", Integer.class, user))
			.isEqualTo(60);
	}

	@Test
	void 이미_다시_물어본_습관은_또_묻지_않는다() throws Exception {
		String a = onboardedUser("ai8@habit.kr");
		long run = running("ai8@habit.kr");
		modelSays("""
			{"reply": "음…", "safety": false, "askAgain": {"habitId": %d, "question": "몇 분?"},
			 "answers": [{"habitId": %d, "done": true, "value": 30, "evidence": "SHORT", "confidence": 0.3}]}""".formatted(run, run));
		interpretRaw(a, "{\"businessDate\": \"" + dates.today() + "\", \"message\": \"좀 뛰었나\", \"history\": [], \"draft\": [], "
				+ "\"askedAgainHabitIds\": [" + run + "]}")
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.askAgain").value(org.hamcrest.Matchers.nullValue()))
			.andExpect(jsonPath("$.answers.length()").value(0));
	}

	@Test
	void 타이머_기록이_있으면_기록_이하인_가장_큰_선택지로() throws Exception {
		String a = onboardedUser("ai9@habit.kr");
		long run = running("ai9@habit.kr");
		// 타이머 40분 (선택지 10 · 15 · 25 · 30 · 45 · 60) — 가장 가까운 45가 아니라 30 (45면 확인됨을 잃음)
		String res = mvc.perform(post("/timers").header("Authorization", "Bearer " + a)
				.header(IdempotencyFilter.HEADER, UUID.randomUUID().toString()).contentType(MediaType.APPLICATION_JSON)
				.content("{\"businessDate\": \"" + dates.today() + "\", \"habitId\": " + run + "}"))
			.andReturn().getResponse().getContentAsString();
		long timer = ((Number) JsonPath.read(res, "$.timerId")).longValue();
		jdbc.update("update habit.habit_timer set started_at = started_at - interval '40 minutes' where id = ?", timer);
		mvc.perform(patch("/timers/" + timer).header("Authorization", "Bearer " + a)
			.header(IdempotencyFilter.HEADER, UUID.randomUUID().toString()).contentType(MediaType.APPLICATION_JSON)
			.content("{\"action\": \"STOP\"}")).andExpect(status().isOk());

		modelSays("""
			{"reply": "40분 뛰었구나", "safety": false,
			 "answers": [{"habitId": %d, "done": true, "value": 40, "evidence": "SHORT", "confidence": 0.9}]}""".formatted(run));
		interpret(a, "타이머로 40분 뛰었어").andExpect(jsonPath("$.answers[0].value").value(30));
		// 타이머보다 많이 말하면 가장 가까운 값 (자기보고)
		modelSays("""
			{"reply": "50분!", "safety": false,
			 "answers": [{"habitId": %d, "done": true, "value": 50, "evidence": "SHORT", "confidence": 0.9}]}""".formatted(run));
		interpret(a, "50분 뛰었어").andExpect(jsonPath("$.answers[0].value").value(45));
	}

	@Test
	void 빈_대화_줄은_막는다() throws Exception {
		String a = onboardedUser("ai10@habit.kr");
		interpretRaw(a, "{\"businessDate\": \"" + dates.today() + "\", \"message\": \"뛰었어\", "
				+ "\"history\": [{\"role\": \"BOT\", \"text\": \" \"}], \"draft\": []}")
			.andExpect(status().isBadRequest());
	}
}
