package kr.habitmonster.habit;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import com.fasterxml.jackson.annotation.JsonInclude;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.common.Decimals;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.habit.HabitRepository.CategoryRow;
import kr.habitmonster.habit.HabitRepository.MeasureTypeRow;
import kr.habitmonster.habit.HabitRepository.StreakRow;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 습관 모듈 — 카테고리 · 측정 항목 마스터, 사용자의 연 카테고리 · 습관 · 기간 · 출석.
 * 다른 모듈(온보딩 · 몬스터 · 조회)은 습관 데이터가 필요하면 이 서비스를 부른다 (DB 원칙: 모듈 = 스키마).
 */
@Service
public class HabitService {

	public record Category(String code, String name, String shortName, String element, String glyph, String color,
			int sortOrder) {
	}

	/** 측정 항목. {@code RANGE}(수면 시간)만 {@code rangeBelow} · {@code rangeAbove}가 있다 (D-28). */
	@JsonInclude(JsonInclude.Include.NON_NULL)
	public record MeasureType(int id, String name, String unit, String scoringMode, Number defaultTarget, Number step,
			Number maxValue, Number rangeBelow, Number rangeAbove) {
	}

	public record Preset(int id, String name, int measureTypeId, Number defaultTarget) {
	}

	/** {@code GET /measure-types} 응답의 카테고리 한 묶음. */
	public record MeasureTypeGroup(String categoryCode, List<MeasureType> measureTypes, List<Preset> presets) {
	}

	/** 검사용 측정 항목 정보 (응답에는 안 나감). */
	public record MeasureRule(int id, String categoryCode, BigDecimal maxValue) {
	}

	/** 출석 결과 = {@code POST /me/attendance} 응답. */
	public record Attendance(LocalDate date, boolean alreadyAttended, int currentStreak, int longestStreak) {
	}

	private final HabitRepository habits;
	private final BusinessDates dates;
	private final BalanceConfig config;

	HabitService(HabitRepository habits, BusinessDates dates, BalanceConfig config) {
		this.habits = habits;
		this.dates = dates;
		this.config = config;
	}

	// ---------- 마스터 ----------
	@Transactional(readOnly = true)
	public List<Category> categories() {
		return habits.categories().stream()
			.map(c -> new Category(c.code(), c.name(), c.shortName(), c.element(), c.glyph(), c.color(), c.sortOrder()))
			.toList();
	}

	/** 고른 카테고리의 측정 항목 + 추천 습관 (카테고리 순서대로). */
	@Transactional(readOnly = true)
	public List<MeasureTypeGroup> measureTypes(Collection<String> categoryCodes) {
		List<MeasureTypeRow> types = habits.measureTypes(categoryCodes);
		var presets = habits.presets(categoryCodes);
		return habits.categories().stream()
			.map(CategoryRow::code)
			.filter(categoryCodes::contains)
			.map(code -> new MeasureTypeGroup(code,
				types.stream().filter(t -> t.categoryCode().equals(code)).map(HabitService::view).toList(),
				presets.stream().filter(p -> p.categoryCode().equals(code))
					.map(p -> new Preset(p.id(), p.name(), p.measureTypeId(), Decimals.plain(p.defaultTarget())))
					.toList()))
			.toList();
	}

	@Transactional(readOnly = true)
	public Optional<MeasureRule> measureRule(int measureTypeId) {
		return habits.measureType(measureTypeId).map(t -> new MeasureRule(t.id(), t.categoryCode(), t.maxValue()));
	}

	private static MeasureType view(MeasureTypeRow t) {
		return new MeasureType(t.id(), t.name(), t.unit(), t.scoringMode(), Decimals.plain(t.defaultTarget()),
				Decimals.plain(t.step()), Decimals.plain(t.maxValue()), Decimals.plain(t.rangeBelow()),
				Decimals.plain(t.rangeAbove()));
	}

	// ---------- 사용자 ----------
	/** 연 카테고리 (카테고리 순서). 온보딩 전이면 비어 있다. */
	@Transactional(readOnly = true)
	public List<String> openedCategories(long userId) {
		return habits.openedCategories(userId);
	}

	/**
	 * 온보딩: 습관 프로필(사용자 잠금 · 연속 출석 행)을 만들고 고른 카테고리를 Lv.1로 연다.
	 * 다른 모듈보다 먼저 부른다 — 잠금 순서의 처음이고, 스타터 지급이 "연 카테고리"를 외래키로 참조하기 때문.
	 */
	@Transactional
	public void startProfile(long userId, List<String> categoryCodes) {
		habits.createHabitUser(userId);
		categoryCodes.forEach(code -> habits.openCategory(userId, code, "INITIAL"));
	}

	/** 습관 등록 (기간 1번째, 시작일 {@code startedOn}). 새 습관 id. */
	@Transactional
	public long addHabit(long userId, String categoryCode, int measureTypeId, String name, BigDecimal dailyTarget,
			String periodCode, LocalDate startedOn) {
		long id = habits.insertHabit(userId, categoryCode, measureTypeId, name);
		habits.insertPeriod(id, 1, periodCode, config.periodDays().get(periodCode), dailyTarget, startedOn);
		return id;
	}

	/** 기간 코드가 올바른지 (D7 · D30 · D100 — 설정 {@code period_days}의 키). */
	public boolean isPeriodCode(String code) {
		return code != null && config.periodDays().containsKey(code);
	}

	@Transactional
	public void clearPersonalText(long userId) {
		habits.clearNames(userId);
	}

