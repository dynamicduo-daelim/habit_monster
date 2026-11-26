package kr.habitmonster.quest;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.annotation.JsonInclude;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.habit.HabitService;
import kr.habitmonster.habit.HabitService.PeriodRecord;
import kr.habitmonster.habit.TimerService;
import kr.habitmonster.quest.QuestRepository.Advanced;
import kr.habitmonster.quest.QuestRepository.QuestRow;
import kr.habitmonster.wallet.LedgerReason;
import kr.habitmonster.wallet.WalletService;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 퀘스트 (API 명세 v8 · v9 10장, 기획 {@code docs/기획/2026-11-12-퀘스트-시스템.md}, 단계 {@code docs/quest/}).
 *
 * <ul>
 * <li>진행은 다른 모듈의 이벤트로 오른다 ({@link QuestListener}, 같은 트랜잭션 — 결정 D-85).
 * 일일은 이벤트마다 +1, 주간은 이번 주 기록에서 다시 계산한다 (D-88 — "서로 다른 카테고리 수"처럼 +1로 셀 수 없는 것이 있고,
 * 퀘스트를 중간에 켜도 그 주 앞부분이 반영되게)</li>
 * <li>기간마다 첫 조회 또는 첫 이벤트 때 행을 만든다 — 스케줄러 없음 (D-64)</li>
 * <li>잠금은 저장하지 않고 그때그때 계산한다 — 하루 중간에 조건을 갖추면 바로 풀린다</li>
 * <li>목표에 닿는 순간 골드를 자동 지급 (지갑 모듈, 원장 {@code QUEST_DAILY} · {@code QUEST_WEEKLY}, ref = {@code user_quest.id})</li>
 * <li><b>항상 지갑을 먼저 잠근다</b> — 사용자 잠금 순서 {@code … → wallet → quest} (D-87)</li>
 * </ul>
 */
@Service
public class QuestService {

	static final String DAILY = "DAILY";
	static final String WEEKLY = "WEEKLY";
	static final String DAILY_CHECKIN = "DAILY_CHECKIN";
	static final String DAILY_PET = "DAILY_PET";
	static final String DAILY_TIMER = "DAILY_TIMER";
	static final String DAILY_TALK = "DAILY_TALK";
	static final String WEEKLY_ATTEND = "WEEKLY_ATTEND";
	static final String WEEKLY_GOOD_DAYS = "WEEKLY_GOOD_DAYS";
	static final String WEEKLY_CATEGORIES = "WEEKLY_CATEGORIES";
	static final String NO_TIMER_HABIT = "NO_TIMER_HABIT";
	static final String NOT_ENOUGH_CATEGORIES = "NOT_ENOUGH_CATEGORIES";

	private static final Map<String, LedgerReason> REASON = Map.of(DAILY, LedgerReason.QUEST_DAILY, WEEKLY,
			LedgerReason.QUEST_WEEKLY);

	/** 퀘스트 한 칸. {@code lockReason}은 {@code LOCKED}일 때만 내보낸다. */
	public record QuestView(String code, String title, int progress, int target, int rewardGold, String status,
			@JsonInclude(JsonInclude.Include.NON_NULL) String lockReason) {
	}

	/** {@code GET /quests}. 깜짝 · 월간은 다음 단계에서 칸을 더한다. */
	public record Quests(LocalDate businessDate, boolean enabled, List<QuestView> daily, LocalDate weekStart,
			List<QuestView> weekly) {
	}

	private final QuestRepository quests;
	private final WalletService wallet;
	private final TimerService timers;
	private final HabitService habits;
	private final BalanceConfig config;
	private final BusinessDates dates;

	QuestService(QuestRepository quests, WalletService wallet, TimerService timers, HabitService habits,
			BalanceConfig config, BusinessDates dates) {
		this.quests = quests;
		this.wallet = wallet;
		this.timers = timers;
		this.habits = habits;
		this.config = config;
		this.dates = dates;
	}

	/** 오늘 · 이번 주 퀘스트. 주간은 조회 때도 기록에서 다시 계산하므로, 조회하다 완료 · 지급될 수 있다. */
	@Transactional
	public Quests today(long userId) {
		LocalDate today = dates.today();
		LocalDate week = dates.weekStart();
		if (!config.questEnabled()) {
			return new Quests(today, false, List.of(), week, List.of());
		}
		wallet.lock(userId); // D-87: 지갑 → 퀘스트
		quests.createMissing(userId, today, DAILY);
		syncWeekly(userId, today, week);
		return new Quests(today, true, views(userId, today, DAILY), week, views(userId, week, WEEKLY));
	}

