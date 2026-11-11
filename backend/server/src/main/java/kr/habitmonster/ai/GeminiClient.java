package kr.habitmonster.ai;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * Gemini API ({@code generateContent}) 호출. 키 · 모델은 환경변수 {@code GEMINI_API_KEY} · {@code GEMINI_MODEL}
 * (로컬은 {@code backend/.env} — 커밋하지 않는다). 앱에는 키를 두지 않는다 (앱 파일을 풀면 꺼낼 수 있어서, D-57).
 *
 * <p>응답이 늦으면 기다리지 않는다: 제한 시간({@code app.llm.timeout-ms}, 기본 5초 — D-66)을 넘기거나 실패하면 빈 값 → 대본형으로.
 */
@Component
class GeminiClient implements LlmClient {

	private static final Logger log = LoggerFactory.getLogger(GeminiClient.class);
	private static final String BASE = "https://generativelanguage.googleapis.com/v1beta/models/";

	private final String apiKey;
	private final String model;
	private final Duration timeout;
	private final JsonMapper json;
	private final HttpClient http;

	GeminiClient(@Value("${app.llm.gemini.api-key:}") String apiKey, @Value("${app.llm.gemini.model}") String model,
			@Value("${app.llm.timeout-ms:5000}") long timeoutMs, JsonMapper json) {
		this.apiKey = apiKey;
		this.model = model;
		this.timeout = Duration.ofMillis(timeoutMs);
		this.json = json;
		this.http = HttpClient.newBuilder().connectTimeout(timeout).build();
	}

	@Override
	public Optional<String> generateJson(String systemPrompt, List<Turn> turns, Map<String, Object> responseSchema) {
		if (apiKey.isBlank()) {
			return Optional.empty(); // 키 없음 = AI 끔 (대본형)
		}
		Map<String, Object> body = new LinkedHashMap<>();
		body.put("systemInstruction", Map.of("parts", List.of(Map.of("text", systemPrompt))));
		List<Map<String, Object>> contents = new ArrayList<>();
		for (Turn t : turns) {
			contents.add(Map.of("role", t.role(), "parts", List.of(Map.of("text", t.text()))));
		}
		body.put("contents", contents);
		// 낮은 온도 = 같은 말에 비슷한 해석. 응답은 지정한 JSON 모양으로만
		body.put("generationConfig", Map.of("responseMimeType", "application/json", "responseSchema", responseSchema,
				"temperature", 0.3));
		try {
			HttpRequest req = HttpRequest.newBuilder(URI.create(BASE + model + ":generateContent"))
				.timeout(timeout)
				.header("Content-Type", "application/json")
				.header("x-goog-api-key", apiKey)
				.POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body), StandardCharsets.UTF_8))
				.build();
			HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
			if (res.statusCode() != 200) {
				log.warn("Gemini 응답 {} (모델 {})", res.statusCode(), model);
				return Optional.empty();
			}
			JsonNode text = json.readTree(res.body()).path("candidates").path(0).path("content").path("parts").path(0)
				.path("text");
			return text.isString() ? Optional.of(text.asString()) : Optional.empty();
		}
		catch (InterruptedException e) {
			Thread.currentThread().interrupt();
			return Optional.empty();
		}
		catch (Exception e) {
			// 시간 초과 · 연결 실패 · 형식 오류 — 키는 로그에 남기지 않는다
			log.warn("Gemini 호출 실패: {}", e.getClass().getSimpleName());
			return Optional.empty();
		}
	}
}
