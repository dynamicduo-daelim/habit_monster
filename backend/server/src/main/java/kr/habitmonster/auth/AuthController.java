package kr.habitmonster.auth;

import kr.habitmonster.auth.AuthDtos.AuthResponse;
import kr.habitmonster.auth.AuthDtos.EmailRequest;
import kr.habitmonster.auth.AuthDtos.RefreshRequest;
import kr.habitmonster.auth.AuthDtos.SocialRequest;
import kr.habitmonster.auth.AuthDtos.UserView;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** 인증 API — backend/README.md "인증 API"와 같은 계약. */
@RestController
public class AuthController {

	private final AuthService auth;

	public AuthController(AuthService auth) {
		this.auth = auth;
	}

	@PostMapping("/auth/signup")
	@ResponseStatus(HttpStatus.CREATED)
	AuthResponse signUp(@RequestBody EmailRequest req) {
		return auth.signUp(req.email(), req.password());
	}

	@PostMapping("/auth/login")
	AuthResponse login(@RequestBody EmailRequest req) {
		return auth.login(req.email(), req.password());
	}

	@PostMapping("/auth/social/{provider}")
	AuthResponse social(@PathVariable String provider, @RequestBody SocialRequest req) {
		return auth.social(provider, req.token());
	}

	@PostMapping("/auth/refresh")
	AuthResponse refresh(@RequestBody RefreshRequest req) {
		return auth.refresh(req.refreshToken());
	}

	@PostMapping("/auth/logout")
	@ResponseStatus(HttpStatus.NO_CONTENT)
	void logout(@RequestBody RefreshRequest req) {
		auth.logout(req.refreshToken());
	}

	@GetMapping("/me")
	UserView me(@AuthenticationPrincipal Jwt jwt) {
		return auth.me(Long.valueOf(jwt.getSubject()));
	}

	/** 온보딩 완료 (본문 없음). 예전 앱이 보내던 {@code {"step":"DONE"}} 본문은 읽지 않는다. */
	@PatchMapping("/me/onboarding")
	UserView onboarding(@AuthenticationPrincipal Jwt jwt) {
		return auth.completeOnboarding(Long.valueOf(jwt.getSubject()));
	}
}
