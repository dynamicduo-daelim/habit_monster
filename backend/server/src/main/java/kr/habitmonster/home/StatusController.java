package kr.habitmonster.home;

import kr.habitmonster.home.StatusService.Status;
import kr.habitmonster.home.StatusService.Today;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** 상단 바 · 오늘 요약 (API 명세 v5 "3. 상단 바 · 메인 화면"). */
@RestController
class StatusController {

	private final StatusService status;

	StatusController(StatusService status) {
		this.status = status;
	}

	@GetMapping("/me/status")
	Status status(@AuthenticationPrincipal Jwt jwt) {
		return status.status(Long.parseLong(jwt.getSubject()));
	}

	@GetMapping("/me/today")
	Today today(@AuthenticationPrincipal Jwt jwt) {
		return status.today(Long.parseLong(jwt.getSubject()));
	}
}
