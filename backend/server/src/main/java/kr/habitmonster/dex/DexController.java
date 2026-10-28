package kr.habitmonster.dex;

import kr.habitmonster.dex.DexService.DexCategory;
import kr.habitmonster.dex.DexService.DexDetail;
import kr.habitmonster.dex.DexService.DexSummary;
import kr.habitmonster.dex.DexService.Unlocked;
import kr.habitmonster.idempotency.Idempotent;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** 도감 · 카테고리 열기 API (API 명세 v5 "7. 도감", 4-3). 경로는 {@code /api/v1} 뒤. */
@RestController
class DexController {

	private final DexService dex;

	DexController(DexService dex) {
		this.dex = dex;
	}

	@GetMapping("/dex")
	DexSummary summary(@AuthenticationPrincipal Jwt jwt) {
		return dex.summary(Long.parseLong(jwt.getSubject()));
	}

	@GetMapping("/dex/categories/{code}")
	DexCategory category(@AuthenticationPrincipal Jwt jwt, @PathVariable String code) {
		return dex.category(Long.parseLong(jwt.getSubject()), code);
	}

	@GetMapping("/dex/species/{speciesId}")
	DexDetail species(@AuthenticationPrincipal Jwt jwt, @PathVariable int speciesId) {
		return dex.species(Long.parseLong(jwt.getSubject()), speciesId);
	}

	/** 카테고리 열기. 중복 방지 키 필수 (명세) — 같은 키로 다시 보내면 첫 응답, 해금권은 한 장만. */
	@Idempotent
	@PostMapping("/categories/{code}/unlock")
	@ResponseStatus(HttpStatus.CREATED)
	Unlocked unlock(@AuthenticationPrincipal Jwt jwt, @PathVariable String code) {
		return dex.unlock(Long.parseLong(jwt.getSubject()), code);
	}
}
