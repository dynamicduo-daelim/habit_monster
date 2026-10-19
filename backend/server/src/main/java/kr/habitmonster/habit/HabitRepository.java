package kr.habitmonster.habit;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** {@code habit} 스키마만 읽고 쓴다 (카테고리 · 측정 항목 · 추천 습관 마스터, 사용자 습관 · 기간 · 출석 · 체크인). */
@Repository
class HabitRepository {

	record CategoryRow(String code, String name, String shortName, String element, String glyph, String color,
			int sortOrder) {
	}

	record MeasureTypeRow(int id, String categoryCode, String name, String unit, String scoringMode,
			BigDecimal defaultTarget, BigDecimal step, BigDecimal maxValue, BigDecimal rangeBelow, BigDecimal rangeAbove,
			int sortOrder) {
	}

	record PresetRow(int id, String categoryCode, int measureTypeId, String name, BigDecimal defaultTarget) {
	}

	record StreakRow(int currentStreak, int longestStreak, LocalDate lastAttendedDate) {
	}

	private final JdbcClient db;

	HabitRepository(JdbcClient db) {
		this.db = db;
	}

	// ---------- 마스터 ----------
	List<CategoryRow> categories() {
		return db.sql("""
			select code, name, short_name, element, glyph, color, sort_order from habit.category order by sort_order""")
			.query(CategoryRow.class).list();
	}

	List<MeasureTypeRow> measureTypes(Collection<String> categoryCodes) {
		return db.sql("""
			select id, category_code, name, unit, scoring_mode, default_target, step, max_value, range_below, range_above,
			       sort_order
			  from habit.measure_type where category_code in (:codes) order by category_code, sort_order""")
			.param("codes", categoryCodes).query(MeasureTypeRow.class).list();
	}

	Optional<MeasureTypeRow> measureType(int id) {
		return db.sql("""
			select id, category_code, name, unit, scoring_mode, default_target, step, max_value, range_below, range_above,
			       sort_order
			  from habit.measure_type where id = ?""")
			.param(id).query(MeasureTypeRow.class).optional();
	}

	List<PresetRow> presets(Collection<String> categoryCodes) {
		return db.sql("""
			select id, category_code, measure_type_id, name, default_target from habit.habit_preset
			 where category_code in (:codes) order by category_code, sort_order""")
			.param("codes", categoryCodes).query(PresetRow.class).list();
	}

	// ---------- 사용자 프로필 · 카테고리 ----------
	void createHabitUser(long userId) {
		db.sql("insert into habit.habit_user (user_id) values (?)").param(userId).update();
	}

	void openCategory(long userId, String categoryCode, String openedVia) {
		db.sql("insert into habit.user_category (user_id, category_code, opened_via) values (?, ?, ?)")
			.params(userId, categoryCode, openedVia).update();
	}

	List<String> openedCategories(long userId) {
		return db.sql("""
			select uc.category_code from habit.user_category uc join habit.category c on c.code = uc.category_code
			 where uc.user_id = ? order by c.sort_order""")
			.param(userId).query(String.class).list();
	}

	// ---------- 습관 · 기간 ----------
	long insertHabit(long userId, String categoryCode, int measureTypeId, String name) {
		return db.sql("""
			insert into habit.habit (user_id, category_code, measure_type_id, name) values (?, ?, ?, ?) returning id""")
			.params(userId, categoryCode, measureTypeId, name).query(Long.class).single();
	}

	void insertPeriod(long habitId, int seq, String periodCode, int periodDays, BigDecimal dailyTarget, LocalDate startedOn) {
		db.sql("""
			insert into habit.habit_period (habit_id, seq, period_code, period_days, daily_target, started_on)
			values (?, ?, ?, ?, ?, ?)""")
			.params(habitId, seq, periodCode, periodDays, dailyTarget, startedOn).update();
	}

	/** 탈퇴: 습관 이름을 비운다 (DB 원칙 7 — 행은 남기고 개인 텍스트만). */
	void clearNames(long userId) {
		db.sql("update habit.habit set name = null, updated_at = now() where user_id = ?").param(userId).update();
	}

	// ---------- 출석 ----------
	/** 사용자 잠금 행 (잠금 순서의 처음). 온보딩 전이면 비어 있다. */
	Optional<StreakRow> lockHabitUser(long userId) {
		return db.sql("""
			select current_streak, longest_streak, last_attended_date from habit.habit_user
			 where user_id = ? for no key update""")
			.param(userId).query(StreakRow.class).optional();
	}

