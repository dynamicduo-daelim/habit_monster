package kr.habitmonster.monster;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** {@code monster} 스키마만 읽고 쓴다. */
@Repository
class MonsterRepository {

	record SpeciesRow(int id, String code, String categoryCode, String name, int rarity) {
	}

	private final JdbcClient db;

	MonsterRepository(JdbcClient db) {
		this.db = db;
	}

	/** 카테고리마다 스타터 종 1개 (DB가 카테고리당 최대 1개를 보장, 시드 v1.8은 6개 모두 있음). */
	List<SpeciesRow> starterSpecies() {
		return db.sql("select id, code, category_code, name, rarity from monster.monster_species where is_starter order by id")
			.query(SpeciesRow.class).list();
	}

	void createMonsterUser(long userId) {
		db.sql("insert into monster.monster_user (user_id) values (?)").param(userId).update();
	}

	long insertMonster(long userId, int speciesId, int affection, String location, boolean partner, String acquiredVia) {
		return db.sql("""
			insert into monster.user_monster (user_id, species_id, affection, location, is_partner, acquired_via)
			values (?, ?, ?, ?, ?, ?) returning id""")
			.params(userId, speciesId, affection, location, partner, acquiredVia).query(Long.class).single();
	}

	void insertStarterGrant(long userId, String categoryCode, long userMonsterId, int speciesId) {
		db.sql("""
			insert into monster.starter_grant (user_id, category_code, user_monster_id, species_id) values (?, ?, ?, ?)""")
			.params(userId, categoryCode, userMonsterId, speciesId).update();
	}

	/** 도감에 "가진 종"으로 등록 + 도감 수 +1. 이미 있으면 그대로 (false). */
	boolean addDexEntry(long userId, int speciesId) {
		boolean added = db.sql("insert into monster.dex_entry (user_id, species_id) values (?, ?) on conflict do nothing")
			.params(userId, speciesId).update() == 1;
		if (added) {
			db.sql("update monster.monster_user set dex_count = dex_count + 1, version = version + 1, updated_at = now() where user_id = ?")
				.param(userId).update();
		}
		return added;
	}

	// ---------- 조회 (3-2) ----------
	record MonsterRow(long userMonsterId, int speciesId, String code, String name, String categoryCode, int rarity,
			int displayHeight, String facing, int level, int expTotal, int affection, String location, boolean isPartner) {
	}

	private static final String MONSTER = """
		select m.id as user_monster_id, m.species_id, s.code, s.name, s.category_code, s.rarity, s.display_height, s.facing,
		       m.level, m.exp_total, m.affection, m.location, m.is_partner
		  from monster.user_monster m join monster.monster_species s on s.id = m.species_id
		""";

	/** @param location FIELD · BAG, null이면 전체. 얻은 순서대로. */
	List<MonsterRow> monsters(long userId, String location) {
		return db.sql(MONSTER + " where m.user_id = :user and (cast(:loc as text) is null or m.location = :loc) order by m.id")
			.param("user", userId).param("loc", location).query(MonsterRow.class).list();
	}

	/** 내 몬스터 한 마리. 남의 것이면 비어 있다 (소유권 검사 — 호출하는 쪽이 404). */
	Optional<MonsterRow> monster(long userId, long userMonsterId) {
		return db.sql(MONSTER + " where m.user_id = ? and m.id = ?").params(userId, userMonsterId)
			.query(MonsterRow.class).optional();
	}

	/** 그날 한 교감 행동 (PET · PLAY). */
	List<String> actionsOn(long userMonsterId, LocalDate day) {
		return db.sql("select action_type from monster.affection_action where user_monster_id = ? and action_date = ?")
			.params(userMonsterId, day).query(String.class).list();
	}

	record QuotaRow(int baseCount, int usedCount) {
	}

	/** 그날 탐색 기회 (체크인 첫 제출 때 생긴다). */
	Optional<QuotaRow> quota(long userId, LocalDate day) {
		return db.sql("select base_count, used_count from monster.daily_explore_quota where user_id = ? and quota_date = ?")
			.params(userId, day).query(QuotaRow.class).optional();
	}
}
