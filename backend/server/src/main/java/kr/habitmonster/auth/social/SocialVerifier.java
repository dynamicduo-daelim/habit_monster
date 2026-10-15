package kr.habitmonster.auth.social;

import kr.habitmonster.identity.AuthProvider;

/**
 * 앱이 소셜 SDK로 받은 토큰을 서버가 직접 확인한다. 앱이 보낸 사용자 ID · 이메일은 믿지 않는다.
 * 실패하면 {@code ApiException(INVALID_PROVIDER_TOKEN)}, 설정(앱 키)이 없으면 {@code SOCIAL_NOT_CONFIGURED}.
 */
public interface SocialVerifier {

	AuthProvider provider();

	SocialIdentity verify(String token);
}
