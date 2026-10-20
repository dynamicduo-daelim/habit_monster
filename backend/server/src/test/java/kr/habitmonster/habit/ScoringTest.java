package kr.habitmonster.habit;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.List;

import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

/** 점수 공식 · 선택지 (API 명세 v5 4-1, 결정 B3 · D-42). 수치는 시드 설정값 (20 · 25 · 10). */
class ScoringTest extends PostgresTest {

	@Autowired
	Scoring scoring;

	static Scoring.Measure ratio(String target, String step, String max) {
		return new Scoring.Measure("TARGET_RATIO", d(target), d(step), d(max), null, null);
	}

	/** 수면 시간 (시드 16번): 목표 7h · 0.5 단위 · 범위 −1 / +1.5 → 6 ~ 8.5h면 20점. */
	static final Scoring.Measure SLEEP = new Scoring.Measure("RANGE", d("7"), d("0.5"), d("16"), d("1"), d("1.5"));

	static final Scoring.Measure OX = new Scoring.Measure("BINARY", BigDecimal.ONE, BigDecimal.ONE, BigDecimal.ONE, null, null);

	static BigDecimal d(String v) {
		return new BigDecimal(v);
	}

	static List<BigDecimal> ds(String... vs) {
		return java.util.Arrays.stream(vs).map(BigDecimal::new).toList();
	}

	@Test
	void 목표_비율_점수() {
		Scoring.Measure walk = ratio("30", "5", "600");
		assertThat(scoring.score(walk, d("20"))).isEqualTo(13); // 13.3 반올림
		assertThat(scoring.score(walk, d("30"))).isEqualTo(20);
		assertThat(scoring.score(walk, d("40"))).isEqualTo(23); // 20 + 10 × 1/3
		assertThat(scoring.score(walk, d("45"))).isEqualTo(25);
		assertThat(scoring.score(walk, d("90"))).isEqualTo(25); // 최대 25
		assertThat(scoring.score(walk, BigDecimal.ZERO)).isZero();
	}

	@Test
	void OX_점수() {
		assertThat(scoring.score(OX, BigDecimal.ONE)).isEqualTo(20);
		assertThat(scoring.score(OX, BigDecimal.ZERO)).isZero();
	}

	@Test
	void 수면_범위_경계() {
		assertThat(scoring.score(SLEEP, d("5.5"))).isZero();
		assertThat(scoring.score(SLEEP, d("6"))).isEqualTo(20); // 목표 − 1 (포함)
		assertThat(scoring.score(SLEEP, d("7"))).isEqualTo(20);
		assertThat(scoring.score(SLEEP, d("8.5"))).isEqualTo(20); // 목표 + 1.5 (포함)
		assertThat(scoring.score(SLEEP, d("9"))).isZero();
	}

	@Test
	void 달성률과_전체_성실도() {
		assertThat(scoring.rate(13)).isEqualTo(65.0);
		assertThat(scoring.rate(25)).isEqualTo(100.0);
		assertThat(scoring.overallRate(List.of(13, 0, 20, 20))).isEqualTo(88); // (65 + 100 + 100) ÷ 3
		assertThat(scoring.overallRate(List.of(13))).isEqualTo(65); // 3개보다 적으면 있는 것만
	}

	@Test
	void 선택지() {
		// 목표 × {0.25, 0.5, 0.75, 1, 1.5, 2}를 step으로 반올림
		assertThat(scoring.options(ratio("30", "5", "600"))).isEqualTo(ds("10", "15", "25", "30", "45", "60"));
		// 물 2L (0.5 단위): 0.5 · 1 · 1.5 · 2 · 3 · 4
		assertThat(scoring.options(ratio("2", "0.5", "5"))).isEqualTo(ds("0.5", "1", "1.5", "2", "3", "4"));
		// 자가진단 4점 (최대 5): 6 · 8은 빠짐
		assertThat(scoring.options(ratio("4", "1", "5"))).isEqualTo(ds("1", "2", "3", "4"));
		// 목표가 step의 배수가 아니어도 목표값은 넣는다 (B3)
		assertThat(scoring.options(ratio("27", "5", "600"))).contains(d("27"));
		assertThat(scoring.options(OX)).isEqualTo(ds("1"));
		// 수면: 범위(6 ~ 8.5) ± 2칸 → 범위 안 · 밖이 둘 다 (D-42)
		assertThat(scoring.options(SLEEP)).isEqualTo(ds("5", "5.5", "6", "6.5", "7", "7.5", "8", "8.5", "9", "9.5"));
	}

	@Test
	void 선택지_밖_값은_받지_않는다() {
		Scoring.Measure walk = ratio("30", "5", "600");
		assertThat(scoring.accepts(walk, d("30.00"))).isTrue(); // 소수점 자리만 다른 같은 값
		assertThat(scoring.accepts(walk, d("27"))).isFalse();
		assertThat(scoring.accepts(walk, null)).isFalse();
		assertThat(scoring.accepts(SLEEP, d("9.5"))).isTrue();
		assertThat(scoring.accepts(SLEEP, d("10"))).isFalse();
	}
}
