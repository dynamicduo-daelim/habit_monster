package kr.habitmonster.ai;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** 위기 키워드 (명세 v6 5장 검사 7) — 걸려야 할 문장 / 걸리면 안 되는 일상 표현. */
class SafetyKeywordsTest {

	@ParameterizedTest
	@ValueSource(strings = { "죽고 싶어", "죽고싶다...", "그냥 사라지고 싶어", "살기 싫어", "자해했어", "유서를 썼어",
			"차라리 죽는 게 낫겠어", "손목 긋고 싶어", "살 이유가 없어", "태어나지 말 걸" })
	void 걸린다(String message) {
		assertThat(SafetyKeywords.flagged(message)).isTrue();
	}

	@ParameterizedTest
	@ValueSource(strings = { "피곤해 죽겠어", "배고파 죽겠다", "더워서 못 살겠다", "돈에 목매지 말자", "웃겨 죽을 뻔",
			"죽는 줄 알았어 너무 힘들어서", "오늘 30분 뛰었어", "미치겠다 공부 많아서" })
	void 일상_표현은_안_걸린다(String message) {
		assertThat(SafetyKeywords.flagged(message)).isFalse();
	}
}
