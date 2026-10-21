package kr.habitmonster.monster;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

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

	// ---------- 체크인 (3-3) ----------
	void insertQuota(long userId, LocalDate day, int baseCount, long sourceCheckinId) {
		db.sql("""
			insert into monster.daily_explore_quota (user_id, quota_date, base_count, source_checkin_id) values (?, ?, ?, ?)""")
			.params(userId, day, baseCount, sourceCheckinId).update();
	}

	void insertQuotaCategory(long userId, LocalDate day, String categoryCode) {
		db.sql("insert into monster.explore_quota_category (user_id, quota_date, category_code) values (?, ?, ?)")
			.params(userId, day, categoryCode).update();
	}

	/** 카테고리 레벨이 {@code from} → {@code to}로 오르며 새로 탐색 후보가 된 종 (출현 레벨이 그 사이). 종 번호 순서. */
	List<Integer> speciesUnlockedBetween(String categoryCode, int from, int to) {
		return db.sql("""
			select id from monster.monster_species where category_code = ? and unlock_level > ? and unlock_level <= ?
			 order by id""")
			.params(categoryCode, from, to).query(Integer.class).list();
	}

	/** 대화 상대 (온보딩 때 정한 한 마리). */
	Optional<MonsterRow> partner(long userId) {
		return db.sql(MONSTER + " where m.user_id = ? and m.is_partner").param(userId).query(MonsterRow.class).optional();
	}

	// ---------- 탐색 · 포획 (3-4) ----------
	/**
	 * 탐색 기회 1회 사용 (조건부: 남아 있을 때만). 쓴 뒤의 사용 횟수 = 이번 탐색의 순번.
	 * 기회 행이 없거나 다 썼으면 비어 있다 — 어느 쪽인지는 {@link #quota}로 가린다.
	 */
	Optional<Integer> useExplore(long userId, LocalDate day) {
		return db.sql("""
			update monster.daily_explore_quota set used_count = used_count + 1, version = version + 1
			 where user_id = ? and quota_date = ? and used_count < base_count returning used_count""")
			.params(userId, day).query(Integer.class).optional();
	}

	record ClosedRow(long id, String outcome) {
	}

	/** 처리 전 등장(사용자당 최대 1건)을 닫는다: 오늘 것이면 SKIPPED, 지난 날 것이면 EXPIRED. */
	Optional<ClosedRow> closePending(long userId, LocalDate today) {
		return db.sql("""
			update monster.explore_log
			   set outcome = case when quota_date = ? then 'SKIPPED' else 'EXPIRED' end, resolved_at = now()
			 where user_id = ? and result = 'ENCOUNTER' and outcome is null returning id, outcome""")
			.params(today, userId).query(ClosedRow.class).optional();
	}

	record CandidateRow(int id, String code, String name, String categoryCode, int rarity, int unlockLevel,
			boolean owned) {
	}

	/** 그날 탐색 카테고리의 모든 종 + 가졌는지(도감 = 가진 종). 출현 레벨 거르기는 서비스가 한다. 종 번호 순서. */
	List<CandidateRow> candidates(long userId, LocalDate day) {
		return db.sql("""
			select s.id, s.code, s.name, s.category_code, s.rarity, s.unlock_level, (d.species_id is not null) as owned
			  from monster.monster_species s
			  join monster.explore_quota_category q
			    on q.category_code = s.category_code and q.user_id = :user and q.quota_date = :day
			  left join monster.dex_entry d on d.user_id = :user and d.species_id = s.id
			 order by s.id""")
			.param("user", userId).param("day", day).query(CandidateRow.class).list();
	}

	/** 이 종이 전에 등장(ENCOUNTER)한 적이 있는지 — 없으면 이번이 "처음 본 종" (결정 D-30). */
	boolean seenBefore(long userId, int speciesId) {
		return db.sql("""
			select exists (select 1 from monster.explore_log where user_id = ? and species_id = ? and result = 'ENCOUNTER')""")
			.params(userId, speciesId).query(Boolean.class).single();
	}

	long insertExplore(long userId, LocalDate day, int seq, UUID key, String result, Integer speciesId, int goldAwarded) {
		return db.sql("""
			insert into monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id, gold_awarded)
			values (?, ?, ?, ?, ?, ?, ?) returning id""")
			.params(userId, day, seq, key, result, speciesId, goldAwarded).query(Long.class).single();
	}

	/** 탐색 한 건 + 나온 종 (꽝이면 종 칸이 null). */
	record EncounterRow(long id, LocalDate quotaDate, String result, String outcome, Integer speciesId, String code,
			String name, String categoryCode, Integer rarity) {
	}

	private static final String ENCOUNTER = """
		select e.id, e.quota_date, e.result, e.outcome, s.id as species_id, s.code, s.name, s.category_code, s.rarity
		  from monster.explore_log e left join monster.monster_species s on s.id = e.species_id
		""";

	/** 오늘의 처리 전 등장 ({@code GET /explores/pending}). */
	Optional<EncounterRow> pending(long userId, LocalDate today) {
		return db.sql(ENCOUNTER + " where e.user_id = ? and e.quota_date = ? and e.result = 'ENCOUNTER' and e.outcome is null")
			.params(userId, today).query(EncounterRow.class).optional();
	}

	/** 내 탐색 한 건을 잠근다 (포획). 남의 것이면 비어 있다 (호출하는 쪽이 404). */
	Optional<EncounterRow> lockExplore(long userId, long exploreId) {
		return db.sql(ENCOUNTER + " where e.user_id = ? and e.id = ? for update of e")
			.params(userId, exploreId).query(EncounterRow.class).optional();
	}

	/** 등장의 결과를 한 번 기록한다 (DB 트리거가 다시 바꾸는 걸 막는다). */
	void resolveCapture(long exploreId, String outcome, long consumptionId, Long userMonsterId) {
		db.sql("""
			update monster.explore_log set outcome = ?, consumption_id = ?, user_monster_id = ?, resolved_at = now()
			 where id = ?""")
			.params(outcome, consumptionId, userMonsterId, exploreId).update();
	}

	int fieldCount(long userId) {
		return db.sql("select count(*) from monster.user_monster where user_id = ? and location = 'FIELD'")
			.param(userId).query(Integer.class).single();
	}

	/** 가진 종 수 (도감 수). */
	int dexCount(long userId) {
		return db.sql("select dex_count from monster.monster_user where user_id = ?").param(userId).query(Integer.class)
			.single();
	}

	// ---------- 성장 · 교감 (3-5) ----------
	/** 몬스터 사용자 잠금 (잠금 순서 monster_user → inventory → wallet). 같은 사람의 성장 요청이 한 줄로 선다. */
	void lockMonsterUser(long userId) {
		db.sql("select user_id from monster.monster_user where user_id = ? for no key update").param(userId)
			.query(Long.class).optional();
	}

	void updateGrowth(long userMonsterId, int expTotal, int level) {
		db.sql("""
			update monster.user_monster set exp_total = ?, level = ?, version = version + 1, updated_at = now() where id = ?""")
			.params(expTotal, level, userMonsterId).update();
	}

	void insertGrowthLog(long userMonsterId, long consumptionId, int expGained, int expTotalAfter, int levelBefore,
			int levelAfter) {
		db.sql("""
			insert into monster.monster_growth_log
			  (user_monster_id, consumption_id, exp_gained, exp_total_after, level_before, level_after)
			values (?, ?, ?, ?, ?, ?)""")
			.params(userMonsterId, consumptionId, expGained, expTotalAfter, levelBefore, levelAfter).update();
	}

	/** 오늘의 교감 1행. 이미 했으면 false — (몬스터, 날짜, 행동)이 기본 키라 동시에 와도 하나만 들어간다. */
	boolean insertAffectionAction(long userMonsterId, LocalDate day, String action, int gain) {
		return db.sql("""
			insert into monster.affection_action (user_monster_id, action_date, action_type, gain) values (?, ?, ?, ?)
			on conflict do nothing""")
			.params(userMonsterId, day, action, gain).update() == 1;
	}

	void updateAffection(long userMonsterId, int affection) {
		db.sql("update monster.user_monster set affection = ?, version = version + 1, updated_at = now() where id = ?")
			.params(affection, userMonsterId).update();
	}

	void updateLocation(long userMonsterId, String location) {
		db.sql("update monster.user_monster set location = ?, version = version + 1, updated_at = now() where id = ?")
			.params(location, userMonsterId).update();
	}

	/** 대화 상대는 사용자당 1마리 (uq_user_partner) — 옛 상대를 먼저 내려야 새 상대를 올릴 수 있다. */
	void clearPartner(long userId) {
		db.sql("update monster.user_monster set is_partner = false, updated_at = now() where user_id = ? and is_partner")
			.param(userId).update();
	}

	void markPartner(long userMonsterId) {
		db.sql("update monster.user_monster set is_partner = true, updated_at = now() where id = ?").param(userMonsterId)
			.update();
	}

	/** 종의 호감도 단계별 대사 (시드 순서). */
	List<String> lines(int speciesId, String affectionTier) {
		return db.sql("select line_text from monster.species_line where species_id = ? and affection_tier = ? order by id")
			.params(speciesId, affectionTier).query(String.class).list();
	}
}
