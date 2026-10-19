package kr.habitmonster.common;

import java.math.BigDecimal;

/** DB의 NUMERIC 값을 JSON 숫자로 — 정수면 {@code 30}, 소수면 {@code 0.5} (BigDecimal 그대로면 {@code 30.00} · {@code 1E+4}로 나간다). */
public final class Decimals {

	private Decimals() {
	}

	public static Number plain(BigDecimal v) {
		if (v == null) {
			return null;
		}
		BigDecimal s = v.stripTrailingZeros();
		return s.scale() <= 0 ? (Number) s.longValueExact() : (Number) s.doubleValue();
	}
}