	Optional<StreakRow> streak(long userId) {
		return db.sql("select current_streak, longest_streak, last_attended_date from habit.habit_user where user_id = ?")
			.param(userId).query(StreakRow.class).optional();
	}

	/** 오늘 출석 1행. 이미 있으면 false (하루에 여러 번 불러도 1행). */
	boolean insertAttendance(long userId, LocalDate day) {
		return db.sql("insert into habit.attendance (user_id, attended_on) values (?, ?) on conflict do nothing")
			.params(userId, day).update() == 1;
	}

	// ---------- 조회 (3-2) ----------
	/** 습관 + 그 습관의 마지막 기간 (연장하면 seq가 커진다). */
	record HabitRow(long habitId, String categoryCode, String name, int measureTypeId, String unit, BigDecimal dailyTarget,
			String periodCode, LocalDate startDate, int filledDays, int periodDays, String status, long periodId) {
	}

	private static final String HABIT_WITH_LAST_PERIOD = """
		select h.id as habit_id, h.category_code, h.name, h.measure_type_id, m.unit, p.daily_target, p.period_code,
		       p.started_on as start_date, p.filled_days, p.period_days, h.status, p.id as period_id
		  from habit.habit h
		  join habit.measure_type m on m.id = h.measure_type_id
		  join habit.habit_period p on p.habit_id = h.id
		   and p.seq = (select max(seq) from habit.habit_period where habit_id = h.id)
		""";

	List<HabitRow> habits(long userId, Collection<String> statuses) {
		return db.sql(HABIT_WITH_LAST_PERIOD + " where h.user_id = :user and h.status in (:statuses) order by h.id")
			.param("user", userId).param("statuses", statuses).query(HabitRow.class).list();
	}

	/** 오늘 체크인 대상: 진행 중(ACTIVE)이고 기간이 시작된 습관 (시작일 ≤ 오늘). */
	List<HabitRow> checkinTargets(long userId, LocalDate today) {
		return db.sql(HABIT_WITH_LAST_PERIOD + """
			 where h.user_id = ? and h.status = 'ACTIVE' and p.ended_on is null and p.started_on <= ? order by h.id""")
			.params(userId, today).query(HabitRow.class).list();
	}

	int countByStatus(long userId, String status) {
		return db.sql("select count(*) from habit.habit where user_id = ? and status = ?")
			.params(userId, status).query(Integer.class).single();
	}

	record CheckinRow(long id, int countedScore) {
	}

	Optional<CheckinRow> checkin(long userId, LocalDate day) {
		return db.sql("select id, counted_score from habit.daily_checkin where user_id = ? and checkin_date = ?")
			.params(userId, day).query(CheckinRow.class).optional();
	}

	/** 체크인에 들어간 습관 (첫 제출의 보상 기준값) + 그날이 속한 기간. */
	record CheckedHabitRow(long habitId, String name, String categoryCode, String unit, BigDecimal targetSnapshot,
			BigDecimal rewardedValue, int rewardedScore, boolean isCounted, int filledDays, int periodDays, long periodId,
			LocalDate endedOn) {
	}

	List<CheckedHabitRow> checkedHabits(long checkinId) {
		return db.sql("""
			select hc.habit_id, h.name, h.category_code, m.unit, hc.target_snapshot, hc.rewarded_value, hc.rewarded_score,
			       hc.is_counted, p.filled_days, p.period_days, p.id as period_id, p.ended_on
			  from habit.habit_checkin hc
			  join habit.habit h on h.id = hc.habit_id
			  join habit.measure_type m on m.id = h.measure_type_id
			  join habit.habit_period p on p.habit_id = hc.habit_id and p.seq = hc.period_seq
			 where hc.daily_checkin_id = ? order by hc.habit_id""")
			.param(checkinId).query(CheckedHabitRow.class).list();
	}

	void updateStreak(long userId, int current, int longest, LocalDate lastAttended) {
		db.sql("""
			update habit.habit_user set current_streak = ?, longest_streak = ?, last_attended_date = ?,
			       version = version + 1, updated_at = now()
			 where user_id = ?""")
			.params(current, longest, lastAttended, userId).update();
	}
}
