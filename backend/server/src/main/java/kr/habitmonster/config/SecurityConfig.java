package kr.habitmonster.config;

import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.common.ErrorResponses;
import kr.habitmonster.identity.UserRepository;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.oauth2.jwt.JwtValidationException;
import org.springframework.security.oauth2.server.resource.web.authentication.BearerTokenAuthenticationFilter;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.SecurityFilterChain;

/**
 * {@code /auth/**}만 열고, 나머지는 {@code Authorization: Bearer <accessToken>} 필요. 세션 · CSRF 없음 (앱 전용 API).
 * 브라우저(웹)의 다른 출처 요청은 {@link CorsConfig} 설정으로 허용 여부를 정한다 (기본 꺼짐, local 프로필만 localhost:5000).
 * 요청 검사 순서 (API 명세 v4): ① 토큰 → ② 사용자 상태 · 온보딩({@link UserGateFilter}) → ③ 중복 방지 키(IdempotencyFilter) → 컨트롤러.
 */
@Configuration
public class SecurityConfig {

	@Bean
	SecurityFilterChain securityFilterChain(HttpSecurity http, UserRepository users) throws Exception {
		AuthenticationEntryPoint unauthorized = (req, res, e) ->
			ErrorResponses.write(res, isExpired(e) ? ErrorCode.TOKEN_EXPIRED : ErrorCode.INVALID_TOKEN);
		return http
			.cors(Customizer.withDefaults()) // CorsConfigurationSource 빈 — 사전 요청(OPTIONS)은 토큰 검사 전에 여기서 답한다
			.csrf(c -> c.disable())
			.httpBasic(b -> b.disable())
			.formLogin(f -> f.disable())
			.sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
			.authorizeHttpRequests(a -> a
				.requestMatchers("/auth/**", "/error").permitAll()
				.anyRequest().authenticated())
			.oauth2ResourceServer(o -> o.jwt(Customizer.withDefaults()).authenticationEntryPoint(unauthorized))
			.exceptionHandling(e -> e.authenticationEntryPoint(unauthorized))
			.addFilterAfter(new UserGateFilter(users), BearerTokenAuthenticationFilter.class)
			.build();
	}

	/** 검증 실패 원인 중에 {@link JwtConfig#EXPIRED_ERROR}가 있으면 만료. */
	private static boolean isExpired(AuthenticationException e) {
		for (Throwable t = e; t != null; t = t.getCause()) {
			if (t instanceof JwtValidationException v) {
				return v.getErrors().stream().anyMatch(err -> JwtConfig.EXPIRED_ERROR.equals(err.getErrorCode()));
			}
		}
		return false;
	}
}
