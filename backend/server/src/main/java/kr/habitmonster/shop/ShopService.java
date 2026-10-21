package kr.habitmonster.shop;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.shop.ShopRepository.ItemRow;
import kr.habitmonster.wallet.LedgerReason;
import kr.habitmonster.wallet.WalletService;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 상점 · 가방 모듈. 골드는 지갑 모듈({@link WalletService})이 가진다. */
@Service
public class ShopService {

	/** 성실볼 (포획용) 아이템 코드. */
	public static final String BALL = "BALL";

	/** 한 번에 살 수 있는 개수 (명세: 1 ~ 99). */
	static final int MAX_QUANTITY = 99;

	public record Item(String code, String name, String shortName, int price, String effectType, int effectValue) {
	}

	/** {@code GET /shop/items} — 상점 창 위쪽에 지금 골드도 보여 준다. */
	public record Shop(long gold, List<Item> items) {
	}

	public record InventoryItem(String itemCode, String name, int quantity) {
	}

	/** {@code GET /inventory}. */
	public record Inventory(List<InventoryItem> items) {
	}

	private final ShopRepository shop;
	private final WalletService wallet;

	ShopService(ShopRepository shop, WalletService wallet) {
		this.shop = shop;
		this.wallet = wallet;
	}

	@Transactional(readOnly = true)
	public Shop items(long userId) {
		List<Item> items = shop.activeItems().stream()
			.map(i -> new Item(i.code(), i.name(), i.shortName(), i.price(), i.effectType(), i.effectValue()))
			.toList();
		return new Shop(wallet.balance(userId), items);
	}

	@Transactional(readOnly = true)
	public Inventory inventory(long userId) {
		return new Inventory(shop.inventory(userId).stream()
			.map(i -> new InventoryItem(i.itemCode(), i.name(), i.quantity())).toList());
	}

	/** 가방에 있는 개수 (없으면 0). */
	@Transactional(readOnly = true)
	public int quantity(long userId, String itemCode) {
		return shop.quantity(userId, itemCode);
	}

	/** 아이템 하나를 쓴 결과: 소모 기록 id(탐색 · 성장 기록이 참조) · 남은 개수. */
	public record Consumed(long consumptionId, int remaining) {
	}

	/**
	 * 성실볼 1개를 쓴다 (포획). 조건부 차감이라 동시에 와도 음수가 되지 않고, 소모 기록은 {@code consumerKey}
	 * (예: {@code CAPTURE:<중복 방지 키>})로 한 번만 남는다.
	 *
	 * @throws ApiException 422 {@code NO_BALL} — 볼이 없으면 아무것도 바뀌지 않는다
	 */
	@Transactional
	public Consumed useBall(long userId, String consumerKey) {
		return use(userId, BALL, consumerKey, ErrorCode.NO_BALL);
	}

	/**
	 * 경험치 물약 1개를 쓴다 (먹이기, {@code FEED:<키>}). 물약의 경험치는 {@link #potionExp}.
	 *
	 * @throws ApiException 422 {@code NO_ITEM}
	 */
	@Transactional
	public Consumed usePotion(long userId, String itemCode, String consumerKey) {
		return use(userId, itemCode, consumerKey, ErrorCode.NO_ITEM);
	}

	private Consumed use(long userId, String itemCode, String consumerKey, ErrorCode none) {
		int remaining = shop.takeOne(userId, itemCode).orElseThrow(() -> new ApiException(none));
		return new Consumed(shop.insertConsumption(userId, itemCode, consumerKey), remaining);
	}

	/** 경험치 물약이면 그 경험치, 아니면(성실볼 · 없는 코드) 비어 있다. */
	@Transactional(readOnly = true)
	public Optional<Integer> potionExp(String itemCode) {
		return shop.activeItem(itemCode).filter(i -> i.effectType().equals("MONSTER_EXP")).map(ItemRow::effectValue);
	}

	// ---------- 구매 (3-5) ----------
	public record PurchaseRequest(String itemCode, Integer quantity) {
	}

	/** {@code POST /shop/purchases} 응답. {@code quantity}는 산 뒤 가방에 있는 개수 (명세). */
	public record Purchased(long purchaseId, int totalPrice, long gold, String itemCode, int quantity) {
	}

	/**
	 * 구매: 가격은 서버의 상점 가격(앱이 보낸 값이 아니다) → 구매 기록 → 가방 → 지갑 차감 (잠금 순서 inventory → wallet).
	 * 골드가 모자라면 지갑이 422를 내고 트랜잭션 전체가 되돌아가 구매 기록 · 가방도 남지 않는다.
	 *
	 * @throws ApiException 400 수량 1 ~ 99 밖 · 없는 아이템, 422 {@code NOT_ENOUGH_GOLD}
	 */
	@Transactional
	public Purchased purchase(long userId, UUID key, PurchaseRequest req) {
		if (req.quantity() == null || req.quantity() < 1 || req.quantity() > MAX_QUANTITY || req.itemCode() == null) {
			throw new ApiException(ErrorCode.INVALID_REQUEST);
		}
		ItemRow item = shop.activeItem(req.itemCode()).orElseThrow(() -> new ApiException(ErrorCode.INVALID_REQUEST));
		long purchaseId = shop.insertPurchase(userId, item.code(), req.quantity(), item.price(), key);
		int quantity = shop.addToInventory(userId, item.code(), req.quantity());
		int total = item.price() * req.quantity();
		long gold = wallet.debit(userId, total, LedgerReason.SHOP_PURCHASE, String.valueOf(purchaseId)).balance();
		return new Purchased(purchaseId, total, gold, item.code(), quantity);
	}
}
