package kr.habitmonster.auth;

import kr.habitmonster.identity.AuthProvider;
import kr.habitmonster.identity.User;

/** 요청 · 응답 모양. 앱의 {@code AuthSession}과 같은 필드. */
public final class AuthDtos {

	private AuthDtos() {
	}

	public record EmailRequest(String email, String password) {
	}

	public record SocialRequest(String token) {
	}

	public record RefreshRequest(String refreshToken) {
	}

	public record UserView(String id, AuthProvider provider, String email, String nickname, boolean onboardingDone) {

		static UserView of(User user, AuthProvider provider, String email) {
			return new UserView(String.valueOf(user.getId()), provider, email, user.getNickname(), user.isOnboardingDone());
		}
	}

	public record AuthResponse(String accessToken, String refreshToken, UserView user) {
	}
}
