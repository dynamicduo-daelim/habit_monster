package kr.habitmonster.auth.social;

import java.util.List;
import java.util.Set;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;

import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwtTimestampValidator;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;

/**
 * OpenID Connect ID 토큰(JWT, 지금은 구글) 검증: 제공자 공개키(JWKS)로 서명, 발급자(iss), 대상(aud = 우리 앱), 만료.
 */
abstract class OidcIdTokenVerifier implements SocialVerifier {

	private final List<String> audiences;
	private final JwtDecoder decoder;

	OidcIdTokenVerifier(String jwkSetUri, Set<String> issuers, List<String> audiences) {
		this.audiences = audiences.stream().filter(a -> a != null && !a.isBlank()).toList();
		NimbusJwtDecoder d = NimbusJwtDecoder.withJwkSetUri(jwkSetUri).build();
		d.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
				new JwtTimestampValidator(),
				jwt -> issuers.contains(jwt.getClaimAsString("iss")) ? OAuth2TokenValidatorResult.success()
						: OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token", "iss", null)),
				jwt -> jwt.getAudience() != null && jwt.getAudience().stream().anyMatch(this.audiences::contains)
						? OAuth2TokenValidatorResult.success()
						: OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token", "aud", null))));
		this.decoder = d;
	}

	@Override
	public SocialIdentity verify(String token) {
		if (audiences.isEmpty()) {
			throw new ApiException(ErrorCode.SOCIAL_NOT_CONFIGURED);
		}
		try {
			Jwt jwt = decoder.decode(token);
			if (jwt.getSubject() == null || jwt.getSubject().isBlank()) {
				throw new ApiException(ErrorCode.INVALID_PROVIDER_TOKEN);
			}
			Object verified = jwt.getClaim("email_verified"); // 구글은 true 또는 "true"
			return new SocialIdentity(jwt.getSubject(), jwt.getClaimAsString("email"),
					Boolean.TRUE.equals(verified) || "true".equals(verified));
		}
		catch (JwtException e) {
			throw new ApiException(ErrorCode.INVALID_PROVIDER_TOKEN);
		}
	}
}
