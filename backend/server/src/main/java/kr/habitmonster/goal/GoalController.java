package kr.habitmonster.goal;

import java.util.Map;

import kr.habitmonster.goal.GoalService.Completed;
import kr.habitmonster.goal.GoalService.CurrentGoals;
import kr.habitmonster.goal.GoalService.GoalView;
import kr.habitmonster.goal.GoalService.NewGoal;
import kr.habitmonster.idempotency.Idempotent;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** 목표 API (API 명세 v5 "8. 목표" + 보충 10-28). 경로는 {@code /api/v1} 뒤. */
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

	/** 목표 등록. 버튼을 두 번 눌러도 하나만 생기게 중복 방지 키 필수 (A3). */
	@Idempotent
	@PostMapping("/goals")
	@ResponseStatus(HttpStatus.CREATED)
	GoalView create(@AuthenticationPrincipal Jwt jwt, @RequestBody NewGoal req) {
		return goals.create(Long.parseLong(jwt.getSubject()), req);
	}

	/** 목표 수정. 본문을 Map으로 받아 "안 보낸 필드"와 {@code null}(지우기)을 가른다. */
	@PatchMapping("/goals/{goalId}")
	GoalView update(@AuthenticationPrincipal Jwt jwt, @PathVariable long goalId, @RequestBody Map<String, Object> body) {
		return goals.update(Long.parseLong(jwt.getSubject()), goalId, body);
	}

	/** 목표 삭제. 두 번 보내면 두 번째는 404라 중복 방지 키가 필요 없다. */
	@DeleteMapping("/goals/{goalId}")
	@ResponseStatus(HttpStatus.NO_CONTENT)
	void delete(@AuthenticationPrincipal Jwt jwt, @PathVariable long goalId) {
		goals.delete(Long.parseLong(jwt.getSubject()), goalId);
	}

	/** 목표 완료. 중복 방지 키 필수 (명세) — 같은 키로 다시 보내면 첫 응답, 골드는 한 번만. */
	@Idempotent
	@PostMapping("/goals/{goalId}/complete")
	Completed complete(@AuthenticationPrincipal Jwt jwt, @PathVariable long goalId) {
		return goals.complete(Long.parseLong(jwt.getSubject()), goalId);
	}
}
