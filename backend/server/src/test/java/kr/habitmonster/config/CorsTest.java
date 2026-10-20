package kr.habitmonster.config;

import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/** 로컬 웹 확인용 CORS (결정 D-44): 허용 출처의 사전 요청만 통과, 기본은 꺼짐. */
class CorsTest {

	static final String WEB = "http://localhost:5000";

	/** 브라우저가 POST 전에 보내는 사전 요청 (토큰 · 중복 방지 키 헤더를 쓰겠다고 묻는다). */
	static MockHttpServletRequestBuilder preflight(String origin) {
		return options("/checkins/today")
			.header("Origin", origin)
			.header("Access-Control-Request-Method", "POST")
			.header("Access-Control-Request-Headers", "authorization,content-type,idempotency-key");
	}

	@Nested
	@TestPropertySource(properties = "app.cors.allowed-origins=" + WEB)
	class 허용_출처가_있을_때 extends PostgresTest {

		@Test
		void 허용_출처의_사전_요청은_토큰_없이_통과() throws Exception {
			mvc.perform(preflight(WEB))
				.andExpect(status().isOk())
				.andExpect(header().string("Access-Control-Allow-Origin", WEB))
				.andExpect(header().string("Access-Control-Allow-Methods", containsString("POST")))
				.andExpect(header().string("Access-Control-Allow-Methods", containsString("PATCH")))
				.andExpect(header().string("Access-Control-Allow-Headers", containsString("idempotency-key")))
				.andExpect(header().doesNotExist("Access-Control-Allow-Credentials"));
		}

		@Test
		void 다른_출처는_거절() throws Exception {
			mvc.perform(preflight("http://evil.example")).andExpect(status().isForbidden())
				.andExpect(header().doesNotExist("Access-Control-Allow-Origin"));
		}

		@Test
		void 허용하지_않은_헤더를_쓰겠다고_하면_거절() throws Exception {
			mvc.perform(options("/checkins/today").header("Origin", WEB)
					.header("Access-Control-Request-Method", "POST")
					.header("Access-Control-Request-Headers", "x-something"))
				.andExpect(status().isForbidden());
		}

		@Test
		void 실제_요청의_오류_응답에도_허용_헤더가_붙는다() throws Exception {
			// 토큰 없이 부르면 401 — 브라우저가 이 오류 본문을 읽을 수 있어야 앱이 "다시 로그인"을 보여 준다
			mvc.perform(get("/me/status").header("Origin", WEB))
				.andExpect(status().isUnauthorized())
				.andExpect(header().string("Access-Control-Allow-Origin", WEB))
				.andExpect(jsonPath("$.code").value("INVALID_TOKEN"));
		}
	}

	@Nested
	class 기본_설정 extends PostgresTest {

		@Test
		void 허용_출처가_비어_있으면_CORS_헤더가_없다() throws Exception {
			mvc.perform(preflight(WEB)).andExpect(header().doesNotExist("Access-Control-Allow-Origin"));
		}
	}
}
