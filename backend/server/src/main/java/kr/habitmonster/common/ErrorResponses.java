package kr.habitmonster.common;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import jakarta.servlet.http.HttpServletResponse;

import org.springframework.http.MediaType;

/**
 * 컨트롤러 밖(보안 · 필터)에서 오류를 쓸 때. {@link ApiExceptionHandler}와 같은 {@code {code, message}} 모양.
 * 메시지는 {@link ErrorCode}의 고정 문구라 따옴표 · 역슬래시만 막으면 된다.
 */
public final class ErrorResponses {

	private ErrorResponses() {
	}

	public static void write(HttpServletResponse res, ErrorCode code) throws IOException {
		res.setStatus(code.status.value());
		res.setContentType(MediaType.APPLICATION_JSON_VALUE);
		res.setCharacterEncoding(StandardCharsets.UTF_8.name());
		res.getWriter().write("{\"code\":\"" + code.name() + "\",\"message\":\"" + escape(code.message) + "\"}");
	}

	private static String escape(String s) {
		return s.replace("\\", "\\\\").replace("\"", "\\\"");
	}
}
