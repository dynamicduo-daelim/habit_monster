package kr.habitmonster.habit;

import java.util.Arrays;
import java.util.List;
import java.util.Set;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.habit.HabitService.Attendance;
import kr.habitmonster.habit.HabitService.Category;
import kr.habitmonster.habit.HabitService.HabitView;
import kr.habitmonster.habit.HabitService.MeasureTypeGroup;
import kr.habitmonster.habit.HabitService.NewHabit;
import kr.habitmonster.habit.HabitService.Renewal;
import kr.habitmonster.habit.HabitService.Stopped;
import kr.habitmonster.idempotency.Idempotent;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** 습관 API (API 명세 v5 "1. 출석" · "2. 온보딩"의 측정 항목 · "4. 습관"). 경로는 {@code /api/v1} 뒤. */
@RestController
class HabitController {

	private final HabitService habits;

	HabitController(HabitService habits) {
		this.habits = habits;
	}

	/** 측정 항목 + 추천 습관. {@code categories}를 생략하면 전체. 모르는 카테고리 코드면 400. */
	@GetMapping("/measure-types")
	List<MeasureTypeGroup> measureTypes(@RequestParam(required = false) String categories) {
		Set<String> all = Set.copyOf(habits.categories().stream().map(Category::code).toList());
		if (categories == null || categories.isBlank()) {
			return habits.measureTypes(all);
		}
		List<String> codes = Arrays.stream(categories.split(",")).map(String::trim).filter(s -> !s.isEmpty()).toList();
		if (!all.containsAll(codes)) {
			throw new ApiException(ErrorCode.INVALID_REQUEST);
		}
		return habits.measureTypes(codes);
	}

	/** 내 습관 (명세 4장). {@code status}는 쉼표로 여러 개, 생략하면 ACTIVE · ENDED. 모르는 상태면 400. */
	@GetMapping("/habits")
	List<HabitView> habits(@AuthenticationPrincipal Jwt jwt, @RequestParam(required = false) String status) {
		Set<String> statuses = HabitService.DEFAULT_STATUSES;
		if (status != null && !status.isBlank()) {
			statuses = Set.copyOf(Arrays.stream(status.split(",")).map(String::trim).toList());
			if (!statuses.stream().allMatch(HabitService::isStatus)) {
				throw new ApiException(ErrorCode.INVALID_REQUEST);
			}
		}
		return habits.habits(Long.parseLong(jwt.getSubject()), statuses);
	}

	/** 습관 추가 (4-1). 버튼을 두 번 눌러도 한 번만 생기게 중복 방지 키 필수 (A3). */
	@Idempotent
	@PostMapping("/habits")
	@ResponseStatus(HttpStatus.CREATED)
	HabitView create(@AuthenticationPrincipal Jwt jwt, @RequestBody NewHabit req) {
		return habits.create(Long.parseLong(jwt.getSubject()), req);
	}

	/** 기간 연장 (4-1). 중복 방지 키 필수 (A3) — 같은 키로 다시 보내면 첫 응답, 새 기간은 한 번만. */
	@Idempotent
	@PostMapping("/habits/{habitId}/renew")
	HabitView renew(@AuthenticationPrincipal Jwt jwt, @PathVariable long habitId, @RequestBody Renewal req) {
		return habits.renew(Long.parseLong(jwt.getSubject()), habitId, req);
	}

	/** 그만두기 (4-1). 두 번 보내면 두 번째는 409라 중복 방지 키가 필요 없다. */
	@PostMapping("/habits/{habitId}/stop")
	Stopped stop(@AuthenticationPrincipal Jwt jwt, @PathVariable long habitId) {
		return habits.stop(Long.parseLong(jwt.getSubject()), habitId);
	}

	/** 출석 — 앱을 켜거나 돌아올 때 자동으로. 하루에 여러 번 불러도 된다 (중복 방지 키 필요 없음). */
	@PostMapping("/me/attendance")
	Attendance attend(@AuthenticationPrincipal Jwt jwt) {
		return habits.attend(Long.parseLong(jwt.getSubject()));
	}
}
