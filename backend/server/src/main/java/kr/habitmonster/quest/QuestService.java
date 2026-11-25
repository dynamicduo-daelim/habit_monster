package kr.habitmonster.quest;

import java.time.LocalDate;
import java.util.List;

import com.fasterxml.jackson.annotation.JsonInclude;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.habit.TimerService;
import kr.habitmonster.wallet.LedgerReason;
import kr.habitmonster.wallet.WalletService;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 퀘스트 (API 명세 v8 10장, 기획 {@code docs/기획/2026-11-12-퀘스트-시스템.md}, 단계 {@code docs/quest/}).
 *
 * <ul>
 * <li>진행은 다른 모듈의 이벤트로만 오른다 ({@link QuestListener}, 같은 트랜잭션 — 결정 D-85)</li>
 * <li>기간마다 첫 조회 또는 첫 이벤트 때 행을 만든다 — 스케줄러 없음 (D-64)</li>
 * <li>잠금은 저장하지 않고 그때그때 계산한다 — 하루 중간에 시간 습관을 등록하면 바로 풀린다</li>
 * <li>목표에 닿는 순간 골드를 자동 지급 (지갑 모듈, 원장 {@code QUEST_DAILY}, ref = {@code user_quest.id})</li>
 * <li><b>항상 지갑을 먼저 잠근다</b> — 사용자 잠금 순서 {@code … → wallet → quest} (D-87). 체크인처럼 이미 지갑을 잠근 뒤
 * 이벤트가 오는 경로와 쓰다듬기처럼 지갑을 안 잠근 경로가 같은 순서가 되어 교착이 생기지 않는다</li>
 * </ul>
 */
@Service
public class QuestService {

	static final String DAILY = "DAILY";
	static final String DAILY_CHECKIN = "DAILY_CHECKIN";
	static final String DAILY_PET = "DAILY_PET";
	static final String DAILY_TIMER = "DAILY_TIMER";
	static final String DAILY_TALK = "DAILY_TALK";
	static final String NO_TIMER_HABIT = "NO_TIMER_HABIT";

	/** 퀘스트 한 칸. {@code lockReason}은 {@code LOCKED}일 때만 내보낸다. */
	public record QuestView(String code, String title, int progress, int target, int rewardGold, String status,
			@JsonInclude(JsonInclude.Include.NON_NULL) String lockReason) {
	}

	/** {@code GET /quests}. 주간 · 깜짝 · 월간은 다음 단계에서 칸을 더한다. */
	public record Quests(LocalDate businessDate, boolean enabled, List<QuestView> daily) {
	}

	private final QuestRepository quests;
	private final WalletService wallet;
	private final TimerService timers;
	private final BalanceConfig config;
	private final BusinessDates dates;

	QuestService(QuestRepository quests, WalletService wallet, TimerService timers, BalanceConfig config,
			BusinessDates dates) {
		this.quests = quests;
		this.wallet = wallet;
		this.timers = timers;
		this.config = config;
		this.dates = dates;
	}

	@Transactional
	public Quests today(long userId) {
		LocalDate today = dates.today();
		if (!config.questEnabled()) {
			return new Quests(today, false, List.of());
		}
		wallet.lock(userId); // D-87: 지갑 → 퀘스트
		quests.createMissing(userId, today, DAILY);
		List<QuestView> daily = quests.quests(userId, today, DAILY).stream().map(q -> {
			String lock = lockReason(userId, q.questCode(), q.status());
			return new QuestView(q.questCode(), q.title(), q.progress(), q.target(), q.rewardGold(),
					lock != null ? "LOCKED" : q.status(), lock);
		}).toList();
		return new Quests(today, true, daily);
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
		wallet.lock(userId); // D-87: 지갑 → 퀘스트
		quests.createMissing(userId, today, DAILY);
		if (lockReason(userId, questCode, "IN_PROGRESS") != null) {
			return;
		}
		quests.advance(userId, today, questCode)
			.filter(a -> a.progress() >= a.target())
			.flatMap(a -> quests.complete(a.id()).map(gold -> {
				wallet.credit(userId, gold, LedgerReason.QUEST_DAILY, String.valueOf(a.id()));
				return gold;
			}));
	}

	/** 잠금 이유 — 이미 끝난 퀘스트는 잠그지 않는다 (완료한 뒤 습관을 그만둬도 "완료"로 보인다). */
	private String lockReason(long userId, String questCode, String status) {
		if (DAILY_TIMER.equals(questCode) && !"DONE".equals(status) && !timers.hasTimerHabit(userId)) {
			return NO_TIMER_HABIT;
		}
		return null;
	}
}
