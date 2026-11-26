package kr.habitmonster.gift;

import kr.habitmonster.gift.GiftService.Claimed;
import kr.habitmonster.gift.GiftService.Gifts;
import kr.habitmonster.idempotency.Idempotent;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

/** 선물함 API (API 명세 v10 11장). 경로는 {@code /api/v1} 뒤. 받기는 중복 방지 키 필수 · {@code businessDate} 없음. */
@RestController
class GiftController {

	private final GiftService gifts;

	GiftController(GiftService gifts) {
		this.gifts = gifts;
	}

	/** 받지 않은 선물만, 최신순. */
	@GetMapping("/gifts")
	Gifts list(@AuthenticationPrincipal Jwt jwt) {
		return gifts.list(Long.parseLong(jwt.getSubject()));
	}

	@Idempotent
	@PostMapping("/gifts/{giftId}/claim")
	Claimed claim(@AuthenticationPrincipal Jwt jwt, @PathVariable long giftId) {
		return gifts.claim(Long.parseLong(jwt.getSubject()), giftId);
	}

	@Idempotent
	@PostMapping("/gifts/claim-all")
	Claimed claimAll(@AuthenticationPrincipal Jwt jwt) {
		return gifts.claimAll(Long.parseLong(jwt.getSubject()));
	}
}
