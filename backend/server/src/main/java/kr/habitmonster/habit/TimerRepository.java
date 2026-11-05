package kr.habitmonster.habit;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * 습관 타이머 {@code habit.habit_timer} (스키마 v1.9, 명세 v6 9장). 시각은 밀리초 숫자(epoch)로 읽어 서버 쪽 계산을 단순하게 한다.
 * 고유 인덱스 두 개가 "습관마다 끝나지 않은 것 하나 · 도는 것은 사용자당 하나"를 DB에서도 막는다.
 */
@Repository
class TimerRepository {

	/** 타이머 한 행. {@code *Ms}는 1970-01-01 UTC부터 밀리초. */
	record TimerRow(long id, long habitId, LocalDate businessDate, String status, long startedMs, Long pausedMs,
			int pausedSeconds, Long endedMs, String endReason, Integer countedMinutes) {
		boolean running() {
			return "RUNNING".equals(status);
		}

		boolean paused() {
			return "PAUSED".equals(status);
		}

		boolean stopped() {
			return "STOPPED".equals(status);
		}
	}

	/** 타이머를 쓸 수 있는지 판단할 습관 정보. */
	record TimerHabit(long id, String status, String unit, String scoringMode) {
	}

	/** 그날 기록된(끝난) 타이머의 습관별 합. */
	record DayMinutes(long habitId, int todayMinutes, int sessions) {
	}

	private static final String COLUMNS = """
		id, habit_id, business_date, status,
		(extract(epoch from started_at) * 1000)::bigint as started_ms,
		(extract(epoch from paused_at) * 1000)::bigint as paused_ms,
		paused_seconds,
		(extract(epoch from ended_at) * 1000)::bigint as ended_ms,
		end_reason, counted_minutes""";

	private final JdbcClient db;

	TimerRepository(JdbcClient db) {
		this.db = db;
	}

	Optional<TimerHabit> habit(long userId, long habitId) {
		return db.sql("""
			select h.id, h.status, m.unit, m.scoring_mode
			  from habit.habit h join habit.measure_type m on m.id = h.measure_type_id
			 where h.user_id = ? and h.id = ?""")
			.params(userId, habitId).query(TimerHabit.class).optional();
	}

	Optional<TimerRow> timer(long userId, long timerId) {
		return db.sql("select " + COLUMNS + " from habit.habit_timer where user_id = ? and id = ?")
			.params(userId, timerId).query(TimerRow.class).optional();
	}

	/** 끝나지 않은 타이머 (도는 것 · 일시정지), 시작 순서. */
	List<TimerRow> open(long userId) {
		return db.sql("select " + COLUMNS + " from habit.habit_timer where user_id = ? and status in ('RUNNING','PAUSED') order by id")
			.param(userId).query(TimerRow.class).list();
	}

	long start(long userId, long habitId, LocalDate businessDate, OffsetDateTime at) {
		return db.sql("""
			insert into habit.habit_timer (user_id, habit_id, business_date, status, started_at)
			values (?, ?, ?, 'RUNNING', ?) returning id""")
			.params(userId, habitId, businessDate, at).query(Long.class).single();
	}

	void pause(long timerId, OffsetDateTime at) {
		db.sql("update habit.habit_timer set status = 'PAUSED', paused_at = ? where id = ? and status = 'RUNNING'")
			.params(at, timerId).update();
	}

	/** 이어서 — 이번 일시정지 시간을 합에 더한다. */
	void resume(long timerId, int addPausedSeconds) {
		db.sql("""
			update habit.habit_timer set status = 'RUNNING', paused_at = null, paused_seconds = paused_seconds + ?
			 where id = ? and status = 'PAUSED'""")
			.params(addPausedSeconds, timerId).update();
	}

	/** 끝내기 — 기록되는 날은 끝난 날로 다시 적고, 일시정지 중이었으면 그 시간도 합에 더한다. */
	void stop(long timerId, OffsetDateTime endedAt, LocalDate businessDate, int countedMinutes, String reason,
			int addPausedSeconds) {
		db.sql("""
			update habit.habit_timer
			   set status = 'STOPPED', paused_at = null, paused_seconds = paused_seconds + ?, ended_at = ?,
			       business_date = ?, counted_minutes = ?, end_reason = ?
			 where id = ? and status in ('RUNNING','PAUSED')""")
			.params(addPausedSeconds, endedAt, businessDate, countedMinutes, reason, timerId).update();
	}

	List<DayMinutes> minutesOn(long userId, LocalDate day) {
		return db.sql("""
			select habit_id, sum(counted_minutes)::int as today_minutes, count(*)::int as sessions
			  from habit.habit_timer
			 where user_id = ? and business_date = ? and status = 'STOPPED'
			 group by habit_id order by habit_id""")
			.params(userId, day).query(DayMinutes.class).list();
	}
}
