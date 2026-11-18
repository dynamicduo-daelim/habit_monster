package kr.habitmonster.checkin;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import kr.habitmonster.ai.LlmClient;
import kr.habitmonster.ai.Personas;
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
 * 몬스터와 대화 늘리기 (기획 2026-11-15-몬스터-대화): A 성격 · B 자유 대화 {@code POST /chat/talk} · C 기억.
 * 모델은 가짜 — 프롬프트에 무엇이 들어가는지와 서버가 모델 답을 다시 검사하는지를 본다.
 */
class TalkApiTest extends PostgresTest {

	@MockitoBean
	LlmClient llm;

	@Autowired
	BusinessDates dates;

	@Autowired
	Personas personas;

	ResultActions talk(String access, String message) throws Exception {
		return talk(access, dates.today().toString(), message);
	}

	ResultActions talk(String access, String day, String message) throws Exception {
		String body = "{\"businessDate\": \"" + day + "\", \"message\": " + InterpretApiTest.quote(message)
				+ ", \"history\": [{\"role\": \"BOT\", \"text\": \"오늘 체크 끝!\"}]}";
		return mvc.perform(post("/chat/talk").header("Authorization", "Bearer " + access)
			.contentType(MediaType.APPLICATION_JSON).content(body));
	}

	void modelSays(String reply, boolean safety) {
		when(llm.generateJson(anyString(), anyList(), any()))
			.thenReturn(Optional.of("{\"reply\": \"" + reply + "\", \"safety\": " + safety + "}"));
	}

	String lastSystemPrompt() {
		ArgumentCaptor<String> system = ArgumentCaptor.forClass(String.class);
		verify(llm, atLeastOnce()).generateJson(system.capture(), anyList(), any());
		return system.getValue();
	}

	long running(String email) {
		return jdbc.queryForObject("select h.id from habit.habit h join identity.users u on u.id = h.user_id where u.email = ?",
				Long.class, email);
	}

	void checkIn(String access, long habitId, int minutes) throws Exception {
		String body = "{\"businessDate\": \"" + dates.today() + "\", \"answers\": [{\"habitId\": " + habitId
				+ ", \"done\": " + (minutes > 0) + ", \"value\": " + minutes + "}]}";
		mvc.perform(post("/checkins/today").header("Authorization", "Bearer " + access)
			.header(IdempotencyFilter.HEADER, UUID.randomUUID().toString())
			.contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isCreated());
	}

	int callCount(String email) {
		return jdbc.queryForObject("""
			select coalesce(sum(c.call_count), 0) from ai.daily_call_count c join identity.users u on u.id = c.user_id
			 where u.email = ?""", Integer.class, email);
	}

	// ---------- A. 성격 ----------

	@Test
	void 성격_자료는_시드의_28종을_모두_가진다() {
		List<String> codes = jdbc.queryForList("select code from monster.monster_species", String.class);
		assertThat(codes).hasSize(28);
		assertThat(codes).allSatisfy(code -> assertThat(personas.of(code)).as(code).isPresent());
	}

	@Test
	void 대화_상대의_성격이_프롬프트에_들어가고_상대를_바꾸면_말투도_바뀐다() throws Exception {
		String a = onboardedUser("p1@habit.kr");
		modelSays("안녕!", false);
		talk(a, "안녕").andExpect(status().isOk());
		String partnerCode = jdbc.queryForObject("""
			select s.code from monster.user_monster m join monster.monster_species s on s.id = m.species_id
			  join identity.users u on u.id = m.user_id
			 where u.email = 'p1@habit.kr' and m.is_partner""",
				String.class);
		assertThat(lastSystemPrompt()).contains("성격: " + personas.of(partnerCode).orElseThrow().personality())
			.contains("가끔만");

		// 다른 몬스터를 대화 상대로 → 그 몬스터의 성격
		long other = jdbc.queryForObject("""
			select m.id from monster.user_monster m join monster.monster_species s on s.id = m.species_id
			  join identity.users u on u.id = m.user_id where u.email = 'p1@habit.kr' and s.code <> ?""", Long.class,
				partnerCode);
		String otherCode = jdbc.queryForObject(
				"select s.code from monster.user_monster m join monster.monster_species s on s.id = m.species_id where m.id = ?",
				String.class, other);
		mvc.perform(put("/me/partner").header("Authorization", "Bearer " + a).contentType(MediaType.APPLICATION_JSON)
			.content("{\"userMonsterId\": " + other + "}")).andExpect(status().is2xxSuccessful());
		talk(a, "안녕").andExpect(status().isOk());
		assertThat(lastSystemPrompt()).contains(personas.of(otherCode).orElseThrow().personality())
			.doesNotContain(personas.of(partnerCode).orElseThrow().personality());
	}

