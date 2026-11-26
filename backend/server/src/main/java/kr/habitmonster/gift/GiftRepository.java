package kr.habitmonster.gift;

import java.util.List;
import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** {@code gift} 스키마만 읽고 쓴다 (모듈 = 스키마). */
@Repository
class GiftRepository {

	/** 선물 한 줄. {@code itemCode}가 없으면 {@code itemQuantity}는 0. {@code createdMs} = 만든 시각(밀리초). */
	record GiftRow(long id, String sourceCode, String title, int gold, String itemCode, int itemQuantity, long createdMs,
			boolean claimed) {
	}

	private static final String COLUMNS = """
		id, source_code, title, gold, item_code, coalesce(item_quantity, 0) as item_quantity,
		(extract(epoch from created_at) * 1000)::bigint as created_ms, claimed_at is not null as claimed""";

	private final JdbcClient db;

	GiftRepository(JdbcClient db) {
		this.db = db;
	}

	/**
	 * 선물 한 줄을 넣는다. 같은 출처 · 출처 번호가 이미 있으면 아무것도 하지 않는다 ({@code UNIQUE(source_code, source_ref)}).
	 * 새 행만 넣고 있는 행은 잠그지 않는다 — 퀘스트 경로의 잠금 순서 {@code … → quest → gift} (D-89).
	 */
	void insert(long userId, GiftSource source, String sourceRef, String title, int gold, String itemCode,
			Integer itemQuantity) {
		db.sql("""
			insert into gift.gift (user_id, source_code, source_ref, title, gold, item_code, item_quantity)
			values (?, ?, ?, ?, ?, ?, ?)
			on conflict (source_code, source_ref) do nothing""")
			.params(userId, source.name(), sourceRef, title, gold, itemCode, itemQuantity).update();
	}

	/** 받지 않은 선물, 최신순 (잠그지 않음 — 조회용). */
	List<GiftRow> unclaimed(long userId) {
		return db.sql("select " + COLUMNS + " from gift.gift where user_id = ? and claimed_at is null order by id desc")
			.param(userId).query(GiftRow.class).list();
	}

	boolean hasUnclaimed(long userId) {
		return db.sql("select exists (select 1 from gift.gift where user_id = ? and claimed_at is null)")
			.param(userId).query(Boolean.class).single();
	}

	/** 내 선물 하나를 잠근다 (받기의 첫 단계 — 잠금 순서 맨 앞). 없거나 남의 것이면 비어 있다. */
	Optional<GiftRow> lockOne(long userId, long giftId) {
		return db.sql("select " + COLUMNS + " from gift.gift where id = ? and user_id = ? for no key update")
			.params(giftId, userId).query(GiftRow.class).optional();
	}

	/** 받지 않은 선물을 모두 잠근다 — id 순서로 (두 "모두 받기"가 같은 순서로 잠가 서로 기다리다 멈추지 않게). */
	List<GiftRow> lockUnclaimed(long userId) {
		return db.sql("select " + COLUMNS
				+ " from gift.gift where user_id = ? and claimed_at is null order by id for no key update")
			.param(userId).query(GiftRow.class).list();
	}

	/** 받음 표시. 잠근 행만 부른다 — 받은 시각은 한 번만 쓸 수 있다 (트리거 {@code tg_gift_fixed}). */
	void markClaimed(List<Long> giftIds) {
		db.sql("update gift.gift set claimed_at = now() where id in (:ids) and claimed_at is null")
			.param("ids", giftIds).update();
	}
}
