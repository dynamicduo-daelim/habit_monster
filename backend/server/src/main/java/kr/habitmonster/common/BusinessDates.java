package kr.habitmonster.common;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.TemporalAdjusters;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * 업무 날짜 — "오늘 체크인 · 탐색 3회 · 쓰다듬기 1회"가 언제 초기화되는지의 기준 (API 명세 v4 공통 규칙).
 * 서버 시계로만 계산하고, 사용자별 시간대는 없다 (Asia/Seoul 고정). 경계 시각은 00시 (v4에서 04시 → 00시).
 * 주는 월요일, 월은 1일에 시작한다.
 */
@Component
public class BusinessDates {

	private final Clock clock;
	private final ZoneId zone;
	private final int boundaryHour;

	public BusinessDates(Clock clock,
			@Value("${app.business.zone:Asia/Seoul}") String zone,
			@Value("${app.business.day-boundary-hour:0}") int boundaryHour) {
		this.clock = clock;
		this.zone = ZoneId.of(zone);
		this.boundaryHour = boundaryHour;
	}

	/** 지금의 업무 날짜. 경계가 04시라면 03:59는 전날이다. */
	public LocalDate today() {
		return dateOf(clock.instant());
	}

	/** 어떤 시각이 속한 업무 날짜 (예: 온보딩한 날). */
	public LocalDate dateOf(Instant t) {
		return t.atZone(zone).minusHours(boundaryHour).toLocalDate();
	}

	public LocalDate weekStart() {
		return today().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
	}

	public LocalDate monthStart() {
		return today().withDayOfMonth(1);
	}

	/**
	 * 앱이 화면을 연 날짜({@code businessDate})가 서버의 오늘과 같은지. 다르면 409 {@code BUSINESS_DATE_CHANGED} —
	 * 23:59에 연 화면으로 00:01에 제출하면 어제 화면의 값이 오늘 기록으로 들어가는 것을 막는다.
	 */
	public LocalDate requireToday(LocalDate businessDate) {
		LocalDate today = today();
		if (businessDate == null) {
			throw new ApiException(ErrorCode.INVALID_REQUEST);
		}
		if (!businessDate.equals(today)) {
			throw new ApiException(ErrorCode.BUSINESS_DATE_CHANGED);
		}
		return today;
	}
}
