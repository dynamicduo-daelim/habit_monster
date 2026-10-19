package kr.habitmonster.shop;

import java.util.List;

import kr.habitmonster.wallet.WalletService;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 상점 · 가방 모듈. 골드는 지갑 모듈({@link WalletService})이 가진다. */
@Service
public class ShopService {

	/** 성실볼 (포획용) 아이템 코드. */
	public static final String BALL = "BALL";

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
}