	// ---------- B. 자유 대화 ----------

	@Test
	void 체크인_뒤_자유_대화_오늘_기록을_알고_아무것도_저장하지_않는다() throws Exception {
		String a = onboardedUser("t1@habit.kr");
		checkIn(a, running("t1@habit.kr"), 30);
		int dialoguesBefore = jdbc.queryForObject("select count(*) from ai.checkin_dialogue", Integer.class);

		modelSays("오늘 30분이나 뛰었잖아! 푹 쉬어.", false);
		talk(a, "오늘 진짜 피곤했어").andExpect(status().isOk())
			.andExpect(jsonPath("$.reply").value("오늘 30분이나 뛰었잖아! 푹 쉬어.")) // 오늘 기록의 숫자는 된다
			.andExpect(jsonPath("$.safety").value(false))
			.andExpect(jsonPath("$.source").value("LLM"));

		String prompt = lastSystemPrompt();
		assertThat(prompt).contains("오늘 기록").contains("아침 러닝 | 30").contains("지시").doesNotContain("골드:");
		assertThat(jdbc.queryForObject("select count(*) from ai.checkin_dialogue", Integer.class)).isEqualTo(dialoguesBefore);
		assertThat(callCount("t1@habit.kr")).isEqualTo(1);
	}

	@Test
	void 체크인_전에도_받고_체크_전이라고_알려_준다() throws Exception {
		String a = onboardedUser("t2@habit.kr");
		modelSays("오늘 아침 러닝도 기대할게!", false);
		talk(a, "심심해").andExpect(status().isOk()).andExpect(jsonPath("$.source").value("LLM"));
		assertThat(lastSystemPrompt()).contains("아직 습관 체크 전").contains("아침 러닝");
	}

	@Test
	void 지어낸_숫자_실패_형식_오류는_대본형() throws Exception {
		String a = onboardedUser("t3@habit.kr");
		checkIn(a, running("t3@habit.kr"), 30);

		modelSays("오늘 골드 25G나 받았네!", false); // 25는 어디에도 없는 숫자
		talk(a, "오늘 어땠어?").andExpect(jsonPath("$.source").value("TEMPLATE"))
			.andExpect(jsonPath("$.reply").value("그랬구나. 조금 더 이야기해 줄래?"));

		modelSays("내가 7번 말했지?", false);
		talk(a, "7번이나 말했잖아").andExpect(jsonPath("$.source").value("LLM")); // 사용자가 말한 숫자는 된다

		when(llm.generateJson(anyString(), anyList(), any())).thenReturn(Optional.empty());
		talk(a, "안녕").andExpect(jsonPath("$.source").value("TEMPLATE"));

		when(llm.generateJson(anyString(), anyList(), any())).thenReturn(Optional.of("JSON 아님"));
		talk(a, "안녕").andExpect(jsonPath("$.source").value("TEMPLATE"));
	}

	@Test
	void 위기_신호는_모델_판단이든_키워드든_걱정하는_문구로() throws Exception {
		String a = onboardedUser("t4@habit.kr");
		modelSays("그렇구나!", false); // 모델이 놓쳐도
		talk(a, "요즘 죽고 싶어").andExpect(jsonPath("$.safety").value(true))
			.andExpect(jsonPath("$.reply").value(org.hamcrest.Matchers.containsString("믿을 수 있는 사람")));

		modelSays("많이 힘들구나.", true); // 모델이 잡으면
		talk(a, "다 그만두고 싶어").andExpect(jsonPath("$.safety").value(true))
			.andExpect(jsonPath("$.reply").value(org.hamcrest.Matchers.containsString("믿을 수 있는 사람")));
	}

