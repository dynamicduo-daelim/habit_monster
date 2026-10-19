package kr.habitmonster.home;

import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;

import kr.habitmonster.auth.AuthService;
import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.habit.HabitService;
import kr.habitmonster.habit.HabitService.TodayCheckin;
import kr.habitmonster.habit.HabitService.TodayHabit;
import kr.habitmonster.monster.MonsterService;
import kr.habitmonster.monster.MonsterService.ExploreQuota;
import kr.habitmonster.shop.ShopService;
import kr.habitmonster.wallet.WalletService;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 메인 화면 조회 (API 명세 v5 "3. 상단 바 · 메인 화면") — 여러 모듈(습관 · 지갑 · 상점 · 몬스터)의 값을 모으는 **조회 전용** 서비스.
 * 자기 테이블은 없고, 각 모듈 서비스의 읽기 메서드만 부른다 (모듈 규칙).
 */
@Service
public class StatusService {

	/**
	 * 상단 바. {@code dayCount}는 명세에 더한 값 — 온보딩한 날이 DAY 1 (결정 D-37).
	 * 체크인 전에는 탐색 남은/전체가 0 / 0.
	 */
	public record Status(LocalDate businessDate, int dayCount, int currentStreak, long gold, int ballCount,
			boolean checkedInToday, int exploreRemaining, int exploreTotal, int endedHabitCount) {
	}

	/** 오늘 요약 (보상 기준 = 첫 제출 값). 체크인 전이면 {@code goldEarned} · {@code overallRate}가 null. */
	public record Today(LocalDate businessDate, boolean checkedIn, Long goldEarned, Integer overallRate,
			List<TodayHabit> habits) {
	}

	private final AuthService auth;
	private final HabitService habits;
	private final WalletService wallet;
	private final ShopService shop;
	private final MonsterService monsters;
	private final BusinessDates dates;

	StatusService(AuthService auth, HabitService habits, WalletService wallet, ShopService shop, MonsterService monsters,
			BusinessDates dates) {
		this.auth = auth;
		this.habits = habits;
		this.wallet = wallet;
		this.shop = shop;
		this.monsters = monsters;
		this.dates = dates;
	}

	@Transactional(readOnly = true)
	public Status status(long userId) {
		LocalDate today = dates.today();
		ExploreQuota quota = monsters.exploreQuota(userId);
		return new Status(today, dayCount(userId, today), habits.currentStreak(userId), wallet.balance(userId),
				shop.quantity(userId, ShopService.BALL), habits.checkedInToday(userId), quota.remaining(), quota.total(),
				habits.endedHabitCount(userId));
	}

	@Transactional(readOnly = true)
	public Today today(long userId) {
		TodayCheckin t = habits.today(userId);
		Long gold = t.checkinId() == null ? null : wallet.checkinGold(userId, t.checkinId(), t.periodsEnded());
		return new Today(dates.today(), t.checkinId() != null, gold, t.overallRate(), t.habits());
	}

	/** 온보딩한 업무 날짜부터 며칠째인지 (그날 = 1). */
	private int dayCount(long userId, LocalDate today) {
		Instant onboarded = auth.onboardedAt(userId);
		return onboarded == null ? 0 : (int) ChronoUnit.DAYS.between(dates.dateOf(onboarded), today) + 1;
	}
}
