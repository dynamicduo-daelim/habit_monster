package kr.habitmonster.monster;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.monster.MonsterRepository.MonsterRow;
import kr.habitmonster.monster.MonsterRepository.SpeciesRow;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 몬스터 모듈 — 종 마스터, 사용자의 몬스터 · 도감.
 * 그림은 URL 대신 {@code imageKey}(= 종 코드, 앱의 {@code assets/images/monsters/{key}.png})로 보낸다 (결정 D1).
 */
@Service
public class MonsterService {

	/** 카테고리의 스타터 종 ({@code GET /categories}의 {@code starter}). */
	public record Starter(int speciesId, String name, String imageKey) {
	}

	/** 지급한 스타터 = {@code POST /onboarding} 응답의 {@code starters} 한 줄. */
	public record GrantedStarter(long userMonsterId, int speciesId, String categoryCode, String name, String imageKey,
			String location) {
	}

	/** {@code GET /monsters} 한 줄. 대화 상대는 가방에 있어도 된다 (필드 표시와 별개). */
	public record MonsterView(long userMonsterId, int speciesId, String name, String categoryCode, int level, int stage,
			String imageKey, int displayHeight, String facing, String location, boolean isPartner) {
	}

	public record TodayActions(boolean pet, boolean play) {
	}

	/**
	 * {@code GET /monsters/{id}} (팝업). {@code expInLevel}은 지금 레벨에서 모은 경험치, {@code expRequired}는 그 레벨에
	 * 필요한 총량 (명세의 {@code expToNextLevel} — 결정 B2). 최대 레벨이면 {@code expRequired} · 최종 진화면
	 * {@code nextEvolutionLevel}이 null.
	 */
	public record MonsterDetail(long userMonsterId, int speciesId, String name, String imageKey, String categoryCode,
			int stage, int rarity, int level, int expInLevel, Integer expRequired, Integer nextEvolutionLevel, int affection,
			int affectionMax, String affectionTier, TodayActions todayActions, String location, boolean isPartner) {
	}

	/** 오늘 탐색 기회. 체크인 전이면 0 / 0. */
	public record ExploreQuota(int remaining, int total) {
	}

	private final MonsterRepository monsters;
	private final BalanceConfig config;
	private final BusinessDates dates;

	MonsterService(MonsterRepository monsters, BalanceConfig config, BusinessDates dates) {
		this.monsters = monsters;
		this.config = config;
		this.dates = dates;
	}

	// ---------- 조회 (3-2) ----------
	/** @param location FIELD · BAG, null이면 전체 */
	@Transactional(readOnly = true)
	public List<MonsterView> monsters(long userId, String location) {
		return monsters.monsters(userId, location).stream()
			.map(m -> new MonsterView(m.userMonsterId(), m.speciesId(), m.name(), m.categoryCode(), m.level(),
					config.stageOf(m.level()), m.code(), m.displayHeight(), m.facing(), m.location(), m.isPartner()))
			.toList();
	}

