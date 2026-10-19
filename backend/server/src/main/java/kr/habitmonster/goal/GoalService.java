package kr.habitmonster.goal;

import java.time.LocalDate;
import java.util.List;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.goal.GoalRepository.GoalRow;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 목표 모듈 — 주간(월요일 시작) · 월간(1일 시작) 목표. */
@Service
public class GoalService {

	public enum GoalType { WEEKLY, MONTHLY }

	public record GoalView(long goalId, String title, String detail, String status) {
	}

	/** 한 기간(이번 주 · 이번 달)의 목표와 칸. {@code slotsUsed}는 완료한 목표도 센다 (삭제한 것만 빠짐). */
	public record Period(LocalDate periodStart, int slotsTotal, int slotsUsed, int rewardGold, List<GoalView> goals) {
	}

	/** {@code GET /goals} 응답. */
	public record CurrentGoals(Period weekly, Period monthly) {
	}

	private final GoalRepository goals;
	private final BusinessDates dates;
	private final BalanceConfig config;

	GoalService(GoalRepository goals, BusinessDates dates, BalanceConfig config) {
		this.goals = goals;
		this.dates = dates;
		this.config = config;
	}

	/** 이번 주 · 이번 달 목표 (명세 8장 — 지난 기간 목표는 안 보낸다). */
	@Transactional(readOnly = true)
	public CurrentGoals current(long userId) {
		int weeklySlots = config.weeklyGoalSlots() + goals.extraWeeklySlots(userId);
		return new CurrentGoals(
				period(userId, GoalType.WEEKLY, dates.weekStart(), weeklySlots, config.weeklyGoalGold()),
				period(userId, GoalType.MONTHLY, dates.monthStart(), config.monthlyGoalSlots(), config.monthlyGoalGold()));
	}

	private Period period(long userId, GoalType type, LocalDate start, int slots, int gold) {
		List<GoalRow> rows = goals.goals(userId, type.name(), start);
		return new Period(start, slots, rows.size(), gold,
				rows.stream().map(g -> new GoalView(g.goalId(), g.title(), g.detail(), g.status())).toList());
	}

	/** 온보딩: 목표 프로필(사용자 잠금 행)을 만든다. */
	@Transactional
	public void startProfile(long userId) {
		goals.createGoalUser(userId);
	}

	/** 이번 주 / 이번 달 목표를 등록한다. 새 목표 id. 개수 검사는 부르는 쪽 (온보딩 · {@code POST /goals}). */
	@Transactional
	public long addGoal(long userId, GoalType type, String title, String detail) {
		LocalDate start = type == GoalType.WEEKLY ? dates.weekStart() : dates.monthStart();
		return goals.insertGoal(userId, type.name(), start, title, detail);
	}

	@Transactional
	public void clearPersonalText(long userId) {
		goals.clearTexts(userId);
	}
}
