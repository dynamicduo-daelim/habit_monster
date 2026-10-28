package kr.habitmonster.stats;

import kr.habitmonster.stats.StatsService.Stats;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** 통계 API (API 명세 v5 "6. 통계", 4-4). 경로는 {@code /api/v1} 뒤. */
@RestController
class StatsController {

	private final StatsService stats;

	StatsController(StatsService stats) {
		this.stats = stats;
	}

	@GetMapping("/stats")
	Stats stats(@AuthenticationPrincipal Jwt jwt) {
		return stats.stats(Long.parseLong(jwt.getSubject()));
	}
}
