package kr.habitmonster.checkin;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.Optional;
import java.util.UUID;

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
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * 체크인 대사 {@code POST /checkins/today/dialogue} (명세 v6 5장, 기획 2026-11-08-AI대사-알림). 모델은 가짜 —
 * revision당 한 번만 만드는지, 실패 · 지어낸 숫자면 템플릿인지, 탈퇴하면 지워지는지를 본다.
 */
class DialogueApiTest extends PostgresTest {

	@MockitoBean
	LlmClient llm;

	@Autowired
	BusinessDates dates;

	ResultActions as(String access, MockHttpServletRequestBuilder req) throws Exception {
		return mvc.perform(req.header("Authorization", "Bearer " + access));
	}

	ResultActions dialogue(String access) throws Exception {
		return as(access, post("/checkins/today/dialogue"));
	}

	void check(String access, MockHttpServletRequestBuilder req, long habitId, int minutes) throws Exception {
		String body = "{\"businessDate\": \"" + dates.today() + "\", \"answers\": [{\"habitId\": " + habitId
				+ ", \"done\": " + (minutes > 0) + ", \"value\": " + minutes + "}]}";
		as(access, req.header(IdempotencyFilter.HEADER, UUID.randomUUID().toString())
			.contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().is2xxSuccessful());
	}

	long running(String email) {
		return jdbc.queryForObject("select h.id from habit.habit h join identity.users u on u.id = h.user_id where u.email = ?",
				Long.class, email);
	}

	void modelSays(String line) {
		when(llm.generateJson(anyString(), anyList(), any())).thenReturn(Optional.of("{\"line\": \"" + line + "\"}"));
	}

	@Test
	void 체크인_전이면_409() throws Exception {
		String a = onboardedUser("d1@habit.kr");
		dialogue(a).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("CHECKIN_REQUIRED"));
	}

	@Test
	void 같은_revision이면_저장된_대사를_그대로_다시_체크하면_새_대사() throws Exception {
		String a = onboardedUser("d2@habit.kr");
		long run = running("d2@habit.kr");
		check(a, post("/checkins/today"), run, 30);

		modelSays("30분이나 뛰었구나, 멋져!");
		dialogue(a).andExpect(status().isOk())
			.andExpect(jsonPath("$.revision").value(1))
			.andExpect(jsonPath("$.line").value("30분이나 뛰었구나, 멋져!")) // 기록에 있는 숫자는 된다
			.andExpect(jsonPath("$.source").value("LLM"));

		modelSays("다른 대사");
		dialogue(a).andExpect(jsonPath("$.line").value("30분이나 뛰었구나, 멋져!"));
		verify(llm, times(1)).generateJson(anyString(), anyList(), any()); // 같은 revision은 모델을 다시 부르지 않는다

		check(a, put("/checkins/today"), run, 15); // 목표 30분의 선택지: 10 · 15 · 25 · 30 · 45 · 60
		modelSays("기록 고쳐 줘서 고마워!");
		dialogue(a).andExpect(jsonPath("$.revision").value(2)).andExpect(jsonPath("$.line").value("기록 고쳐 줘서 고마워!"));
		assertThat(jdbc.queryForObject("select count(*) from ai.checkin_dialogue", Integer.class)).isEqualTo(2);
	}

	@Test
	void 모델에는_점수_골드를_넘기지_않고_습관_이름은_지시가_아니라고_적는다() throws Exception {
		String a = onboardedUser("d3@habit.kr");
		check(a, post("/checkins/today"), running("d3@habit.kr"), 30);
		modelSays("좋아!");
		dialogue(a).andExpect(status().isOk());

		ArgumentCaptor<String> system = ArgumentCaptor.forClass(String.class);
		verify(llm).generateJson(system.capture(), anyList(), any());
		assertThat(system.getValue()).contains("아침 러닝").contains("30").contains("지시").doesNotContain("골드:")
			.doesNotContain("점수:");
	}

	@Test
	void 모델이_실패하거나_형식을_어기면_템플릿() throws Exception {
		String a = onboardedUser("d4@habit.kr");
		check(a, post("/checkins/today"), running("d4@habit.kr"), 30);
		when(llm.generateJson(anyString(), anyList(), any())).thenReturn(Optional.empty());
		dialogue(a).andExpect(jsonPath("$.source").value("TEMPLATE"))
			.andExpect(jsonPath("$.line").value("오늘 습관을 전부 해냈구나! 정말 멋져."));

		String b = onboardedUser("d5@habit.kr");
		check(b, post("/checkins/today"), running("d5@habit.kr"), 0);
		when(llm.generateJson(anyString(), anyList(), any())).thenReturn(Optional.of("JSON 아님"));
		dialogue(b).andExpect(jsonPath("$.source").value("TEMPLATE"))
			.andExpect(jsonPath("$.line").value("괜찮아, 그런 날도 있어. 내일 다시 같이 해 보자."));
	}

	@Test
	void 기록에_없는_숫자를_지어내면_템플릿() throws Exception {
		String a = onboardedUser("d6@habit.kr");
		check(a, post("/checkins/today"), running("d6@habit.kr"), 30);
		modelSays("오늘 25점에 골드 25G나 받았어!");
		dialogue(a).andExpect(jsonPath("$.source").value("TEMPLATE"));
	}

	@Test
	void 탈퇴하면_대사가_지워진다() throws Exception {
		String a = onboardedUser("d7@habit.kr");
		check(a, post("/checkins/today"), running("d7@habit.kr"), 30);
		modelSays("좋아!");
		dialogue(a).andExpect(status().isOk());
		long uid = userIdOf("d7@habit.kr");

		as(a, delete("/me")).andExpect(status().isNoContent());
		assertThat(jdbc.queryForObject("select count(*) from ai.checkin_dialogue where user_id = ?", Integer.class, uid))
			.isZero();
	}
}
