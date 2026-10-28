package kr.habitmonster.habit;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

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

	// ---------- 추가 · 연장 · 그만두기 (4-1) ----------
	/** 습관 칸을 차지하는 습관 수 = 진행 중 + 기간 완료 (상한 5 · 하한 1의 기준). */
	int countOpen(long userId) {
		return db.sql("select count(*) from habit.habit where user_id = ? and status in ('ACTIVE','ENDED')")
			.param(userId).query(Integer.class).single();
	}

	boolean isOpened(long userId, String categoryCode) {
		return db.sql("select count(*) from habit.user_category where user_id = ? and category_code = ?")
			.params(userId, categoryCode).query(Integer.class).single() > 0;
	}

	/** 내 습관 하나 (+ 마지막 기간). 남의 습관이면 비어 있다. */
	Optional<HabitRow> habit(long userId, long habitId) {
		return db.sql(HABIT_WITH_LAST_PERIOD + " where h.user_id = ? and h.id = ?")
			.params(userId, habitId).query(HabitRow.class).optional();
	}

	int lastSeq(long habitId) {
		return db.sql("select max(seq) from habit.habit_period where habit_id = ?").param(habitId).query(Integer.class).single();
	}

	/** 연장: 기간 완료 → 진행 중. 상태가 ENDED일 때만 바꾼다 (바뀐 행 수). */
	int reopenHabit(long habitId) {
		return db.sql("update habit.habit set status = 'ACTIVE', updated_at = now() where id = ? and status = 'ENDED'")
			.param(habitId).update();
	}

	/** 그만두기. 진행 중이던 기간은 채우지 못한 채 남는다 (schema 주석). */
	void stopHabit(long habitId) {
		db.sql("update habit.habit set status = 'STOPPED', stopped_at = now(), updated_at = now() where id = ?")
			.param(habitId).update();
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

	// ---------- 체크인 (3-3) ----------
	/**
	 * 체크인 한 줄의 습관 정보 + 측정 방식 + 그 기간. 제출 전에는 마지막 기간 · 목표, 제출 후에는 체크인에 기록된 기간 · 목표(snapshot)와
	 * 최신 값({@code value} · {@code score}).
	 */
	record CheckinHabitRow(long habitId, String name, String categoryCode, String categoryName, int categorySort,
			String unit, String scoringMode, BigDecimal step, BigDecimal maxValue, BigDecimal rangeBelow,
			BigDecimal rangeAbove, BigDecimal target, long periodId, int periodSeq, String periodCode, int periodDays,
			int filledDays, int countedScoreSum, BigDecimal value, Integer score, Integer rewardedScore, Boolean isCounted) {
	}

	private static final String CHECKIN_HABIT_COLUMNS = """
		select h.id as habit_id, h.name, h.category_code, c.name as category_name, c.sort_order as category_sort, m.unit,
		       m.scoring_mode, m.step, m.max_value, m.range_below, m.range_above,
		""";

	private static final String CHECKIN_HABIT_JOINS = """
		  join habit.category c on c.code = h.category_code
		  join habit.measure_type m on m.id = h.measure_type_id
		""";

	/** 오늘 체크인 대상 (제출 전): ACTIVE이고 마지막 기간이 아직 안 찼고 시작일 ≤ 오늘. 습관 id 순서 (= 등록 순서). */
	List<CheckinHabitRow> targetHabits(long userId, LocalDate today) {
		return db.sql(CHECKIN_HABIT_COLUMNS + """
			       p.daily_target as target, p.id as period_id, p.seq as period_seq, p.period_code, p.period_days,
			       p.filled_days, p.counted_score_sum, null as value, null as score, null as rewarded_score,
			       null as is_counted
			  from habit.habit h
			""" + CHECKIN_HABIT_JOINS + """
			  join habit.habit_period p on p.habit_id = h.id and p.ended_on is null
			 where h.user_id = ? and h.status = 'ACTIVE' and p.started_on <= ?
			 order by h.id""")
			.params(userId, today).query(CheckinHabitRow.class).list();
	}

	/** 오늘 제출에 들어간 습관 (다시 체크 대상 — 그 뒤 ENDED · STOPPED여도). 목표는 제출 때의 snapshot. */
	List<CheckinHabitRow> submittedHabits(long checkinId) {
		return db.sql(CHECKIN_HABIT_COLUMNS + """
			       hc.target_snapshot as target, p.id as period_id, p.seq as period_seq, p.period_code, p.period_days,
			       p.filled_days, p.counted_score_sum, hc.value, hc.score, hc.rewarded_score, hc.is_counted
			  from habit.habit_checkin hc
			  join habit.habit h on h.id = hc.habit_id
			""" + CHECKIN_HABIT_JOINS + """
			  join habit.habit_period p on p.habit_id = hc.habit_id and p.seq = hc.period_seq
			 where hc.daily_checkin_id = ?
			 order by h.id""")
			.param(checkinId).query(CheckinHabitRow.class).list();
	}

	record DailyCheckinRow(long id, int revision) {
	}

	Optional<DailyCheckinRow> dailyCheckin(long userId, LocalDate day) {
		return db.sql("select id, revision from habit.daily_checkin where user_id = ? and checkin_date = ?")
			.params(userId, day).query(DailyCheckinRow.class).optional();
	}

	long insertDailyCheckin(long userId, LocalDate day, int habitCount, int totalScore, int countedScore) {
		return db.sql("""
			insert into habit.daily_checkin (user_id, checkin_date, habit_count, total_score, counted_score)
			values (?, ?, ?, ?, ?) returning id""")
			.params(userId, day, habitCount, totalScore, countedScore).query(Long.class).single();
	}

	/** 다시 체크: 최신 합계 · 제출 횟수만 (보상 기준값은 트리거가 막는다). 새 revision. */
	int reviseDailyCheckin(long checkinId, int totalScore) {
		return db.sql("""
			update habit.daily_checkin set total_score = ?, revision = revision + 1, last_submitted_at = now()
			 where id = ? returning revision""")
			.params(totalScore, checkinId).query(Integer.class).single();
	}

	/** 제출 1건 = 1행. 이 키가 이미 다른 제출에 쓰였으면 false. */
	boolean insertSubmission(UUID key, long checkinId, int revision) {
		return db.sql("""
			insert into habit.checkin_submission (idempotency_key, daily_checkin_id, revision) values (?, ?, ?)
			on conflict (idempotency_key) do nothing""")
			.params(key, checkinId, revision).update() == 1;
	}

	void insertHabitCheckin(long checkinId, long habitId, int periodSeq, BigDecimal value, BigDecimal target, int score,
			boolean counted) {
		db.sql("""
			insert into habit.habit_checkin (daily_checkin_id, habit_id, period_seq, value, target_snapshot, score,
			                                 rewarded_value, rewarded_score, is_counted, is_filled)
			values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""")
			.params(checkinId, habitId, periodSeq, value, target, score, value, score, counted, value.signum() > 0)
			.update();
	}

	void updateHabitCheckin(long checkinId, long habitId, BigDecimal value, int score) {
		db.sql("update habit.habit_checkin set value = ?, score = ? where daily_checkin_id = ? and habit_id = ?")
			.params(value, score, checkinId, habitId).update();
	}

	/** 기간의 채운 날 · 반영 점수 합. 기간을 채웠으면 {@code endedOn} · {@code bonus}도 같은 문장에서 (DB CHECK가 같이 요구). */
	void updatePeriod(long periodId, int filledDays, int countedScoreSum, LocalDate endedOn, Integer bonus) {
		db.sql("""
			update habit.habit_period set filled_days = ?, counted_score_sum = ?, ended_on = ?, period_bonus = ?
			 where id = ?""")
			.params(filledDays, countedScoreSum, endedOn, bonus, periodId).update();
	}

	void endHabit(long habitId) {
		db.sql("update habit.habit set status = 'ENDED', updated_at = now() where id = ?").param(habitId).update();
	}

	record CategoryExpRow(String categoryCode, int expTotal, int level) {
	}

	List<CategoryExpRow> categoryExp(long userId) {
		return db.sql("select category_code, exp_total, level from habit.user_category where user_id = ?")
			.param(userId).query(CategoryExpRow.class).list();
	}

	void updateCategoryExp(long userId, String categoryCode, int expTotal, int level) {
		db.sql("""
			update habit.user_category set exp_total = ?, level = ?, updated_at = now()
			 where user_id = ? and category_code = ?""")
			.params(expTotal, level, userId, categoryCode).update();
	}

	void updateStreak(long userId, int current, int longest, LocalDate lastAttended) {
		db.sql("""
			update habit.habit_user set current_streak = ?, longest_streak = ?, last_attended_date = ?,
			       version = version + 1, updated_at = now()
			 where user_id = ?""")
			.params(current, longest, lastAttended, userId).update();
	}

	// ---------- 탐색 (3-4) ----------
	/** 도감 해금권 1장. 같은 기준값이면 이미 받은 것이라 false (DB UNIQUE(user_id, milestone)). */
	boolean insertUnlockTicket(long userId, int milestone) {
		return db.sql("insert into habit.category_unlock_ticket (user_id, milestone) values (?, ?) on conflict do nothing")
			.params(userId, milestone).update() == 1;
	}

	// ---------- 카테고리 열기 (4-3) ----------
	int countUnusedTickets(long userId) {
		return db.sql("select count(*) from habit.category_unlock_ticket where user_id = ? and used_at is null")
			.param(userId).query(Integer.class).single();
	}

	/** 가장 먼저 받은 안 쓴 해금권. */
	Optional<Long> firstUnusedTicket(long userId) {
		return db.sql("""
			select id from habit.category_unlock_ticket where user_id = ? and used_at is null order by milestone limit 1""")
			.param(userId).query(Long.class).optional();
	}

	void useTicket(long ticketId, String categoryCode) {
		db.sql("update habit.category_unlock_ticket set used_category_code = ?, used_at = now() where id = ?")
			.params(categoryCode, ticketId).update();
	}
}