	/** 내 몬스터 상세. 없거나 남의 몬스터면 404 — 남의 것이 있는지조차 알려 주지 않는다 (결정 C3). */
	@Transactional(readOnly = true)
	public MonsterDetail monster(long userId, long userMonsterId) {
		MonsterRow m = monsters.monster(userId, userMonsterId).orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND));
		int perLevel = config.monsterExpPerLevel();
		boolean max = m.level() >= config.monsterMaxLevel();
		int expInLevel = max ? 0 : Math.max(0, m.expTotal() - (m.level() - 1) * perLevel);
		List<String> actions = monsters.actionsOn(m.userMonsterId(), dates.today());
		return new MonsterDetail(m.userMonsterId(), m.speciesId(), m.name(), m.code(), m.categoryCode(),
				config.stageOf(m.level()), m.rarity(), m.level(), expInLevel, max ? null : perLevel,
				config.nextEvolutionLevel(m.level()), m.affection(), config.affectionMax(), config.affectionTier(m.affection()),
				new TodayActions(actions.contains("PET"), actions.contains("PLAY")), m.location(), m.isPartner());
	}

	@Transactional(readOnly = true)
	public ExploreQuota exploreQuota(long userId) {
		return monsters.quota(userId, dates.today())
			.map(q -> new ExploreQuota(q.baseCount() - q.usedCount(), q.baseCount()))
			.orElse(new ExploreQuota(0, 0));
	}

	// ---------- 체크인 (3-3) ----------
	/** 체크인 화면의 대화 상대 ({@code imageUrl} 대신 {@code imageKey} — 결정 D1). */
	public record Partner(long userMonsterId, String name, String imageKey, String affectionTier) {
	}

	/** 레벨업으로 탐색에 새로 나오게 된 종. */
	public record UnlockedSpecies(int speciesId, String categoryCode) {
	}

	@Transactional(readOnly = true)
	public Optional<Partner> partner(long userId) {
		return monsters.partner(userId)
			.map(m -> new Partner(m.userMonsterId(), m.name(), m.code(), config.affectionTier(m.affection())));
	}

	/**
	 * 체크인 첫 제출로 그날 탐색 기회를 만든다. 탐색 후보 카테고리는 **연 카테고리 전부** (결정 B4).
	 * 같은 체크인으로 두 번 만들 수 없다 (DB {@code source_checkin_id} UNIQUE).
	 */
	@Transactional
	public void openExploreQuota(long userId, LocalDate day, int baseCount, long checkinId, List<String> categories) {
		monsters.insertQuota(userId, day, baseCount, checkinId);
		categories.forEach(code -> monsters.insertQuotaCategory(userId, day, code));
	}

	/** 카테고리 레벨이 {@code from} → {@code to}로 올라 새로 탐색 후보가 된 종 (출현 레벨 기준). */
	@Transactional(readOnly = true)
	public List<UnlockedSpecies> unlockedBetween(String categoryCode, int from, int to) {
		if (to <= from) {
			return List.of();
		}
		return monsters.speciesUnlockedBetween(categoryCode, from, to).stream()
			.map(id -> new UnlockedSpecies(id, categoryCode)).toList();
	}

	/** 카테고리 코드 → 스타터 종. */
	@Transactional(readOnly = true)
	public Map<String, Starter> starters() {
		return monsters.starterSpecies().stream().collect(Collectors.toMap(SpeciesRow::categoryCode,
				s -> new Starter(s.id(), s.name(), s.code())));
	}

	/** 온보딩: 몬스터 프로필(사용자 잠금 · 도감 수 행)을 만든다. */
	@Transactional
	public void startProfile(long userId) {
		monsters.createMonsterUser(userId);
	}

	/**
	 * 카테고리를 연 사용자에게 그 카테고리의 스타터를 준다 (카테고리마다 1마리, DB v1.5).
	 * 시작 호감도는 설정값({@code starter_affection}), 필드에 자리가 있으면 필드, 없으면 가방.
	 * 카테고리를 여는 쪽(습관 모듈)이 같은 트랜잭션에서 먼저 열어 둬야 한다 (외래키).
	 *
	 * @param fieldCount 지금 필드에 있는 마리 수
	 * @param partner    대화 상대로 정할지
	 */
	@Transactional
	public GrantedStarter grantStarter(long userId, String categoryCode, int fieldCount, boolean partner) {
		SpeciesRow s = monsters.starterSpecies().stream().filter(r -> r.categoryCode().equals(categoryCode)).findFirst()
			.orElseThrow(() -> new IllegalStateException("스타터 종 없음: " + categoryCode));
		String location = fieldCount < config.fieldMax() ? "FIELD" : "BAG";
		long id = monsters.insertMonster(userId, s.id(), config.starterAffection(), location, partner, "STARTER");
		monsters.insertStarterGrant(userId, categoryCode, id, s.id());
		monsters.addDexEntry(userId, s.id());
		return new GrantedStarter(id, s.id(), categoryCode, s.name(), s.code(), location);
	}
}
