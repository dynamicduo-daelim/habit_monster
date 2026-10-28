package kr.habitmonster.stats;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.habit.HabitService;
import kr.habitmonster.habit.HabitService.CategoryProgress;
import kr.habitmonster.habit.HabitService.Streak;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 통계 (API 명세 v5 "6. 통계", 4-4) — 습관 모듈의 출석 · 체크인 · 카테고리 값을 화면 모양으로 모으는 조율 서비스. 자기 테이블은 없다.
 * 카테고리 경험치 이름은 명세의 {@code expToNextLevel} 대신 {@code expRequired} (결정 B2, 체크인 응답과 같은 뜻).
 */
@Service
public class StatsService {

	static final int ATTENDANCE_DAYS = 14;
	static final int SINCERITY_DAYS = 7;

	public record Day(LocalDate date, boolean attended) {
	}

	public record Attendance(int currentStreak, int longestStreak, List<Day> last14Days) {
	}

	/** {@code rate}는 체크인하지 않은 날 null. */
	public record DayRate(LocalDate date, String dayOfWeek, Integer rate) {
	}

	/** {@code averageRate}는 체크인한 날만의 평균 (하루도 없으면 null). */
	public record Sincerity(List<DayRate> last7Days, Integer averageRate) {
	}

	/** 카테고리 한 줄 — 연 카테고리({@link OpenedCategory})와 잠긴 카테고리({@link LockedCategory})의 모양이 다르다. */
	public sealed interface CategoryStat permits OpenedCategory, LockedCategory {
	}

	/** 최대 레벨이면 {@code expRequired}가 null. */
	public record OpenedCategory(String code, String name, boolean opened, int level, int maxLevel, int expInLevel,
			Integer expRequired, int levelUpGold) implements CategoryStat {
	}

	/** 잠긴 카테고리는 레벨 필드가 없다. */
	public record LockedCategory(String code, String name, boolean opened) implements CategoryStat {
	}

	/** {@code GET /stats}. */
	public record Stats(Attendance attendance, Sincerity sincerity, List<CategoryStat> categories) {
	}

	private final HabitService habits;
	private final BusinessDates dates;
	private final BalanceConfig config;

	StatsService(HabitService habits, BusinessDates dates, BalanceConfig config) {
		this.habits = habits;
		this.dates = dates;
		this.config = config;
	}

	@Transactional(readOnly = true)
	public Stats stats(long userId) {
		LocalDate today = dates.today();

		LocalDate from14 = today.minusDays(ATTENDANCE_DAYS - 1L);
		List<LocalDate> attended = habits.attendedDays(userId, from14, today);
		List<Day> days = new ArrayList<>();
		for (LocalDate d = from14; !d.isAfter(today); d = d.plusDays(1)) {
			days.add(new Day(d, attended.contains(d)));
		}
		Streak streak = habits.streak(userId);

		LocalDate from7 = today.minusDays(SINCERITY_DAYS - 1L);
		Map<LocalDate, Integer> rates = habits.dailyRates(userId, from7, today);
		List<DayRate> week = new ArrayList<>();
		for (LocalDate d = from7; !d.isAfter(today); d = d.plusDays(1)) {
			week.add(new DayRate(d, d.getDayOfWeek().name().substring(0, 3), rates.get(d)));
		}
		List<Integer> done = week.stream().map(DayRate::rate).filter(Objects::nonNull).toList();
		Integer average = done.isEmpty() ? null
				: (int) Math.round(done.stream().mapToInt(Integer::intValue).average().orElseThrow());

		Map<String, CategoryProgress> progress = habits.categoryProgress(userId);
		List<CategoryStat> categories = habits.categories().stream().<CategoryStat>map(c -> {
			CategoryProgress p = progress.get(c.code());
			return p == null ? new LockedCategory(c.code(), c.name(), false)
					: new OpenedCategory(c.code(), c.name(), true, p.level(), config.categoryMaxLevel(), p.expInLevel(),
							p.expRequired(), config.levelupGold());
		}).toList();

		return new Stats(new Attendance(streak.current(), streak.longest(), days), new Sincerity(week, average), categories);
	}
}
