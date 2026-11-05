package kr.habitmonster.habit;

import kr.habitmonster.habit.TimerService.StartTimer;
import kr.habitmonster.habit.TimerService.TimerAction;
import kr.habitmonster.habit.TimerService.TimerView;
import kr.habitmonster.habit.TimerService.TodayTimers;
import kr.habitmonster.idempotency.Idempotent;

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

/** 습관 타이머 (API 명세 v6 9장). 시작 · 일시정지 · 이어서 · 끝내기는 중복 방지 키 필수 (버튼을 두 번 눌러도 한 번만). */
@RestController
class TimerController {

	private final TimerService timers;

	TimerController(TimerService timers) {
		this.timers = timers;
	}

	@Idempotent
	@PostMapping("/timers")
	@ResponseStatus(HttpStatus.CREATED)
	TimerView start(@AuthenticationPrincipal Jwt jwt, @RequestBody StartTimer req) {
		return timers.start(Long.parseLong(jwt.getSubject()), req);
	}

	@Idempotent
	@PatchMapping("/timers/{timerId}")
	TimerView act(@AuthenticationPrincipal Jwt jwt, @PathVariable long timerId, @RequestBody TimerAction req) {
		return timers.act(Long.parseLong(jwt.getSubject()), timerId, req);
	}

	@GetMapping("/timers/today")
	TodayTimers today(@AuthenticationPrincipal Jwt jwt) {
		return timers.today(Long.parseLong(jwt.getSubject()));
	}
}
