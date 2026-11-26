package kr.habitmonster.ai;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Set;

import org.junit.jupiter.api.Test;

/** 해석 검사의 작은 규칙들 (DB · 모델 없이). 실제 Gemini 답으로 찾은 문제(11-26)를 사례로 둔다. */
class CheckinInterpreterTest {

	@Test
	void 말에_양이_있는지() {
		for (String yes : List.of("30분", "한 시간 했어", "한시간반 했지", "반시간 했어", "삼십 분", "두 잔 마셨어", "1.5시간",
				"다 했어", "목표만큼 했어", "꽉 채웠어")) {
			assertThat(CheckinInterpreter.saidAmount(yes)).as(yes).isTrue();
		}
		for (String no : List.of("웅 핶어", "했어", "응", "요가 갔다왔어", "이번에도 했어", "저번처럼 했어", "못 갔어 ㅠ")) {
			assertThat(CheckinInterpreter.saidAmount(no)).as(no).isFalse();
		}
	}

	@Test
	void 대답에_쓸_수_있는_숫자는_사용자가_말한_숫자와_기록한_값() {
		var h = new CheckinInterpreter.HabitContext(3, "요가 가기", "운동", "분", "TARGET_RATIO", 30, 600, List.of(30, 60, 90), null);
		var a = new CheckinInterpreter.Answer(3, true, 90, "SHORT", 0.9);
		Set<String> rec = CheckinInterpreter.recordedNumbers(List.of(a), Map.of(3L, h));
		assertThat(rec).contains("90", "1.5");
		assertThat(CheckinInterpreter.numbersFromUser("90분이나 했구나", "한시간반 했지", rec)).isTrue();
		assertThat(CheckinInterpreter.numbersFromUser("1.5시간이나!", "한시간반 했지", rec)).isTrue();
		assertThat(CheckinInterpreter.numbersFromUser("25점이야", "한시간반 했지", rec)).isFalse();
	}

	@Test
	void 실패_대답은_질문을_되풀이하지_않는다() {
		assertThat(CheckinInterpreter.retryReply("요가 가기")).contains("요가 가기").contains("다시 말해").doesNotContain("했어?");
	}
}
