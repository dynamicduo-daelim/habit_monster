package kr.habitmonster.config;

import java.nio.charset.StandardCharsets;
import java.time.Clock;

import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;

import com.nimbusds.jose.jwk.source.ImmutableSecret;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtIssuerValidator;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;

/** 우리 서버가 발급하는 access 토큰(JWT, HS256)과 비밀번호 해시(BCrypt). */
@Configuration
public class JwtConfig {

	/** 만료로 검증에 실패했을 때의 오류 코드. {@link SecurityConfig}가 이걸 보고 401 {@code TOKEN_EXPIRED}로 답한다. */
	public static final String EXPIRED_ERROR = "token_expired";

	private final SecretKey key;
	private final String issuer;

	public JwtConfig(AuthProperties props) {
		String secret = props.jwtSecret();
		if (secret == null || secret.getBytes(StandardCharsets.UTF_8).length < 32) {
			throw new IllegalStateException("app.auth.jwt-secret(JWT_SECRET)은 32바이트 이상이어야 합니다.");
		}
		this.key = new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
		this.issuer = props.issuer();
	}

	@Bean
	JwtEncoder jwtEncoder() {
		return new NimbusJwtEncoder(new ImmutableSecret<>(key));
	}

	@Bean
	JwtDecoder jwtDecoder(Clock clock) {
		NimbusJwtDecoder decoder = NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build();
		decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(new JwtIssuerValidator(issuer), notExpired(clock)));
		return decoder;
	}

	/**
	 * 기본 검사기는 만료와 위조를 같은 오류로 돌려줘서 앱이 구분할 수 없다.
	 * 만료만 따로 표시해서, 앱은 만료일 때만 재발급하고 위조 · 폐기면 바로 로그인 화면으로 간다.
	 */
	private static OAuth2TokenValidator<Jwt> notExpired(Clock clock) {
		return jwt -> {
			if (jwt.getExpiresAt() != null && !clock.instant().isBefore(jwt.getExpiresAt())) {
				return OAuth2TokenValidatorResult.failure(new OAuth2Error(EXPIRED_ERROR, "access 토큰 만료", null));
			}
			return OAuth2TokenValidatorResult.success();
		};
	}

	@Bean
	PasswordEncoder passwordEncoder() {
		return new BCryptPasswordEncoder();
	}

	@Bean
	Clock clock() {
		return Clock.systemUTC();
	}
}
