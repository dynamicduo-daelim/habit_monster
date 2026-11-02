package kr.habitmonster.ai;

import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * 외부 언어 모델 호출 (지금은 Gemini — {@link GeminiClient}). 테스트는 이 인터페이스를 가짜로 바꾼다 ({@code @MockitoBean}).
 *
 * <p>모델은 <b>말과 기록 후보만</b> 만든다. 점수 · 골드는 모르고, 정하지도 않는다 (결정 D-57, A안).
 */
public interface LlmClient {

	/** 대화 한 줄. {@code role}은 {@code user}(사용자) · {@code model}(챗봇). */
	record Turn(String role, String text) {
	}

	/**
	 * 응답 형식({@code responseSchema})을 지정해 JSON 문자열을 받는다.
	 *
	 * @return 모델이 낸 JSON 텍스트. 키가 없거나 · 실패 · 제한 시간을 넘기면 비어 있다 (부르는 쪽이 대본형으로 바꾼다)
	 */
	Optional<String> generateJson(String systemPrompt, List<Turn> turns, Map<String, Object> responseSchema);
}
