package kr.habitmonster.shop;

import kr.habitmonster.shop.ShopService.Inventory;
import kr.habitmonster.shop.ShopService.Shop;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** 상점 · 가방 API (API 명세 v5 "3. 메인 화면"). 지금은 조회만 — 구매는 3-5단계. */
@RestController
class ShopController {

	private final ShopService shop;

	ShopController(ShopService shop) {
		this.shop = shop;
	}

	@GetMapping("/shop/items")
	Shop items(@AuthenticationPrincipal Jwt jwt) {
		return shop.items(Long.parseLong(jwt.getSubject()));
	}

	/** 가방의 아이템 탭. 몬스터 탭은 {@code GET /monsters?location=BAG}. */
	@GetMapping("/inventory")
	Inventory inventory(@AuthenticationPrincipal Jwt jwt) {
		return shop.inventory(Long.parseLong(jwt.getSubject()));
	}
}
