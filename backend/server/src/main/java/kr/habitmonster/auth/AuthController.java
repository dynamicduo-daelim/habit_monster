package kr.habitmonster.auth;

import kr.habitmonster.auth.AuthDtos.DeviceTokenRequest;
import kr.habitmonster.auth.AuthDtos.EmailRequest;
import kr.habitmonster.auth.AuthDtos.LoginResponse;
import kr.habitmonster.auth.AuthDtos.MeView;
import kr.habitmonster.auth.AuthDtos.RefreshRequest;
import kr.habitmonster.auth.AuthDtos.SocialRequest;
import kr.habitmonster.auth.AuthDtos.TokenResponse;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** 회원 · 설정 API (API 명세 v5 "1. 회원 · 설정" + 결정 A5 · D4). 경로는 모두 {@code /api/v1} 뒤. */
@RestController
public class AuthController {

	private final AuthService auth;

	public AuthController(AuthService auth) {
		this.auth = auth;
	}

	@PostMapping("/auth/signup")
	@ResponseStatus(HttpStatus.CREATED)
	LoginResponse signUp(@RequestBody EmailRequest req) {
		return auth.signUp(req.email(), req.password());
	}

	@PostMapping("/auth/login")
	LoginResponse login(@RequestBody EmailRequest req) {
		return auth.login(req.email(), req.password());
	}

	@PostMapping("/auth/social/{provider}")
	LoginResponse social(@PathVariable String provider, @RequestBody SocialRequest req) {
		return auth.social(provider, req.providerToken());
	}

	@PostMapping("/auth/refresh")
	TokenResponse refresh(@RequestBody RefreshRequest req) {
		return auth.refresh(req.refreshToken());
	}

	@PostMapping("/auth/logout")
	@ResponseStatus(HttpStatus.NO_CONTENT)
	void logout(@RequestBody RefreshRequest req) {
		auth.logout(req.refreshToken());
	}

	/** 내 계정 (결정 D4 — 명세에 없어서 더함). */
	@GetMapping("/me")
	MeView me(@AuthenticationPrincipal Jwt jwt) {
		return auth.me(userId(jwt));
	}

	@DeleteMapping("/me")
	@ResponseStatus(HttpStatus.NO_CONTENT)
	void withdraw(@AuthenticationPrincipal Jwt jwt) {
		auth.withdraw(userId(jwt));
	}

	@PutMapping("/me/device-token")
	@ResponseStatus(HttpStatus.NO_CONTENT)
	void registerDeviceToken(@AuthenticationPrincipal Jwt jwt, @RequestBody DeviceTokenRequest req) {
		auth.registerDeviceToken(userId(jwt), req.fcmToken(), req.platform());
	}

	/** 로그아웃할 때 푸시 토큰 해제 (결정 A5 — 명세에 없어서 더함). */
	@DeleteMapping("/me/device-token")
	@ResponseStatus(HttpStatus.NO_CONTENT)
	void unregisterDeviceToken(@AuthenticationPrincipal Jwt jwt, @RequestBody DeviceTokenRequest req) {
		auth.unregisterDeviceToken(userId(jwt), req.fcmToken());
	}

	private static Long userId(Jwt jwt) {
		return Long.valueOf(jwt.getSubject());
	}
}
