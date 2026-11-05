package kr.habitmonster.checkin;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.habit.HabitService;
import kr.habitmonster.habit.HabitService.Answer;
import kr.habitmonster.habit.HabitService.Board;
import kr.habitmonster.habit.HabitService.CategoryGain;
import kr.habitmonster.habit.HabitService.FirstCheckin;
import kr.habitmonster.habit.HabitService.PeriodBonus;
import kr.habitmonster.habit.HabitService.Revision;
import kr.habitmonster.habit.HabitService.ScoredHabit;
import kr.habitmonster.habit.HabitService.Tab;
import kr.habitmonster.monster.MonsterService;
import kr.habitmonster.monster.MonsterService.Partner;
import kr.habitmonster.monster.MonsterService.UnlockedSpecies;
import kr.habitmonster.wallet.LedgerReason;
import kr.habitmonster.wallet.WalletService;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 체크인 (API 명세 v5 "5. 챗봇 — 체크인") — 습관 · 몬스터 · 지갑 모듈을 차례로 부르는 조율 서비스. 자기 테이블은 없다.
 *
 * <p>첫 제출은 한 트랜잭션이고, 부르는 순서는 사용자 잠금 순서와 같다: 습관(점수 · 기록 · 경험치 · 기간) → 몬스터(탐색 기회) → 지갑(골드).
 * 보상은 모두 첫 제출 기준이고, 다시 체크(PUT)는 최신 값 · 점수만 바꾼다.
 */
@Service
public class CheckinService {

	public record CheckinRequest(LocalDate businessDate, List<Answer> answers) {
	}

	/** {@code GET /checkins/today}. 대화 상대가 없으면 {@code partner}가 null. */
	public record TodayCheckin(LocalDate businessDate, boolean submitted, int revision, Partner partner, List<Tab> tabs) {
	}

	public record GoldBreakdown(int score, int levelUp, int periodBonus) {
	}

	/** {@code categoryExp} 한 줄 = 명세 필드 + {@code expInLevel} · {@code expRequired}(추가, B2 이름). */
	public record CategoryExp(String categoryCode, int expGained, int levelBefore, int levelAfter, int levelUpGold,
			int expInLevel, Integer expRequired) {
	}

	public record PeriodBonusView(long habitId, String periodCode, double multiplier, int periodScore, int bonusGold) {
	}

	/** {@code POST /checkins/today} 응답 (명세 예시 그대로 + {@code categoryExp}의 추가 필드). */
	public record Submitted(int revision, List<ScoredHabit> habits, int overallRate, int goldEarned,
			GoldBreakdown goldBreakdown, List<CategoryExp> categoryExp, List<PeriodBonusView> periodBonuses,
			List<UnlockedSpecies> unlockedSpecies, int exploreTotal, long gold) {
	}

	private final HabitService habits;
	private final MonsterService monsters;
	private final WalletService wallet;
	private final BalanceConfig config;
	private final BusinessDates dates;

	CheckinService(HabitService habits, MonsterService monsters, WalletService wallet, BalanceConfig config,
			BusinessDates dates) {
		this.habits = habits;
		this.monsters = monsters;
		this.wallet = wallet;
		this.config = config;
		this.dates = dates;
	}

	/** 쓰기 트랜잭션 — 습관 모듈이 타이머 자동 종료 정리를 먼저 한다 (명세 v6 5장 {@code timerMinutes}). */
	@Transactional
	public TodayCheckin today(long userId) {
		Board board = habits.board(userId);
		return new TodayCheckin(dates.today(), board.submitted(), board.revision(), monsters.partner(userId).orElse(null),
				board.tabs());
	}

	@Transactional
	public Submitted submit(long userId, UUID key, CheckinRequest req) {
		LocalDate today = dates.requireToday(req.businessDate()); // ⑤ 업무 날짜 (다르면 409)
		FirstCheckin c = habits.submitFirst(userId, today, key, req.answers());

		// 탐색 기회: 전부 "못했어"면 1, 아니면 3. 후보는 연 카테고리 전부 (B4)
		int exploreTotal = c.allMissed() ? config.exploreDailyAllMissed() : config.exploreDailyFree();
		monsters.openExploreQuota(userId, today, exploreTotal, c.checkinId(), habits.openedCategories(userId));

		List<CategoryExp> categoryExp = new ArrayList<>();
		List<UnlockedSpecies> unlocked = new ArrayList<>();
		for (CategoryGain g : c.categories()) {
			int levelUpGold = (g.levelAfter() - g.levelBefore()) * config.levelupGold();
			categoryExp.add(new CategoryExp(g.categoryCode(), g.expGained(), g.levelBefore(), g.levelAfter(), levelUpGold,
					g.expInLevel(), g.expRequired()));
			unlocked.addAll(monsters.unlockedBetween(g.categoryCode(), g.levelBefore(), g.levelAfter()));
		}

		// 골드는 지갑으로만 (잠금 순서의 마지막). 0원은 원장에 쓰지 않고, 같은 (사유, ref)는 한 번만
		int scoreGold = c.countedScore() * config.goldPerScore();
		long balance = wallet.credit(userId, scoreGold, LedgerReason.CHECKIN, String.valueOf(c.checkinId())).balance();
		int levelUpGold = 0;
		for (CategoryExp e : categoryExp) {
			levelUpGold += e.levelUpGold();
			balance = wallet.credit(userId, e.levelUpGold(), LedgerReason.LEVELUP, c.checkinId() + ":" + e.categoryCode())
				.balance();
		}
		int periodGold = 0;
		List<PeriodBonusView> bonuses = new ArrayList<>();
		for (PeriodBonus b : c.periodBonuses()) {
			periodGold += b.bonusGold();
			balance = wallet.credit(userId, b.bonusGold(), LedgerReason.PERIOD_BONUS, String.valueOf(b.periodId())).balance();
			bonuses.add(new PeriodBonusView(b.habitId(), b.periodCode(), b.multiplier(), b.periodScore(), b.bonusGold()));
		}

		return new Submitted(c.revision(), c.habits(), c.overallRate(), scoreGold + levelUpGold + periodGold,
				new GoldBreakdown(scoreGold, levelUpGold, periodGold), categoryExp, bonuses, unlocked, exploreTotal, balance);
	}

	@Transactional
	public Revision resubmit(long userId, UUID key, CheckinRequest req) {
		LocalDate today = dates.requireToday(req.businessDate());
		return habits.resubmit(userId, today, key, req.answers());
	}
}
