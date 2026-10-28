package kr.habitmonster.monster;

import java.time.LocalDate;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.monster.MonsterRepository.CandidateRow;
import kr.habitmonster.monster.MonsterRepository.ClosedRow;
import kr.habitmonster.monster.MonsterRepository.DexRow;
import kr.habitmonster.monster.MonsterRepository.EncounterRow;
import kr.habitmonster.monster.MonsterRepository.MonsterRow;
import kr.habitmonster.shop.ShopService;
import kr.habitmonster.shop.ShopService.Consumed;
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
	private final Dice dice;
	private final ShopService shop;

	MonsterService(MonsterRepository monsters, BalanceConfig config, BusinessDates dates, Dice dice, ShopService shop) {
		this.monsters = monsters;
		this.config = config;
		this.dates = dates;
		this.dice = dice;
		this.shop = shop;
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

	// ---------- 탐색 · 포획 (3-4) ----------
	/** 등장한 종 ({@code imageUrl} 대신 {@code imageKey} — 결정 D1). 가진 종(DUPLICATE)이면 던질 일이 없어 {@code captureRate}가 null. */
	public record SpeciesView(int speciesId, String name, String imageKey, String categoryCode, int rarity,
			Double captureRate) {
	}

	/**
	 * 탐색 1회 결과. {@code goldAwarded}는 가진 종이 나왔을 때 줄 골드 — 실제 지급은 조율 서비스가 지갑으로 한다.
	 * {@code skippedExploreId}는 같은 날 넘긴 등장만 (지난 날 등장은 EXPIRED로 닫지만 오늘 화면엔 없던 것이라 안 담는다).
	 */
	public record Explored(long exploreId, String result, SpeciesView species, boolean newlySeen, int goldAwarded,
			Long skippedExploreId, int exploreRemaining) {
	}

	/** 포획 결과의 새 몬스터. */
	public record CapturedMonster(long userMonsterId, String name, String imageKey, String location) {
	}

	/** 볼을 던질 수 있는 등장 (잠근 상태). */
	public record Target(long exploreId, int speciesId, int rarity) {
	}

	/** {@code dexAdded}: 이번에 가진 종이 늘었는지 (해금권 판단). */
	public record Caught(String outcome, CapturedMonster monster, int dexCount, boolean dexAdded) {
	}

	/**
	 * 탐색 1회 (API 명세 v5 {@code POST /explores}). 부르는 쪽이 사용자 잠금을 먼저 잡는다.
	 * <ol>
	 * <li>기회 1회 사용 — 체크인 전 409 {@code CHECKIN_REQUIRED}, 다 썼으면 422 {@code NO_EXPLORE_LEFT}</li>
	 * <li>남아 있던 등장을 닫는다 (같은 날 SKIPPED · 지난 날 EXPIRED)</li>
	 * <li>꽝 {@code explore_miss_rate} → MISS</li>
	 * <li>후보 = 오늘 탐색 카테고리 종 중 출현 레벨 ≤ 그 카테고리 레벨, 가중치 = 희귀도 가중치 × (안 가진 종이면 배수)</li>
	 * <li>가진 종 → DUPLICATE(골드), 안 가진 종 → ENCOUNTER(볼을 던질 수 있음)</li>
	 * </ol>
	 * 후보가 하나도 없으면 꽝으로 둔다 (카테고리마다 출현 Lv.1 스타터가 있어 지금 시드로는 생기지 않음 — 결정 D-45).
	 *
	 * @param levels 연 카테고리 → 레벨 (습관 모듈)
	 */
	@Transactional
	public Explored explore(long userId, LocalDate today, UUID key, Map<String, Integer> levels) {
		int seq = monsters.useExplore(userId, today).orElseThrow(() -> new ApiException(
				monsters.quota(userId, today).isPresent() ? ErrorCode.NO_EXPLORE_LEFT : ErrorCode.CHECKIN_REQUIRED));
		int remaining = monsters.quota(userId, today).map(q -> q.baseCount() - q.usedCount()).orElse(0);
		Long skipped = monsters.closePending(userId, today).filter(c -> c.outcome().equals("SKIPPED"))
			.map(ClosedRow::id).orElse(null);

		CandidateRow picked = dice.roll() < config.exploreMissRate() ? null : pick(monsters.candidates(userId, today).stream()
			.filter(c -> c.unlockLevel() <= levels.getOrDefault(c.categoryCode(), 0)).toList());
		if (picked == null) {
			long id = monsters.insertExplore(userId, today, seq, key, "MISS", null, 0);
			return new Explored(id, "MISS", null, false, 0, skipped, remaining);
		}
		if (picked.owned()) {
			int gold = config.duplicateGold();
			long id = monsters.insertExplore(userId, today, seq, key, "DUPLICATE", picked.id(), gold);
			return new Explored(id, "DUPLICATE", view(picked.id(), picked.name(), picked.code(), picked.categoryCode(),
					picked.rarity(), false), false, gold, skipped, remaining);
		}
		boolean newlySeen = !monsters.seenBefore(userId, picked.id());
		long id = monsters.insertExplore(userId, today, seq, key, "ENCOUNTER", picked.id(), 0);
		return new Explored(id, "ENCOUNTER", view(picked.id(), picked.name(), picked.code(), picked.categoryCode(),
				picked.rarity(), true), newlySeen, 0, skipped, remaining);
	}

	/** 가중치 뽑기: 종 번호 순서로 가중치를 쌓고 주사위 × 합이 들어간 칸. 후보가 없으면 null. */
	private CandidateRow pick(List<CandidateRow> candidates) {
		Map<Integer, Integer> rarityWeight = config.exploreRarityWeight();
		double unowned = config.exploreUnownedMultiplier();
		double[] weights = candidates.stream()
			.mapToDouble(c -> rarityWeight.getOrDefault(c.rarity(), 0) * (c.owned() ? 1 : unowned)).toArray();
		double total = Arrays.stream(weights).sum();
		if (total <= 0) {
			return null;
		}
		double r = dice.roll() * total;
		for (int i = 0; i < weights.length; i++) {
			r -= weights[i];
			if (r < 0) {
				return candidates.get(i);
			}
		}
		return candidates.getLast(); // 소수 오차로 끝까지 왔을 때
	}

	private SpeciesView view(int speciesId, String name, String code, String categoryCode, int rarity, boolean catchable) {
		return new SpeciesView(speciesId, name, code, categoryCode, rarity,
				catchable ? config.captureRate().get(rarity) : null);
	}

	/** 오늘의 처리 전 등장 ({@code GET /explores/pending}) — 이미 도감에 올라간 등장이라 {@code newlySeen}은 false. */
	@Transactional(readOnly = true)
	public Optional<Explored> pending(long userId) {
		LocalDate today = dates.today();
		return monsters.pending(userId, today).map(e -> new Explored(e.id(), e.result(),
				view(e.speciesId(), e.name(), e.code(), e.categoryCode(), e.rarity(), true), false, 0, null,
				exploreQuota(userId).remaining()));
	}

	/**
	 * 볼을 던질 등장을 잠근다. 남의 탐색이면 404(결정 C3 — 명세는 403), 등장이 아니거나 · 이미 끝났거나 ·
	 * 지난 날 등장이면 409 {@code ENCOUNTER_CLOSED}. 같은 등장에 두 번 던지면 두 번째가 여기서 409.
	 */
	@Transactional
	public Target captureTarget(long userId, long exploreId, LocalDate today) {
		EncounterRow e = monsters.lockExplore(userId, exploreId).orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND));
		if (!e.result().equals("ENCOUNTER") || e.outcome() != null || !e.quotaDate().equals(today)) {
			throw new ApiException(ErrorCode.ENCOUNTER_CLOSED);
		}
		return new Target(e.id(), e.speciesId(), e.rarity());
	}

	/**
	 * 볼을 던진 뒤 (볼은 이미 썼다): 희귀도별 포획률 {@code capture_rate}로 잡으면 몬스터를 만들고(필드가 꽉 찼으면 가방)
	 * 도감에 등록, 못 잡으면 도망. 결과는 탐색 기록에 한 번만 남는다.
	 */
	@Transactional
	public Caught capture(long userId, Target t, long consumptionId) {
		if (dice.roll() >= config.captureRate().get(t.rarity())) {
			monsters.resolveCapture(t.exploreId(), "ESCAPED", consumptionId, null);
			return new Caught("ESCAPED", null, monsters.dexCount(userId), false);
		}
		String location = monsters.fieldCount(userId) < config.fieldMax() ? "FIELD" : "BAG";
		long id = monsters.insertMonster(userId, t.speciesId(), 0, location, false, "EXPLORE");
		boolean added = monsters.addDexEntry(userId, t.speciesId());
		monsters.resolveCapture(t.exploreId(), "CAPTURED", consumptionId, id);
		MonsterRow m = monsters.monster(userId, id).orElseThrow();
		return new Caught("CAPTURED", new CapturedMonster(id, m.name(), m.code(), location), monsters.dexCount(userId), added);
	}

	// ---------- 성장 · 교감 (3-5) ----------
	public record FeedRequest(String itemCode) {
	}

	/** {@code POST /monsters/{id}/feed} 응답 (명세 그대로). */
	public record Fed(int expGained, int levelBefore, int levelAfter, int stageBefore, int stageAfter, boolean evolved,
			int remainingQuantity) {
	}

	public record AffectionRequest(String action) {
	}

	/** {@code POST /monsters/{id}/affection} 응답. 호감도가 최대면 {@code gain}은 0. */
	public record AffectionResult(int gain, int affection, String affectionTier) {
	}

	public record Line(String affectionTier, String line) {
	}

	public record LocationRequest(String location) {
	}

	public record Moved(long userMonsterId, String location, int fieldCount) {
	}

	public record PartnerRequest(Long userMonsterId) {
	}

	public record PartnerChanged(long partnerMonsterId) {
	}

	/** 내 몬스터. 없거나 남의 것이면 404 (결정 C3). */
	private MonsterRow mine(long userId, long userMonsterId) {
		return monsters.monster(userId, userMonsterId).orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND));
	}

	/**
	 * 물약 먹이기 (명세 이름은 "간식 주기"). 몬스터 사용자 잠금 → 내 몬스터 · 최대 레벨 확인 → 물약 1개(상점 모듈, {@code FEED:<키>})
	 * → 경험치 · 레벨(레벨당 {@code monster_exp_per_level}, 최대 {@code monster_max_level}) · 진화 단계 → 성장 기록.
	 * 레벨은 내려가지 않는다 (DB 원칙 6).
	 *
	 * @throws ApiException 400 물약이 아닌 코드, 404 남의 몬스터, 422 {@code MAX_LEVEL} · {@code NO_ITEM}
	 */
	@Transactional
	public Fed feed(long userId, long userMonsterId, UUID key, FeedRequest req) {
		monsters.lockMonsterUser(userId);
		MonsterRow m = mine(userId, userMonsterId);
		int exp = Optional.ofNullable(req.itemCode()).flatMap(shop::potionExp)
			.orElseThrow(() -> new ApiException(ErrorCode.INVALID_REQUEST));
		if (m.level() >= config.monsterMaxLevel()) {
			throw new ApiException(ErrorCode.MAX_LEVEL);
		}
		Consumed potion = shop.usePotion(userId, req.itemCode(), "FEED:" + key);
		int total = m.expTotal() + exp;
		int level = Math.max(m.level(), Math.min(config.monsterMaxLevel(), total / config.monsterExpPerLevel() + 1));
		monsters.updateGrowth(m.userMonsterId(), total, level);
		monsters.insertGrowthLog(m.userMonsterId(), potion.consumptionId(), exp, total, m.level(), level);
		int stageBefore = config.stageOf(m.level());
		int stageAfter = config.stageOf(level);
		return new Fed(exp, m.level(), level, stageBefore, stageAfter, stageAfter > stageBefore, potion.remaining());
	}

	/**
	 * 쓰다듬기(PET) · 놀아주기(PLAY) — 몬스터마다 하루 1번씩. 오른 만큼(최대 {@code affection_max})을 기록한다.
	 * 필드 끌기(앱의 D-20)는 명세 · DB에 없어 받지 않는다 (결정 D-46).
	 *
	 * @throws ApiException 400 다른 행동, 404 남의 몬스터, 409 {@code ALREADY_DONE_TODAY}
	 */
	@Transactional
	public AffectionResult affection(long userId, long userMonsterId, AffectionRequest req) {
		String action = req.action();
		if (!"PET".equals(action) && !"PLAY".equals(action)) {
			throw new ApiException(ErrorCode.INVALID_REQUEST);
		}
		monsters.lockMonsterUser(userId);
		MonsterRow m = mine(userId, userMonsterId);
		int step = action.equals("PET") ? config.affectionPetGain() : config.affectionPlayGain();
		int gain = Math.max(0, Math.min(step, config.affectionMax() - m.affection()));
		if (!monsters.insertAffectionAction(m.userMonsterId(), dates.today(), action, gain)) {
			throw new ApiException(ErrorCode.ALREADY_DONE_TODAY);
		}
		int affection = m.affection() + gain;
		if (gain > 0) {
			monsters.updateAffection(m.userMonsterId(), affection);
		}
		return new AffectionResult(gain, affection, config.affectionTier(affection));
	}

	/** 말 걸기: 호감도 단계에 맞는 대사 중 하나 (랜덤은 {@link Dice}). */
	@Transactional(readOnly = true)
	public Line line(long userId, long userMonsterId) {
		MonsterRow m = mine(userId, userMonsterId);
		String tier = config.affectionTier(m.affection());
		List<String> lines = monsters.lines(m.speciesId(), tier);
		String line = lines.isEmpty() ? "..." : lines.get(Math.min(lines.size() - 1, (int) (dice.roll() * lines.size())));
		return new Line(tier, line);
	}

	/**
	 * 가방에 넣기 · 꺼내기. 필드는 {@code field_min} ~ {@code field_max}마리 (대화 상대도 가방에 갈 수 있다).
	 * 이미 그 자리면 그대로 돌려준다.
	 *
	 * @throws ApiException 400 FIELD · BAG 밖, 404 남의 몬스터, 422 {@code FIELD_LIMIT}
	 */
	@Transactional
	public Moved move(long userId, long userMonsterId, LocationRequest req) {
		String to = req.location();
		if (!"FIELD".equals(to) && !"BAG".equals(to)) {
			throw new ApiException(ErrorCode.INVALID_REQUEST);
		}
		monsters.lockMonsterUser(userId);
		MonsterRow m = mine(userId, userMonsterId);
		int field = monsters.fieldCount(userId);
		if (m.location().equals(to)) {
			return new Moved(m.userMonsterId(), to, field);
		}
		boolean full = to.equals("FIELD") && field >= config.fieldMax();
		boolean last = to.equals("BAG") && field <= config.fieldMin();
		if (full || last) {
			throw new ApiException(ErrorCode.FIELD_LIMIT);
		}
		monsters.updateLocation(m.userMonsterId(), to);
		return new Moved(m.userMonsterId(), to, to.equals("FIELD") ? field + 1 : field - 1);
	}

	/** 대화 상대 바꾸기 (가방에 있어도 된다). 옛 상대를 내린 뒤 새 상대를 올린다 — DB가 "1마리"를 강제해서 이 순서. */
	@Transactional
	public PartnerChanged changePartner(long userId, PartnerRequest req) {
		if (req.userMonsterId() == null) {
			throw new ApiException(ErrorCode.INVALID_REQUEST);
		}
		monsters.lockMonsterUser(userId);
		MonsterRow m = mine(userId, req.userMonsterId());
		if (!m.isPartner()) {
			monsters.clearPartner(userId);
			monsters.markPartner(m.userMonsterId());
		}
		return new PartnerChanged(m.userMonsterId());
	}

	// ---------- 도감 (4-3) ----------
	/**
	 * 도감의 종 하나. {@code status} = OWNED(가진 종) · SEEN(탐색에서 만난 종) · UNKNOWN(아직 모름).
	 * {@code level}은 가진 종일 때 내 몬스터 중 가장 높은 레벨, {@code stage}는 그 레벨의 진화 단계.
	 */
	public record DexSpecies(int speciesId, String code, String name, String categoryCode, int rarity, int unlockLevel,
			int dexNo, String description, String status, Integer level, Integer stage) {
	}

	/** 도감 (도감 번호 순서). {@code categoryCode}가 null이면 전체. */
	@Transactional(readOnly = true)
	public List<DexSpecies> dex(long userId, String categoryCode) {
		return monsters.dex(userId, categoryCode).stream().map(this::dexView).toList();
	}

	private DexSpecies dexView(DexRow r) {
		String status = r.owned() ? "OWNED" : r.seen() ? "SEEN" : "UNKNOWN";
		Integer level = r.owned() ? r.level() : null;
		return new DexSpecies(r.id(), r.code(), r.name(), r.categoryCode(), r.rarity(), r.unlockLevel(), r.dexNo(),
				r.description(), status, level, level == null ? null : config.stageOf(level));
	}

	/** 필드에 있는 몬스터 수 (시작 몬스터를 필드에 둘지 정할 때). */
	@Transactional(readOnly = true)
	public int fieldCount(long userId) {
		return monsters.fieldCount(userId);
	}

	/** 가진 종 수 (도감 수). */
	@Transactional(readOnly = true)
	public int dexCount(long userId) {
		return monsters.dexCount(userId);
	}
}
