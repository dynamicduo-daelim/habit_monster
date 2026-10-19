package kr.habitmonster.goal;

import kr.habitmonster.goal.GoalService.CurrentGoals;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** 목표 API (API 명세 v5 "8. 목표"). 지금은 조회만 — 등록 · 수정 · 완료는 4단계. */
@RestController
class GoalController {

	private final GoalService goals;

	GoalController(GoalService goals) {
		this.goals = goals;
	}

	@GetMapping("/goals")
	CurrentGoals goals(@AuthenticationPrincipal Jwt jwt) {
		return goals.current(Long.parseLong(jwt.getSubject()));
	}
}