	@Test
	void 하루_한도는_해석과_함께_센다() throws Exception {
		String a = onboardedUser("t5@habit.kr");
		modelSays("응!", false);
		talk(a, "안녕").andExpect(status().isOk());
		mvc.perform(post("/checkins/today/interpret").header("Authorization", "Bearer " + a)
			.contentType(MediaType.APPLICATION_JSON)
			.content("{\"businessDate\": \"" + dates.today() + "\", \"message\": \"뛰었어\", \"history\": [], \"draft\": []}"))
			.andExpect(status().isOk());
		assertThat(callCount("t5@habit.kr")).isEqualTo(2);

		jdbc.update("update ai.daily_call_count set call_count = 60 where user_id = ?", userIdOf("t5@habit.kr"));
		talk(a, "안녕").andExpect(status().isTooManyRequests()).andExpect(jsonPath("$.code").value("AI_RATE_LIMITED"));
	}

	@Test
	void 빈_말_긴_말은_400_날짜가_다르면_409() throws Exception {
		String a = onboardedUser("t6@habit.kr");
		talk(a, "   ").andExpect(status().isBadRequest());
		talk(a, "가".repeat(301)).andExpect(status().isBadRequest());
		talk(a, dates.today().minusDays(1).toString(), "안녕").andExpect(status().isConflict());
		assertThat(callCount("t6@habit.kr")).isZero(); // 거절된 요청은 세지 않는다
	}

	@Test
	void 대답은_200자까지_받고_넘으면_200자에서_자른다() throws Exception {
		String a = onboardedUser("l1@habit.kr");
		modelSays("가".repeat(150), false); // 예전 상한(120)을 넘어도 된다
		talk(a, "안녕").andExpect(jsonPath("$.reply").value("가".repeat(150))).andExpect(jsonPath("$.source").value("LLM"));
		modelSays("나".repeat(250), false);
		talk(a, "안녕").andExpect(jsonPath("$.reply").value("나".repeat(200)));
	}

	@Test
	void 대화_규칙이_프롬프트에_들어간다_반복_금지_구체적_답_위기_신호_범위() throws Exception {
		String a = onboardedUser("l2@habit.kr");
		modelSays("응!", false);
		talk(a, "안녕").andExpect(status().isOk());
		assertThat(lastSystemPrompt()).contains("200자 이내")
			.contains("반복하지 않는다") // 앞 대화의 위로 · 조언 · 말버릇
			.contains("거절하거나 항의한 방법")
			.contains("구체적으로 세 문장까지")
			.contains("화남 · 속상함 · 다툼 · 피곤함은 위기 신호가 아니다")
			.contains("'내'와 '네'")
			.contains("인사말 말버릇은 대화 첫 턴에만");
	}

	// ---------- C. 기억 ----------

	@Test
	void 어제_기록을_기억하고_그_숫자는_말해도_된다() throws Exception {
		String a = onboardedUser("m1@habit.kr");
		checkIn(a, running("m1@habit.kr"), 45);
		// 오늘 체크인을 어제 것으로 옮긴다 (지난 날 기록 만들기)
		jdbc.update("update habit.daily_checkin set checkin_date = checkin_date - 1 where user_id = ?", userIdOf("m1@habit.kr"));

		modelSays("어제 45분 뛰었잖아, 오늘도 해 보자!", false);
		talk(a, "오늘은 뭐 하지").andExpect(jsonPath("$.source").value("LLM"));
		assertThat(lastSystemPrompt()).contains("최근 기록").contains("어제: 아침 러닝 45분").contains("2일 전: 체크 안 함")
			.contains("아직 습관 체크 전");
	}

	@Test
	void 지난_기록이_없으면_없다고_적는다() throws Exception {
		String a = onboardedUser("m2@habit.kr");
		modelSays("반가워!", false);
		talk(a, "안녕").andExpect(status().isOk());
		assertThat(lastSystemPrompt()).contains("아직 지난 기록 없음");
	}
}
