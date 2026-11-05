package kr.habitmonster.config;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * 게임 수치 — {@code config.balance_config}(값은 JSONB)를 서버가 뜰 때 한 번 읽어 메모리에 둔다 (DB 원칙 4: 수치는 코드에 박지 않는다).
 *
 * <p>서버가 쓰는 키는 {@link #REQUIRED}에 모아 두고, 하나라도 없으면 **서버가 뜨지 않는다**. 조용히 기본값을 쓰면
 * DB와 서버의 규칙이 몰래 어긋나기 때문이다. 수치를 바꾸면 DB 값을 고치고 서버를 다시 띄운다.
 * 앱의 {@code frontend/lib/core/constants/economy.dart}는 서버 없을 때(시연)용 사본이고, 기준은 여기다.
 */
@Component
public class BalanceConfig {

	/** 서버가 읽는 키. 시드에 있어도 서버가 쓰지 않는 키는 {@link #NOT_USED_BY_SERVER}. */
	static final Set<String> REQUIRED = Set.of(
		"category_select_min", "category_select_max", "category_exp_base", "category_max_level", "levelup_gold",
		"dex_unlock_thresholds", "max_active_habits", "daily_counted_habits",
		"score_target_hit", "score_max", "score_over_slope", "score_binary_done", "score_binary_miss", "gold_per_score",
		"period_multiplier", "period_days",
		"weekly_goal_slots", "monthly_goal_slots", "weekly_goal_gold", "monthly_goal_gold", "weekly_goal_days", "monthly_goal_days",
		"explore_daily_free", "explore_daily_all_missed", "explore_miss_rate", "explore_rarity_weight",
		"explore_unowned_multiplier", "duplicate_gold", "capture_rate",
		"monster_exp_per_level", "monster_max_level", "evolve_levels", "field_max", "field_min",
		"affection_max", "affection_tiers", "affection_pet_gain", "affection_play_gain", "starter_affection",
		"timer_max_minutes");

	/**
	 * 시드에 있지만 이 클래스가 읽지 않는 키 — 다른 곳에서 정하거나(업무 날짜는 {@code application.properties}),
	 * 아직 만들지 않은 기능(동결 · AI · 키 보관 배치)이다. 새 키가 시드에 생기면 테스트가 둘 중 어디에 둘지 묻는다.
	 */
	static final Set<String> NOT_USED_BY_SERVER = Set.of(
		"service_timezone", "day_boundary_hour", "freeze_after_days", "idempotency_ttl_hours", "idempotency_lock_seconds",
		"chat_message_retention_days", "llm_timeout_ms", "llm_model",
		// 시드 v1.9 (D-62 · D-63) — 서버 구현(타이머 · 근거 · 상한 · 계수 · 해석 보강) 때 REQUIRED로 옮긴다
		"self_report_max_score", "exp_coef_ratio", "exp_coef_range", "exp_coef_binary", "exp_coef_verified",
		"ai_daily_call_limit", "ai_min_confidence");

	private final Map<String, JsonNode> values;

	@Autowired
	public BalanceConfig(JdbcClient db, JsonMapper json) {
		this(load(db, json));
	}

	BalanceConfig(Map<String, JsonNode> values) {
		Set<String> missing = new TreeSet<>(REQUIRED);
		missing.removeAll(values.keySet());
		if (!missing.isEmpty()) {
			throw new IllegalStateException("config.balance_config에 없는 키: " + missing + " — seed.sql을 확인하세요");
		}
		this.values = Map.copyOf(values);
	}

	private static Map<String, JsonNode> load(JdbcClient db, JsonMapper json) {
		Map<String, JsonNode> map = new LinkedHashMap<>();
		db.sql("select key, value::text as value from config.balance_config")
			.query((rs, i) -> map.put(rs.getString("key"), json.readTree(rs.getString("value"))))
			.list();
		return map;
	}

	/** DB에 있는 모든 키 (테스트가 모르는 키를 찾을 때). */
	Set<String> keys() {
		return values.keySet();
	}

	// ---------- 온보딩 · 카테고리 ----------
	public int categorySelectMin() { return integer("category_select_min"); }
	public int categorySelectMax() { return integer("category_select_max"); }
	/** 레벨 N → N+1에 필요한 카테고리 EXP = 이 값 × N. */
	public int categoryExpBase() { return integer("category_exp_base"); }
	public int categoryMaxLevel() { return integer("category_max_level"); }
	public int levelupGold() { return integer("levelup_gold"); }
	/** 가진 종 수가 이 값에 닿을 때마다 카테고리 해금권 1장. */
	public List<Integer> dexUnlockThresholds() { return intList("dex_unlock_thresholds"); }

	// ---------- 습관 · 점수 ----------
	public int maxActiveHabits() { return integer("max_active_habits"); }
	public int dailyCountedHabits() { return integer("daily_counted_habits"); }
	public int scoreTargetHit() { return integer("score_target_hit"); }
	public int scoreMax() { return integer("score_max"); }
	public int scoreOverSlope() { return integer("score_over_slope"); }
	public int scoreBinaryDone() { return integer("score_binary_done"); }
	public int scoreBinaryMiss() { return integer("score_binary_miss"); }
	public int goldPerScore() { return integer("gold_per_score"); }
	/** 기간 코드(D7 · D30 · D100) → 배수. */
	public Map<String, Double> periodMultiplier() { return doubleMap("period_multiplier"); }
	/** 기간 코드 → 채워야 할 날 수. */
	public Map<String, Integer> periodDays() { return intMap("period_days"); }
	/** 습관 타이머 한 번 최대 분 — 일시정지를 뺀 경과 기준 (명세 v6 9장). */
	public int timerMaxMinutes() { return integer("timer_max_minutes"); }

	// ---------- 목표 ----------
	public int weeklyGoalSlots() { return integer("weekly_goal_slots"); }
	public int monthlyGoalSlots() { return integer("monthly_goal_slots"); }
	public int weeklyGoalGold() { return integer("weekly_goal_gold"); }
	public int monthlyGoalGold() { return integer("monthly_goal_gold"); }
	/** 목표 기간 — 등록한 날부터 센 일수 (명세 v5 보충 10-28). */
	public int weeklyGoalDays() { return integer("weekly_goal_days"); }
	public int monthlyGoalDays() { return integer("monthly_goal_days"); }

	// ---------- 탐색 · 포획 ----------
	public int exploreDailyFree() { return integer("explore_daily_free"); }
	public int exploreDailyAllMissed() { return integer("explore_daily_all_missed"); }
	public double exploreMissRate() { return values.get("explore_miss_rate").asDouble(); }
	/** 희귀도(1 · 2 · 3) → 등장 가중치. */
	public Map<Integer, Integer> exploreRarityWeight() { return byRarity("explore_rarity_weight", JsonNode::asInt); }
	public double exploreUnownedMultiplier() { return values.get("explore_unowned_multiplier").asDouble(); }
	public int duplicateGold() { return integer("duplicate_gold"); }
	/** 희귀도 → 포획 확률. */
	public Map<Integer, Double> captureRate() { return byRarity("capture_rate", JsonNode::asDouble); }

	// ---------- 몬스터 ----------
	public int monsterExpPerLevel() { return integer("monster_exp_per_level"); }
	public int monsterMaxLevel() { return integer("monster_max_level"); }
	/** 1차 · 최종 진화 레벨 (오름차순). */
	public List<Integer> evolveLevels() { return intList("evolve_levels"); }
	public int fieldMax() { return integer("field_max"); }
	public int fieldMin() { return integer("field_min"); }
	public int affectionMax() { return integer("affection_max"); }
	public int affectionPetGain() { return integer("affection_pet_gain"); }
	public int affectionPlayGain() { return integer("affection_play_gain"); }
	public int starterAffection() { return integer("starter_affection"); }

	/** 진화 단계: 0 기본 · 1 1차 · 2 최종 = 넘은 진화 레벨 수. */
	public int stageOf(int level) {
		return (int) evolveLevels().stream().filter(l -> level >= l).count();
	}

	/** 다음 진화 레벨. 최종 단계면 null. */
	public Integer nextEvolutionLevel(int level) {
		return evolveLevels().stream().filter(l -> l > level).findFirst().orElse(null);
	}

	/** 호감도 단계 LOW · MID · HIGH ({@code affection_tiers}의 하한). */
	public String affectionTier(int affection) {
		Map<String, Integer> tiers = intMap("affection_tiers");
		if (affection >= tiers.get("HIGH")) {
			return "HIGH";
		}
		return affection >= tiers.get("MID") ? "MID" : "LOW";
	}

	// ---------- JSON 읽기 ----------
	private int integer(String key) {
		return values.get(key).asInt();
	}

	private List<Integer> intList(String key) {
		List<Integer> list = new ArrayList<>();
		values.get(key).forEach(n -> list.add(n.asInt()));
		return List.copyOf(list);
	}

	private Map<String, Integer> intMap(String key) {
		Map<String, Integer> map = new TreeMap<>();
		values.get(key).properties().forEach(e -> map.put(e.getKey(), e.getValue().asInt()));
		return map;
	}

	private Map<String, Double> doubleMap(String key) {
		Map<String, Double> map = new TreeMap<>();
		values.get(key).properties().forEach(e -> map.put(e.getKey(), e.getValue().asDouble()));
		return map;
	}

	private <T> Map<Integer, T> byRarity(String key, java.util.function.Function<JsonNode, T> read) {
		Map<Integer, T> map = new TreeMap<>();
		values.get(key).properties().forEach(e -> map.put(Integer.valueOf(e.getKey()), read.apply(e.getValue())));
		return map;
	}
}
