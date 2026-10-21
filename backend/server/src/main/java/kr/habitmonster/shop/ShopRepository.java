package kr.habitmonster.shop;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** {@code shop} 스키마만 읽고 쓴다. */
@Repository
class ShopRepository {

	record ItemRow(String code, String name, String shortName, int price, String effectType, int effectValue) {
	}

	record InventoryRow(String itemCode, String name, int quantity) {
	}

	private final JdbcClient db;

	ShopRepository(JdbcClient db) {
		this.db = db;
	}

	/** 파는 아이템 (시드 가격 · 효과, 진열 순서). */
	List<ItemRow> activeItems() {
		return db.sql("""
			select code, name, short_name, price, effect_type, effect_value from shop.shop_item
			 where is_active order by sort_order""")
			.query(ItemRow.class).list();
	}

	/** 가방 — 1개 이상 있는 아이템만 (결정 D-39). 행은 처음 살 때 생긴다. */
	List<InventoryRow> inventory(long userId) {
		return db.sql("""
			select i.item_code, s.name, i.quantity from shop.inventory i join shop.shop_item s on s.code = i.item_code
			 where i.user_id = ? and i.quantity > 0 order by s.sort_order""")
			.param(userId).query(InventoryRow.class).list();
	}

	int quantity(long userId, String itemCode) {
		return db.sql("select quantity from shop.inventory where user_id = ? and item_code = ?")
			.params(userId, itemCode).query(Integer.class).optional().orElse(0);
	}

	// ---------- 소모 (3-4 포획) ----------
	/** 조건부 차감: 1개 이상 있을 때만 1 줄이고 남은 개수. 없거나 0개면 비어 있다 (음수가 되지 않는다). */
	Optional<Integer> takeOne(long userId, String itemCode) {
		return db.sql("""
			update shop.inventory set quantity = quantity - 1, version = version + 1, updated_at = now()
			 where user_id = ? and item_code = ? and quantity >= 1 returning quantity""")
			.params(userId, itemCode).query(Integer.class).optional();
	}

	/** 소모 기록 1행 ({@code consumer_key}가 유일 — 같은 소모를 두 번 쓰지 않는다). 새 행 id. */
	long insertConsumption(long userId, String itemCode, String consumerKey) {
		return db.sql("""
			insert into shop.item_consumption (user_id, item_code, quantity, consumer_key) values (?, ?, 1, ?) returning id""")
			.params(userId, itemCode, consumerKey).query(Long.class).single();
	}

	// ---------- 구매 (3-5) ----------
	/** 파는 아이템 하나 (판매 중인 것만). */
	Optional<ItemRow> activeItem(String code) {
		return db.sql("""
			select code, name, short_name, price, effect_type, effect_value from shop.shop_item where code = ? and is_active""")
			.param(code).query(ItemRow.class).optional();
	}

	/** 구매 기록 (가격 스냅샷). 새 행 id = 원장 ref. */
	long insertPurchase(long userId, String itemCode, int quantity, int unitPrice, UUID key) {
		return db.sql("""
			insert into shop.purchase (user_id, item_code, quantity, unit_price, total_price, idempotency_key)
			values (?, ?, ?, ?, ?, ?) returning id""")
			.params(userId, itemCode, quantity, unitPrice, unitPrice * quantity, key).query(Long.class).single();
	}

	/** 가방에 더한다 (행은 처음 살 때 생긴다). 더한 뒤 개수. */
	int addToInventory(long userId, String itemCode, int quantity) {
		return db.sql("""
			insert into shop.inventory (user_id, item_code, quantity) values (?, ?, ?)
			on conflict (user_id, item_code)
			do update set quantity = shop.inventory.quantity + excluded.quantity, version = shop.inventory.version + 1,
			              updated_at = now()
			returning quantity""")
			.params(userId, itemCode, quantity).query(Integer.class).single();
	}
}