	/**
	 * 오늘의 일일 퀘스트 하나를 +1 한다 ({@link QuestListener}가 부른다 — 부른 쪽 트랜잭션 안).
	 * 꺼져 있거나 · 오늘이 아닌 날의 일이거나(늦게 정리된 타이머 자동 종료) · 잠겨 있거나 · 이미 끝났으면 아무것도 안 한다.
	 */
	void progressDaily(long userId, LocalDate day, String questCode) {
		LocalDate today = dates.today();
		if (!config.questEnabled() || !today.equals(day)) {
			return;
		}
		wallet.lock(userId); // D-87
		quests.createMissing(userId, today, DAILY);
		if (lockReason(userId, questCode, "IN_PROGRESS", 0) != null) {
			return;
		}
		quests.advance(userId, today, questCode).ifPresent(a -> completeIfReached(userId, a, DAILY));
	}

	/** 이번 주 기록이 바뀌었을 때(출석 · 체크인 첫 제출) 주간 퀘스트를 다시 계산한다 ({@link QuestListener}). */
	void refreshWeekly(long userId, LocalDate day) {
		LocalDate today = dates.today();
		if (!config.questEnabled() || !today.equals(day)) {
			return;
		}
		wallet.lock(userId); // D-87
		syncWeekly(userId, today, dates.weekStart());
	}

	/**
	 * 이번 주(월요일 ~ 오늘) 기록에서 진행도를 계산해 맞춘다 — 내려가지 않고, 목표에 닿으면 완료 · 지급.
	 * 잠긴 퀘스트는 계산하지 않는다. 지갑을 잠근 뒤 부른다.
	 */
	private void syncWeekly(long userId, LocalDate today, LocalDate week) {
		quests.createMissing(userId, week, WEEKLY);
		PeriodRecord rec = habits.periodRecord(userId, week, today, config.questWeeklyRateThreshold());
		for (QuestRow q : quests.quests(userId, week, WEEKLY)) {
			if (!"IN_PROGRESS".equals(q.status()) || lockReason(userId, q.questCode(), q.status(), q.target()) != null) {
				continue;
			}
			int value = switch (q.questCode()) {
				case WEEKLY_ATTEND -> rec.attendedDays();
				case WEEKLY_GOOD_DAYS -> rec.goodDays();
				case WEEKLY_CATEGORIES -> rec.filledCategories();
				default -> 0;
			};
			quests.raise(userId, week, q.questCode(), value).ifPresent(a -> completeIfReached(userId, a, WEEKLY));
		}
	}

	/** 목표에 닿았으면 조건부로 완료하고(한 번만 성공) 그 행의 보상을 지급한다. */
	private void completeIfReached(long userId, Advanced a, String kind) {
		if (a.progress() < a.target()) {
			return;
		}
		quests.complete(a.id()).ifPresent(gold -> wallet.credit(userId, gold, REASON.get(kind), String.valueOf(a.id())));
	}

	private List<QuestView> views(long userId, LocalDate period, String kind) {
		return quests.quests(userId, period, kind).stream().map(q -> {
			String lock = lockReason(userId, q.questCode(), q.status(), q.target());
			return new QuestView(q.questCode(), q.title(), q.progress(), q.target(), q.rewardGold(),
					lock != null ? "LOCKED" : q.status(), lock);
		}).toList();
	}

	/**
	 * 잠금 이유 — 이미 끝난 퀘스트는 잠그지 않는다 (완료한 뒤 조건이 바뀌어도 "완료"로 보인다).
	 * 타이머: 시간 습관이 없음. 카테고리: 연 카테고리가 목표 수보다 적음 (자동으로 목표를 낮추지 않음 — 기획 4-2).
	 */
	private String lockReason(long userId, String questCode, String status, int target) {
		if ("DONE".equals(status)) {
			return null;
		}
		if (DAILY_TIMER.equals(questCode) && !timers.hasTimerHabit(userId)) {
			return NO_TIMER_HABIT;
		}
		if (WEEKLY_CATEGORIES.equals(questCode) && habits.openedCategories(userId).size() < target) {
			return NOT_ENOUGH_CATEGORIES;
		}
		return null;
	}
}
