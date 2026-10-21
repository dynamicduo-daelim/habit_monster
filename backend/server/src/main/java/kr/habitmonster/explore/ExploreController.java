package kr.habitmonster.explore;

import java.util.UUID;

import kr.habitmonster.explore.ExploreService.CaptureResult;
import kr.habitmonster.explore.ExploreService.ExploreRequest;
import kr.habitmonster.explore.ExploreService.ExploreResult;
import kr.habitmonster.idempotency.Idempotent;
import kr.habitmonster.idempotency.IdempotencyFilter;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** 탐색 · 포획 (API 명세 v5 "5. 챗봇 — 탐색"). "그만" 버튼은 서버를 부르지 않는다. */
@RestController
class ExploreController {

	private final ExploreService explores;

	ExploreController(ExploreService explores) {
		this.explores = explores;
	}

	/** 탐색 1회. 키는 {@code monster.explore_log}에도 남는다 (탐색 1회 = 1행). */
	@Idempotent
	@PostMapping("/explores")
	@ResponseStatus(HttpStatus.CREATED)
	ExploreResult explore(@AuthenticationPrincipal Jwt jwt, @RequestHeader(IdempotencyFilter.HEADER) UUID key,
			@RequestBody ExploreRequest req) {
		return explores.explore(Long.parseLong(jwt.getSubject()), key, req);
	}

	/** 챗봇 화면에 들어올 때: 오늘 처리하지 않은 등장 (200) 또는 없음 (204). */
	@GetMapping("/explores/pending")
	ResponseEntity<ExploreResult> pending(@AuthenticationPrincipal Jwt jwt) {
		return explores.pending(Long.parseLong(jwt.getSubject())).map(ResponseEntity::ok)
			.orElseGet(() -> ResponseEntity.noContent().build());
	}

	/** 볼 던지기. 소모 기록 키 = {@code CAPTURE:<중복 방지 키>}. */
	@Idempotent
	@PostMapping("/explores/{exploreId}/capture")
	CaptureResult capture(@AuthenticationPrincipal Jwt jwt, @PathVariable long exploreId,
			@RequestHeader(IdempotencyFilter.HEADER) UUID key, @RequestBody ExploreRequest req) {
		return explores.capture(Long.parseLong(jwt.getSubject()), exploreId, key, req);
	}
}
