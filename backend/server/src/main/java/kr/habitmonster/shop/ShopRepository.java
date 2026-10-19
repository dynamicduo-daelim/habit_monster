package kr.habitmonster.shop;

import java.util.List;

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
}
