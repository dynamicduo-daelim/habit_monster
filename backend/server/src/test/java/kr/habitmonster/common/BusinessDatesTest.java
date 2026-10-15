package kr.habitmonster.common;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;

import org.junit.jupiter.api.Test;

class BusinessDatesTest {

	static BusinessDates at(String instant, int boundaryHour) {
		return new BusinessDates(Clock.fixed(Instant.parse(instant), ZoneOffset.UTC), "Asia/Seoul", boundaryHour);
	}

	@Test
	void 서울_자정이_경계() {
		// 2026-10-11T15:00Z = 10-12 00:00 KST
		assertThat(at("2026-10-11T14:59:59Z", 0).today()).isEqualTo(LocalDate.of(2026, 10, 11));
		assertThat(at("2026-10-11T15:00:00Z", 0).today()).isEqualTo(LocalDate.of(2026, 10, 12));
	}

	@Test
	void 경계를_4시로_바꾸면_새벽은_전날() {
		// 10-12 03:59 KST
		assertThat(at("2026-10-11T18:59:00Z", 4).today()).isEqualTo(LocalDate.of(2026, 10, 11));
		assertThat(at("2026-10-11T19:00:00Z", 4).today()).isEqualTo(LocalDate.of(2026, 10, 12));
	}

	@Test
	void 주는_월요일_월은_1일부터() {
		BusinessDates thursday = at("2026-10-15T03:00:00Z", 0); // 10-15(목) 12:00 KST
		assertThat(thursday.weekStart()).isEqualTo(LocalDate.of(2026, 10, 12));
		assertThat(thursday.monthStart()).isEqualTo(LocalDate.of(2026, 10, 1));
		assertThat(at("2026-10-11T15:00:00Z", 0).weekStart()).isEqualTo(LocalDate.of(2026, 10, 12)); // 월요일 당일
	}

	@Test
	void 앱의_날짜가_서버_오늘과_다르면_거절() {
		BusinessDates d = at("2026-10-11T15:00:01Z", 0); // 10-12 00:00:01 KST
		assertThat(d.requireToday(LocalDate.of(2026, 10, 12))).isEqualTo(LocalDate.of(2026, 10, 12));
		assertThatThrownBy(() -> d.requireToday(LocalDate.of(2026, 10, 11)))
			.isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo(ErrorCode.BUSINESS_DATE_CHANGED));
		assertThatThrownBy(() -> d.requireToday(null))
			.isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo(ErrorCode.INVALID_REQUEST));
	}
}
