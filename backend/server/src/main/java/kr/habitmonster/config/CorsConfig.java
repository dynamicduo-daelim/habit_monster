package kr.habitmonster.config;

import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

/**
 * 브라우저(Flutter 웹)에서 서버를 부를 때의 CORS — **로컬 웹 확인용** (결정 D-44).
 *
 * <p>브라우저는 다른 출처(주소 · 포트가 다른 곳)의 서버를 부르기 전에 "불러도 되나?"를 먼저 묻는다(사전 요청 OPTIONS).
 * 허용 출처는 설정값 {@code app.cors.allowed-origins}(쉼표로 여러 개)로 정하고, **기본은 비어 있어 꺼짐**이다.
 * {@code local} 프로필만 {@code http://localhost:5000}(flutter run -d chrome --web-port=5000)을 연다.
 * 앱(Android · iOS)은 브라우저가 아니라 CORS와 상관없다.
 *
 * <p>토큰은 쿠키가 아니라 {@code Authorization} 헤더로 보내므로 {@code allowCredentials}는 끈다.
 */
@Configuration
public class CorsConfig {

	static final List<String> ALLOWED_METHODS = List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS");
	static final List<String> ALLOWED_HEADERS = List.of("Authorization", "Content-Type", "Idempotency-Key");

	@Bean
	CorsConfigurationSource corsConfigurationSource(@Value("${app.cors.allowed-origins:}") List<String> origins) {
		UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
		List<String> allowed = origins.stream().map(String::strip).filter(o -> !o.isEmpty()).toList();
		if (allowed.isEmpty()) {
			return source; // 등록한 규칙이 없으면 CORS 응답 헤더를 붙이지 않는다 → 브라우저가 막는다
		}
		CorsConfiguration cors = new CorsConfiguration();
		cors.setAllowedOrigins(allowed);
		cors.setAllowedMethods(ALLOWED_METHODS);
		cors.setAllowedHeaders(ALLOWED_HEADERS);
		cors.setAllowCredentials(false);
		source.registerCorsConfiguration("/**", cors);
		return source;
	}
}
