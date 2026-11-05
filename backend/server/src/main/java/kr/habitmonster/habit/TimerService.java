package kr.habitmonster.habit;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.habit.TimerRepository.DayMinutes;
import kr.habitmonster.habit.TimerRepository.TimerHabit;
import kr.habitmonster.habit.TimerRepository.TimerRow;

import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 습관 타이머 (API 명세 v6 9장, 결정 D-62 · D-63). 서버 시각으로 재서 체크인 때 "확인된 기록"(VERIFIED)이 된다.
 *
 * <ul>
 * <li>분 단위 시간 습관(진행 중)만. 타이머는 습관마다 하나, 실제로 도는 것은 사용자당 하나 (일시정지한 것은 여러 개여도 된다)</li>
 * <li>경과 = (끝 또는 지금) − 시작 − 일시정지한 시간. 최대 {@code timer_max_minutes}(일시정지 뺀 경과)에 닿으면 자동 종료</li>
 * <li><b>00시에 끊지 않는다.</b> 기록되는 날 = 끝난 날 (23:30 ~ 00:12 → 다음 날 42분)</li>
 * <li>끝낼 때 앱이 집중 분({@code focusMinutes} — 뽀모도로 쉬는 시간 뺌)을 보내면 서버 경과와 작은 값</li>
 * <li>자동 종료는 스케줄러 없이 다음 요청 때 {@link #settle}이 처리하고, 끝난 시각은 "끝나야 했던 시각"으로 적는다</li>
 * </ul>
 */
@Service
public class TimerService {

	/** 앱이 보는 타이머. {@code todayMinutes} = 그 습관의 오늘 기록 합, {@code endReason}은 끝났을 때만. */
	public record TimerView(long timerId, long habitId, String status, OffsetDateTime startedAt, long elapsedSeconds,
			int todayMinutes, String endReason) {
	}

	public record HabitMinutes(long habitId, int todayMinutes, int sessions) {
	}

	/** {@code GET /timers/today}: 끝나지 않은 타이머 전부(어제 시작한 것도) + 오늘 기록된 합. */
	public record TodayTimers(List<TimerView> active, List<HabitMinutes> habits) {
	}

	public record StartTimer(LocalDate businessDate, Long habitId) {
	}

	/** {@code action}: PAUSE · RESUME · STOP. {@code focusMinutes}는 STOP에서만 (선택). */
	public record TimerAction(String action, Integer focusMinutes) {
	}

	private static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");

	private final TimerRepository timers;
	private final HabitRepository habits;
	private final BusinessDates dates;
	private final BalanceConfig config;
	private final Clock clock;

	TimerService(TimerRepository timers, HabitRepository habits, BusinessDates dates, BalanceConfig config, Clock clock) {
		this.timers = timers;
		this.habits = habits;
		this.dates = dates;
		this.config = config;
		this.clock = clock;
	}

	/** 시작. 검사 순서: 본인 습관(404) → 업무 날짜(409) → 타이머 습관(422) → 이미 있는 타이머(409, {@code timerId}). */
	@Transactional
	public TimerView start(long userId, StartTimer req) {
		if (req == null || req.habitId() == null) {
			throw new ApiException(ErrorCode.INVALID_REQUEST);
		}
		lock(userId);
		Instant now = clock.instant();
		settle(userId, now);
		TimerHabit h = timers.habit(userId, req.habitId()).orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND));
		LocalDate today = dates.requireToday(req.businessDate());
		if (!isTimerHabit(h)) {
			throw new ApiException(ErrorCode.NOT_TIMER_HABIT);
		}
		for (TimerRow t : timers.open(userId)) {
			if (t.habitId() == h.id() || t.running()) {
				throw ApiException.timerAlreadyRunning(t.id());
			}
		}
		long id;
		try {
			id = timers.start(userId, h.id(), today, at(now));
		}
		catch (DuplicateKeyException e) { // 잠금으로 거의 없지만, 고유 인덱스가 마지막 방어선
			throw new ApiException(ErrorCode.TIMER_ALREADY_RUNNING);
		}
		return view(userId, timers.timer(userId, id).orElseThrow(), now);
	}

	/** 일시정지 · 이어서 · 끝내기. 같은 상태로 다시 보내면(일시정지 중에 PAUSE) 그대로 돌려준다. */
	@Transactional
	public TimerView act(long userId, long timerId, TimerAction req) {
		String action = req == null ? null : req.action();
		if (action == null || !List.of("PAUSE", "RESUME", "STOP").contains(action)
				|| (req.focusMinutes() != null && (req.focusMinutes() < 0 || !"STOP".equals(action)))) {
			throw new ApiException(ErrorCode.INVALID_REQUEST);
		}
		lock(userId);
		Instant now = clock.instant();
		settle(userId, now);
		TimerRow t = timers.timer(userId, timerId).orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND));
		if (t.stopped()) {
			throw ApiException.timerNotRunning(t.endReason());
		}
		switch (action) {
			case "PAUSE" -> {
				if (t.running()) {
					timers.pause(t.id(), at(now));
				}
			}
			case "RESUME" -> {
				if (t.paused()) {
					for (TimerRow o : timers.open(userId)) {
						if (o.running() && o.id() != t.id()) {
							throw ApiException.timerAlreadyRunning(o.id());
						}
					}
					timers.resume(t.id(), pausedSecondsNow(t, now));
				}
			}
			default -> {
				int minutes = (int) Math.min(elapsedSeconds(t, now) / 60, config.timerMaxMinutes());
				if (req.focusMinutes() != null) {
					minutes = Math.min(minutes, req.focusMinutes());
				}
				timers.stop(t.id(), at(now), dates.dateOf(now), minutes, "USER", pausedSecondsNow(t, now));
			}
		}
		return view(userId, timers.timer(userId, timerId).orElseThrow(), now);
	}

	@Transactional
	public TodayTimers today(long userId) {
		lock(userId);
		Instant now = clock.instant();
		settle(userId, now);
		List<TimerView> active = timers.open(userId).stream().map(t -> view(userId, t, now)).toList();
		List<HabitMinutes> minutes = timers.minutesOn(userId, dates.today()).stream()
			.map(m -> new HabitMinutes(m.habitId(), m.todayMinutes(), m.sessions())).toList();
		return new TodayTimers(active, minutes);
	}

	/**
	 * 오늘 기록된 타이머 분 (습관 → 분). 체크인이 "확인된 기록"을 판정 · 미리 채울 때 쓴다.
	 * 부르는 쪽이 사용자 잠금을 잡은 트랜잭션 안에서 부른다 (자동 종료 정리를 먼저 한다).
	 */
	@Transactional
	public Map<Long, Integer> todayMinutes(long userId) {
		settle(userId, clock.instant());
		return timers.minutesOn(userId, dates.today()).stream()
			.collect(Collectors.toMap(DayMinutes::habitId, DayMinutes::todayMinutes));
	}

	/** 그 습관이 타이머를 쓸 수 있는 측정 항목인지 (진행 상태와 상관없이). */
	static boolean isTimerMeasure(String unit, String scoringMode) {
		return "분".equals(unit) && "TARGET_RATIO".equals(scoringMode);
	}

	/**
	 * 습관을 그만두거나 기간을 채웠을 때(같은 트랜잭션) — 그 습관의 끝나지 않은 타이머를 지금 끝낸다 ({@code HABIT_STOPPED}).
	 * 그때까지 잰 분은 기록으로만 남는다 (그 습관은 더 체크인 대상이 아님).
	 */
	void endForHabit(long userId, long habitId) {
		Instant now = clock.instant();
		settle(userId, now);
		for (TimerRow t : timers.open(userId)) {
			if (t.habitId() == habitId) {
				int minutes = (int) Math.min(elapsedSeconds(t, now) / 60, config.timerMaxMinutes());
				timers.stop(t.id(), at(now), dates.dateOf(now), minutes, "HABIT_STOPPED", pausedSecondsNow(t, now));
			}
		}
	}

	/** 탈퇴 — 끝나지 않은 타이머를 끝낸다 (기록 행은 통계용으로 남는다). */
	void endAll(long userId) {
		Instant now = clock.instant();
		settle(userId, now);
		for (TimerRow t : timers.open(userId)) {
			int minutes = (int) Math.min(elapsedSeconds(t, now) / 60, config.timerMaxMinutes());
			timers.stop(t.id(), at(now), dates.dateOf(now), minutes, "USER", pausedSecondsNow(t, now));
		}
	}

	/**
	 * 자동 종료 정리: 도는 타이머의 경과가 최대 시간에 닿았으면 그 시각(시작 + 최대 + 지난 일시정지)에 끝낸 것으로 적는다.
	 * 기록되는 날도 그 시각의 날 (22:00에 시작해 잊으면 02:00 → 다음 날 240분). 일시정지 중에는 경과가 늘지 않아 해당 없음.
	 */
	private void settle(long userId, Instant now) {
		long maxSeconds = config.timerMaxMinutes() * 60L;
		for (TimerRow t : timers.open(userId)) {
			if (t.running() && elapsedSeconds(t, now) >= maxSeconds) {
				Instant end = Instant.ofEpochMilli(t.startedMs()).plusSeconds(t.pausedSeconds() + maxSeconds);
				timers.stop(t.id(), at(end), dates.dateOf(end), config.timerMaxMinutes(), "MAX_DURATION", 0);
			}
		}
	}

	private static boolean isTimerHabit(TimerHabit h) {
		return "ACTIVE".equals(h.status()) && isTimerMeasure(h.unit(), h.scoringMode());
	}

	/** 일시정지를 뺀 경과 초 (끝났으면 끝난 시각, 일시정지 중이면 일시정지한 시각까지). */
	private static long elapsedSeconds(TimerRow t, Instant now) {
		long endMs = t.endedMs() != null ? t.endedMs() : t.pausedMs() != null ? t.pausedMs() : now.toEpochMilli();
		return Math.max(0, (endMs - t.startedMs()) / 1000 - t.pausedSeconds());
	}

	/** 지금 일시정지 중이면 일시정지한 뒤 흐른 초 (이어서 · 끝내기 때 일시정지 합에 더한다). */
	private static int pausedSecondsNow(TimerRow t, Instant now) {
		return t.pausedMs() == null ? 0 : (int) Math.max(0, (now.toEpochMilli() - t.pausedMs()) / 1000);
	}

	private TimerView view(long userId, TimerRow t, Instant now) {
		long elapsed = Math.min(elapsedSeconds(t, now), config.timerMaxMinutes() * 60L);
		int today = timers.minutesOn(userId, dates.today()).stream().filter(m -> m.habitId() == t.habitId())
			.mapToInt(DayMinutes::todayMinutes).sum();
		return new TimerView(t.id(), t.habitId(), t.status(),
				OffsetDateTime.ofInstant(Instant.ofEpochMilli(t.startedMs()), SEOUL), elapsed, today, t.endReason());
	}

	private void lock(long userId) {
		habits.lockHabitUser(userId).orElseThrow(() -> new IllegalStateException("습관 프로필 없음: " + userId));
	}

	private static OffsetDateTime at(Instant t) {
		return OffsetDateTime.ofInstant(t, SEOUL);
	}
}
