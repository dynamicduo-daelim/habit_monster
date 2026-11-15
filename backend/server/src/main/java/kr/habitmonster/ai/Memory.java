package kr.habitmonster.ai;

import java.math.BigDecimal;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * 몬스터의 기억 — 최근 며칠(오늘 제외)의 습관 기록 (기획 {@code docs/기획/2026-11-15-몬스터-대화.md} C).
 * 부르는 쪽(체크인 조율)이 습관 모듈에서 읽어 값으로 넘긴다. 대사 · 자유 대화 프롬프트에만 넣는다 (해석에는 안 넣음).
 *
 * <p>숫자 검사: 여기 넣은 값과 "n일 전"의 n만 허용한다 — 문맥에 없는 숫자는 지어낸 것이다.
 */
public final class Memory {

	private Memory() {
	}

	/** {@code value}: 그날 최신 값 (못 했으면 0). */
	public record PastHabit(String name, String unit, String scoringMode, Number value) {

		boolean done() {
			return value != null && new BigDecimal(value.toString()).signum() > 0;
		}
	}

	/** {@code daysAgo}: 1 = 어제. {@code habits}가 비었으면 그날 체크하지 않았다. */
	public record PastDay(int daysAgo, List<PastHabit> habits) {
	}

	static void append(StringBuilder sb, List<PastDay> days) {
		sb.append("최근 기록 (오늘 제외, 지금 하는 습관만):\n");
		if (days.isEmpty() || days.stream().allMatch(d -> d.habits().isEmpty())) {
			sb.append("아직 지난 기록 없음\n");
			return;
		}
		for (PastDay d : days) {
			sb.append(label(d.daysAgo())).append(": ");
			if (d.habits().isEmpty()) {
				sb.append("체크 안 함\n");
				continue;
			}
			sb.append(d.habits().stream().map(Memory::describe).collect(Collectors.joining(", "))).append('\n');
		}
	}

	static String label(int daysAgo) {
		return daysAgo == 1 ? "어제" : daysAgo + "일 전";
	}

	private static String describe(PastHabit h) {
		if (!h.done()) {
			return h.name() + " 못 함";
		}
		return "BINARY".equals(h.scoringMode()) ? h.name() + " 했음" : h.name() + " " + h.value() + h.unit();
	}

	/** 기억 문맥에 나온 숫자 (값 · 날 수). */
	static Stream<Number> numbers(List<PastDay> days) {
		return days.stream().flatMap(d -> Stream.concat(Stream.of((Number) d.daysAgo()),
				d.habits().stream().map(PastHabit::value)));
	}

	static Set<String> normalized(Stream<Number> numbers) {
		return numbers.filter(n -> n != null).map(n -> normalize(n.toString())).collect(Collectors.toSet());
	}

	static String normalize(String n) {
		return new BigDecimal(n).stripTrailingZeros().toPlainString();
	}
}
