package kr.habitmonster.shop;

import java.util.UUID;

import kr.habitmonster.idempotency.Idempotent;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.shop.ShopService.Inventory;
import kr.habitmonster.shop.ShopService.PurchaseRequest;
import kr.habitmonster.shop.ShopService.Purchased;
import kr.habitmonster.shop.ShopService.Shop;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** 상점 · 가방 API (API 명세 v5 "3. 메인 화면"). 구매는 3-5단계. */
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

	/** 구매 (상점 창 · 챗봇의 "볼 사기"). 키는 {@code shop.purchase.idempotency_key}에도 남는다. */
	@Idempotent
	@PostMapping("/shop/purchases")
	@ResponseStatus(HttpStatus.CREATED)
	Purchased purchase(@AuthenticationPrincipal Jwt jwt, @RequestHeader(IdempotencyFilter.HEADER) UUID key,
			@RequestBody PurchaseRequest req) {
		return shop.purchase(Long.parseLong(jwt.getSubject()), key, req);
	}
}
