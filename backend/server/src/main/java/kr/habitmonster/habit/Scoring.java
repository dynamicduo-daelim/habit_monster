package kr.habitmonster.habit;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;
import java.util.TreeSet;

import kr.habitmonster.config.BalanceConfig;

import org.springframework.stereotype.Component;

/**
 * 습관 점수 · 달성률 · 선택지 (API 명세 v5 "4-1. 점수 공식", 결정 B3).
 *
 * <p>체크인 조회의 {@code options}와 제출 검사가 **같은 함수**({@link #options} · {@link #accepts})를 써서 "보여준 선택지 = 받는 값"이 된다.
 * 나중에 선택지 밖 값(직접 입력한 값 그대로)도 받기로 하면 {@link #accepts}만 바꾸면 된다 — 점수 공식은 어떤 값이든 계산한다 (결정 D-42).
 */
@Component
class Scoring {

	/** 측정 방식과 목표 — 점수 · 선택지 계산에 필요한 값만. */
	record Measure(String scoringMode, BigDecimal target, BigDecimal step, BigDecimal maxValue, BigDecimal rangeBelow,
			BigDecimal rangeAbove) {
	}

	/** 선택지 = 목표 × 이 배수들 (결정 B3). 설정 키가 없어 여기 둔다 — 다음 DB 판에 설정으로 옮기자고 제안. */
	private static final List<BigDecimal> OPTION_RATIOS = List.of(new BigDecimal("0.25"), new BigDecimal("0.5"),
			new BigDecimal("0.75"), BigDecimal.ONE, new BigDecimal("1.5"), new BigDecimal("2"));

	/** 범위(수면) 선택지: 범위 아래 · 위로 step 몇 칸씩 더 보여 줄지 (결정 D-42 — 범위 안 · 밖이 둘 다 있게). */
	private static final int RANGE_EXTRA_STEPS = 2;

	private final BalanceConfig config;

	Scoring(BalanceConfig config) {
		this.config = config;
	}

	/**
	 * 점수 0 ~ 25 (반올림 정수). 값 0("못했어")은 0점.
	 * <ul>
	 * <li>TARGET_RATIO: 미달 {@code 20 × 기록/목표}, 달성 20, 초과 {@code 20 + 10 × (기록/목표 − 1)} 최대 25</li>
	 * <li>BINARY: 했으면 20, 못했으면 0</li>
	 * <li>RANGE: {@code 목표 − 아래 ≤ 기록 ≤ 목표 + 위}면 20, 아니면 0</li>
	 * </ul>
	 */
	int score(Measure m, BigDecimal value) {
		if (value == null || value.signum() <= 0) {
			return "BINARY".equals(m.scoringMode()) ? config.scoreBinaryMiss() : 0;
		}
		int hit = config.scoreTargetHit();
		return switch (m.scoringMode()) {
			case "BINARY" -> config.scoreBinaryDone();
			case "RANGE" -> value.compareTo(m.target().subtract(m.rangeBelow())) >= 0
					&& value.compareTo(m.target().add(m.rangeAbove())) <= 0 ? hit : 0;
			default -> {
				double ratio = value.doubleValue() / m.target().doubleValue();
				if (ratio < 1) {
					yield (int) Math.round(hit * ratio);
				}
				yield (int) Math.min(config.scoreMax(), Math.round(hit + config.scoreOverSlope() * (ratio - 1)));
			}
		};
	}

	/** 달성률 % = min(점수 ÷ 20, 1) × 100 (반올림한 점수로). */
	double rate(int score) {
		return Math.min(score / (double) config.scoreTargetHit(), 1.0) * 100;
	}

	/** 전체 성실도: 점수 상위 N개(설정 {@code daily_counted_habits}) 습관의 달성률 평균, 반올림. 습관이 N개보다 적으면 있는 것만. */
	int overallRate(List<Integer> scores) {
		List<Integer> top = scores.stream().sorted((a, b) -> b - a).limit(config.dailyCountedHabits()).toList();
		if (top.isEmpty()) {
			return 0;
		}
		return (int) Math.round(top.stream().mapToDouble(this::rate).sum() / top.size());
	}

	/** 고를 수 있는 값, 오름차순. BINARY는 {@code [1]}(했어). "못했어"(0)는 선택지가 아니라 {@code done:false}. */
	List<BigDecimal> options(Measure m) {
		if ("BINARY".equals(m.scoringMode())) {
			return List.of(BigDecimal.ONE);
		}
		TreeSet<BigDecimal> set = new TreeSet<>();
		if ("RANGE".equals(m.scoringMode())) {
			// 목표에서 step 간격으로 범위 ± 2칸까지: 수면 7h(−1/+1.5, 0.5) → 5 · 5.5 · 6 … 8.5 · 9 · 9.5
			BigDecimal low = m.target().subtract(m.rangeBelow()).subtract(m.step().multiply(BigDecimal.valueOf(RANGE_EXTRA_STEPS)));
			BigDecimal high = m.target().add(m.rangeAbove()).add(m.step().multiply(BigDecimal.valueOf(RANGE_EXTRA_STEPS)));
			for (BigDecimal v = m.target(); v.compareTo(low) >= 0; v = v.subtract(m.step())) {
				addIfAllowed(set, v, m);
			}
			for (BigDecimal v = m.target().add(m.step()); v.compareTo(high) <= 0; v = v.add(m.step())) {
				addIfAllowed(set, v, m);
			}
		}
		else {
			for (BigDecimal ratio : OPTION_RATIOS) {
				BigDecimal raw = m.target().multiply(ratio);
				BigDecimal steps = raw.divide(m.step(), 0, RoundingMode.HALF_UP);
				addIfAllowed(set, steps.multiply(m.step()), m);
			}
		}
		set.add(normalize(m.target())); // 목표값은 항상 (없으면 20점을 못 받는다 — B3)
		return List.copyOf(set);
	}

	/**
	 * 제출 값을 받을지. 지금은 선택지 중 하나여야 한다 (명세 "done:true면 value가 그 습관의 선택지 중 하나").
	 * 직접 입력 값을 그대로 받게 바꿀 땐 여기만 고친다 (예: 0 초과 · {@code max_value} 이하).
	 */
	boolean accepts(Measure m, BigDecimal value) {
		return value != null && options(m).contains(normalize(value));
	}

	private static void addIfAllowed(TreeSet<BigDecimal> set, BigDecimal v, Measure m) {
		if (v.signum() > 0 && (m.maxValue() == null || v.compareTo(m.maxValue()) <= 0)) {
			set.add(normalize(v));
		}
	}

	/** 30.00과 30을 같은 값으로 (TreeSet · contains 비교용). */
	private static BigDecimal normalize(BigDecimal v) {
		BigDecimal s = v.stripTrailingZeros();
		return s.scale() < 0 ? s.setScale(0) : s;
	}
}