	// ---------- 조회 (3-2) ----------
	/** {@code GET /habits} 한 줄. 기간 · 목표값은 마지막 기간(연장하면 새 기간) 기준. */
	public record HabitView(long habitId, String categoryCode, String name, int measureTypeId, String unit,
			Number dailyTarget, String periodCode, LocalDate startDate, int filledDays, int periodDays, String status) {
	}

	/** 오늘 요약의 습관 한 줄. 체크인 전이면 보상 필드({@code rewarded*} · {@code counted})가 null. */
	public record TodayHabit(long habitId, String name, String categoryCode, String unit, Number dailyTarget,
			Number rewardedValue, Integer rewardedScore, Boolean counted, int filledDays, int periodDays) {
	}

	/**
	 * 오늘 체크인 요약 (보상 기준 = 첫 제출 값). 체크인 전이면 {@code checkinId} · {@code overallRate}가 null.
	 * {@code periodsEnded}는 이 체크인으로 채워진 기간 — 오늘 받은 골드(기간 보너스)를 지갑에서 찾을 때 쓴다.
	 */
	public record TodayCheckin(Long checkinId, Integer overallRate, List<TodayHabit> habits, List<Long> periodsEnded) {
	}

	public static final Set<String> DEFAULT_STATUSES = Set.of("ACTIVE", "ENDED");
	private static final Set<String> ALL_STATUSES = Set.of("ACTIVE", "ENDED", "STOPPED");

	public static boolean isStatus(String s) {
		return ALL_STATUSES.contains(s);
	}

	@Transactional(readOnly = true)
	public List<HabitView> habits(long userId, Set<String> statuses) {
		return habits.habits(userId, statuses).stream()
			.map(h -> new HabitView(h.habitId(), h.categoryCode(), h.name(), h.measureTypeId(), h.unit(),
					Decimals.plain(h.dailyTarget()), h.periodCode(), h.startDate(), h.filledDays(), h.periodDays(), h.status()))
			.toList();
	}

	/** 기간을 채워 연장 · 그만두기를 기다리는 습관 수. */
	@Transactional(readOnly = true)
	public int endedHabitCount(long userId) {
		return habits.countByStatus(userId, "ENDED");
	}

	@Transactional(readOnly = true)
	public boolean checkedInToday(long userId) {
		return habits.checkin(userId, dates.today()).isPresent();
	}

	@Transactional(readOnly = true)
	public TodayCheckin today(long userId) {
		LocalDate today = dates.today();
		var checkin = habits.checkin(userId, today);
		if (checkin.isEmpty()) {
			List<TodayHabit> targets = habits.checkinTargets(userId, today).stream()
				.map(h -> new TodayHabit(h.habitId(), h.name(), h.categoryCode(), h.unit(), Decimals.plain(h.dailyTarget()),
						null, null, null, h.filledDays(), h.periodDays()))
				.toList();
			return new TodayCheckin(null, null, targets, List.of());
		}
		var rows = habits.checkedHabits(checkin.get().id());
		List<TodayHabit> list = rows.stream()
			.map(h -> new TodayHabit(h.habitId(), h.name(), h.categoryCode(), h.unit(), Decimals.plain(h.targetSnapshot()),
					Decimals.plain(h.rewardedValue()), h.rewardedScore(), h.isCounted(), h.filledDays(), h.periodDays()))
			.toList();
		List<Long> ended = rows.stream().filter(h -> today.equals(h.endedOn())).map(h -> h.periodId()).toList();
		return new TodayCheckin(checkin.get().id(), overallRate(list), list, ended);
	}

	/**
	 * 전체 성실도 (API 명세 v5 4-1): 반영된(점수 상위 N개) 습관의 달성률 평균, 반올림.
	 * 달성률 = min(점수 ÷ 목표 달성 점수, 1) × 100 — 반올림한 점수로 계산한다.
	 */
	int overallRate(List<TodayHabit> list) {
		List<Integer> counted = list.stream().filter(h -> Boolean.TRUE.equals(h.counted())).map(TodayHabit::rewardedScore)
			.toList();
		if (counted.isEmpty()) {
			return 0;
		}
		double hit = config.scoreTargetHit();
		double sum = counted.stream().mapToDouble(s -> Math.min(s / hit, 1.0) * 100).sum();
		return (int) Math.round(sum / counted.size());
	}

	// ---------- 출석 ----------
	/**
	 * 오늘 출석 (앱을 켜거나 돌아올 때 자동). 하루에 여러 번 불러도 출석 행은 1개다.
	 * 처음이면 어제 출석했을 때만 연속 일수를 이어 가고, 아니면 1부터 다시 센다.
	 */
	@Transactional
	public Attendance attend(long userId) {
		LocalDate today = dates.today();
		StreakRow row = habits.lockHabitUser(userId).orElseThrow(() -> new IllegalStateException("습관 프로필 없음"));
		if (!habits.insertAttendance(userId, today)) {
			return new Attendance(today, true, displayStreak(row, today), row.longestStreak());
		}
		boolean continued = today.minusDays(1).equals(row.lastAttendedDate());
		int current = continued ? row.currentStreak() + 1 : 1;
		int longest = Math.max(row.longestStreak(), current);
		habits.updateStreak(userId, current, longest, today);
		return new Attendance(today, false, current, longest);
	}

	/** 화면에 보일 연속 출석: 마지막 출석이 어제보다 이전이면 끊긴 것이라 0 (schema 주석). */
	@Transactional(readOnly = true)
	public int currentStreak(long userId) {
		return habits.streak(userId).map(r -> displayStreak(r, dates.today())).orElse(0);
	}

	private static int displayStreak(StreakRow r, LocalDate today) {
		LocalDate last = r.lastAttendedDate();
		return last != null && !last.isBefore(today.minusDays(1)) ? r.currentStreak() : 0;
	}
}
