package kr.habitmonster.monster;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.idempotency.Idempotent;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.monster.MonsterService.AffectionRequest;
import kr.habitmonster.monster.MonsterService.AffectionResult;
import kr.habitmonster.monster.MonsterService.Fed;
import kr.habitmonster.monster.MonsterService.FeedRequest;
import kr.habitmonster.monster.MonsterService.Line;
import kr.habitmonster.monster.MonsterService.LocationRequest;
import kr.habitmonster.monster.MonsterService.MonsterDetail;
import kr.habitmonster.monster.MonsterService.MonsterView;
import kr.habitmonster.monster.MonsterService.Moved;
import kr.habitmonster.monster.MonsterService.PartnerChanged;
import kr.habitmonster.monster.MonsterService.PartnerRequest;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 몬스터 API (API 명세 v5 "3. 메인 화면"). 조회(3-2) + 간식(물약) · 교감 · 말 걸기 · 필드/가방 · 대화 상대(3-5). */
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

	/** 간식 주기 = 경험치 물약 먹이기. 소모 기록 키 = {@code FEED:<중복 방지 키>}. */
	@Idempotent
	@PostMapping("/monsters/{id}/feed")
	Fed feed(@AuthenticationPrincipal Jwt jwt, @PathVariable long id, @RequestHeader(IdempotencyFilter.HEADER) UUID key,
			@RequestBody FeedRequest req) {
		return monsters.feed(Long.parseLong(jwt.getSubject()), id, key, req);
	}

	/** 쓰다듬기 · 놀아주기 (명세대로 중복 방지 키 없음 — 하루 1번은 DB 기본 키가 막는다). */
	@PostMapping("/monsters/{id}/affection")
	AffectionResult affection(@AuthenticationPrincipal Jwt jwt, @PathVariable long id, @RequestBody AffectionRequest req) {
		return monsters.affection(Long.parseLong(jwt.getSubject()), id, req);
	}

	@GetMapping("/monsters/{id}/line")
	Line line(@AuthenticationPrincipal Jwt jwt, @PathVariable long id) {
		return monsters.line(Long.parseLong(jwt.getSubject()), id);
	}

	@PatchMapping("/monsters/{id}/location")
	Moved move(@AuthenticationPrincipal Jwt jwt, @PathVariable long id, @RequestBody LocationRequest req) {
		return monsters.move(Long.parseLong(jwt.getSubject()), id, req);
	}

	/** 메인 팝업의 "대화 상대로" · 챗봇 상단 선택. */
	@PutMapping("/me/partner")
	PartnerChanged partner(@AuthenticationPrincipal Jwt jwt, @RequestBody PartnerRequest req) {
		return monsters.changePartner(Long.parseLong(jwt.getSubject()), req);
	}
}
