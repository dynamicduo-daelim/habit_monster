package kr.habitmonster.checkin;

import java.util.UUID;

import kr.habitmonster.checkin.CheckinService.CheckinRequest;
import kr.habitmonster.checkin.CheckinService.Submitted;
import kr.habitmonster.checkin.CheckinService.TodayCheckin;
import kr.habitmonster.habit.HabitService.Revision;
import kr.habitmonster.idempotency.Idempotent;
import kr.habitmonster.idempotency.IdempotencyFilter;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** 체크인 (API 명세 v5 "5. 챗봇 — 체크인"). 대사 요청({@code /checkins/today/dialogue})은 5단계. */
@RestController
class CheckinController {

	private final CheckinService checkins;

	CheckinController(CheckinService checkins) {
		this.checkins = checkins;
	}

	@GetMapping("/checkins/today")
	TodayCheckin today(@AuthenticationPrincipal Jwt jwt) {
		return checkins.today(Long.parseLong(jwt.getSubject()));
	}

	/** 첫 제출. 키는 {@code habit.checkin_submission}에도 남는다 (제출 1건 = 1행). */
	@Idempotent
	@PostMapping("/checkins/today")
	@ResponseStatus(HttpStatus.CREATED)
	Submitted submit(@AuthenticationPrincipal Jwt jwt, @RequestHeader(IdempotencyFilter.HEADER) UUID key,
			@RequestBody CheckinRequest req) {
		return checkins.submit(Long.parseLong(jwt.getSubject()), key, req);
	}

	/** 다시 체크. 보상은 바뀌지 않는다. */
	@Idempotent
	@PutMapping("/checkins/today")
	Revision resubmit(@AuthenticationPrincipal Jwt jwt, @RequestHeader(IdempotencyFilter.HEADER) UUID key,
			@RequestBody CheckinRequest req) {
		return checkins.resubmit(Long.parseLong(jwt.getSubject()), key, req);
	}
}
