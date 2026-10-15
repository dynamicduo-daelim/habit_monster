package kr.habitmonster.auth;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

/** 요청 · 응답 모양 (API 명세 v5 "1. 회원 · 설정"). */
public final class AuthDtos {

	private AuthDtos() {
	}

	public record EmailRequest(String email, String password) {
	}

	/** 앱이 카카오 · 구글 SDK로 받은 토큰 (카카오: access token, 구글: ID token). */
	public record SocialRequest(String providerToken) {
	}

	public record RefreshRequest(String refreshToken) {
	}

	/** @param platform ANDROID | IOS */
	public record DeviceTokenRequest(String fcmToken, String platform) {
	}

	/**
	 * 가입 · 로그인 응답. {@code onboarded}가 false면 앱은 온보딩으로 보낸다.
	 * {@code isNewUser}는 소셜 로그인에서만 (이메일 가입 · 로그인 응답에는 없음).
	 */
	@JsonInclude(JsonInclude.Include.NON_NULL)
	public record LoginResponse(String accessToken, String refreshToken, boolean onboarded,
			@JsonProperty("isNewUser") Boolean isNewUser) {
	}

	/** 토큰 재발급 응답. 리프레시 토큰도 새것이고 이전 것은 폐기된다. */
	public record TokenResponse(String accessToken, String refreshToken) {
	}

	/**
	 * {@code GET /me} — 설정 창의 계정 표시 + 앱을 다시 켰을 때 온보딩 여부 확인 (결정 D4).
	 *
	 * @param provider 가입 방법 코드 EMAIL | KAKAO | GOOGLE
	 * @param email 없을 수 있음 (카카오가 이메일을 주지 않았거나 검증되지 않은 이메일)
	 */
	public record MeView(long userId, String email, String provider, boolean onboarded) {
	}
}
