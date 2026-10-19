package kr.habitmonster.onboarding;

import java.util.List;

import kr.habitmonster.idempotency.Idempotent;
import kr.habitmonster.onboarding.OnboardingService.CategoryView;
import kr.habitmonster.onboarding.OnboardingService.OnboardingRequest;
import kr.habitmonster.onboarding.OnboardingService.OnboardingResult;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** 온보딩 API (API 명세 v5 "2. 온보딩"). 온보딩 전에도 부를 수 있다 ({@code UserGateFilter.BEFORE_ONBOARDING}). */
@RestController
class OnboardingController {

	private final OnboardingService onboarding;

	OnboardingController(OnboardingService onboarding) {
		this.onboarding = onboarding;
	}

	@GetMapping("/categories")
	List<CategoryView> categories(@AuthenticationPrincipal Jwt jwt) {
		return onboarding.categories(Long.parseLong(jwt.getSubject()));
	}

	/** 온보딩 일괄 제출. 버튼을 두 번 누르거나 응답을 못 받아 다시 보내도 한 번만 처리되게 중복 방지 키 필수 (결정 A3). */
	@Idempotent
	@PostMapping("/onboarding")
	@ResponseStatus(HttpStatus.CREATED)
	OnboardingResult complete(@AuthenticationPrincipal Jwt jwt, @RequestBody OnboardingRequest req) {
		return onboarding.complete(Long.parseLong(jwt.getSubject()), req);
	}
}
