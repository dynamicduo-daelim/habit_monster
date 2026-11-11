package kr.habitmonster.checkin;

import java.util.UUID;

import kr.habitmonster.ai.CheckinDialogues.Line;
import kr.habitmonster.checkin.CheckinChatService.InterpretRequest;
import kr.habitmonster.checkin.CheckinChatService.Interpreted;
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

/** 체크인 (API 명세 v6 "5. 챗봇 — 체크인"): 조회 · 제출 · 다시 체크 · 대화 해석 · 체크인 대사. */
@RestController
class CheckinController {

	private final CheckinService checkins;
	private final CheckinChatService chat;
	private final CheckinDialogueService dialogue;

	CheckinController(CheckinService checkins, CheckinChatService chat, CheckinDialogueService dialogue) {
		this.checkins = checkins;
		this.chat = chat;
		this.dialogue = dialogue;
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

	/** 체크인 대사 (명세 v6 5장). 최신 revision당 한 번만 만들고, 같은 revision이면 저장된 대사 — 그래서 중복 방지 키가 없다. */
	@PostMapping("/checkins/today/dialogue")
	Line dialogue(@AuthenticationPrincipal Jwt jwt) {
		return dialogue.dialogue(Long.parseLong(jwt.getSubject()));
	}

	/** 대화 해석 (제안 docs/제안/2026-10-30-AI챗봇-API.md). 확정하지 않으므로 중복 방지 키가 없다. */
	@PostMapping("/checkins/today/interpret")
	Interpreted interpret(@AuthenticationPrincipal Jwt jwt, @RequestBody InterpretRequest req) {
		return chat.interpret(Long.parseLong(jwt.getSubject()), req);
	}
}
