package kr.habitmonster.monster;

import java.util.List;
import java.util.Set;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.monster.MonsterService.MonsterDetail;
import kr.habitmonster.monster.MonsterService.MonsterView;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 몬스터 API (API 명세 v5 "3. 메인 화면"). 지금은 조회만 — 교감 · 간식 · 필드/가방은 3-5단계. */
@RestController
class MonsterController {

	private static final Set<String> LOCATIONS = Set.of("FIELD", "BAG");

	private final MonsterService monsters;

	MonsterController(MonsterService monsters) {
		this.monsters = monsters;
	}

	/** {@code location}: FIELD(메인 필드) · BAG(가방) · 생략하면 전체(대화 상대 고르기). */
	@GetMapping("/monsters")
	List<MonsterView> monsters(@AuthenticationPrincipal Jwt jwt, @RequestParam(required = false) String location) {
		if (location != null && !LOCATIONS.contains(location)) {
			throw new ApiException(ErrorCode.INVALID_REQUEST);
		}
		return monsters.monsters(Long.parseLong(jwt.getSubject()), location);
	}

	@GetMapping("/monsters/{id}")
	MonsterDetail monster(@AuthenticationPrincipal Jwt jwt, @PathVariable long id) {
		return monsters.monster(Long.parseLong(jwt.getSubject()), id);
	}
}
