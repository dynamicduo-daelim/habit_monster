package kr.habitmonster.goal;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ApiExceptionHandler.FieldError;
import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.goal.GoalRepository.GoalRow;
import kr.habitmonster.wallet.LedgerReason;
import kr.habitmonster.wallet.WalletService;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 목표 모듈 — 주간 · 월간 목표 (API 명세 v5 8장 + 보충 10-28).
 * 기간은 달력 주 · 달이 아니라 <b>등록한 날부터</b> 주간 7일 · 월간 30일 (설정 {@code *_goal_days}).
 * 칸은 기간이 남은 목표(진행 중 · 완료)가 차지하고, 기간이 끝나거나 삭제하면 빈다 — 완료 즉시 비우면
 * "등록 → 다음 날 완료"를 반복해 골드를 계속 벌 수 있기 때문 (D-48).
 */
@Service
public class GoalService {

	public enum GoalType { WEEKLY, MONTHLY }

	static final int TITLE_MAX = 50;
	static final int DETAIL_MAX = 500;

	/** 목표 하나 = 등록 · 수정 응답, 목록의 한 줄. {@code periodEnd}는 기간 마지막 날 (그날까지 완료할 수 있다). */
	public record GoalView(long goalId, String goalType, LocalDate periodStart, LocalDate periodEnd, String title,
			String detail, String status) {
	}

	/** 한 종류(주간 · 월간)의 칸과 기간이 남은 목표. {@code slotsUsed} = 목표 수 (완료한 것도 센다). */
	public record Slots(int slotsTotal, int slotsUsed, int rewardGold, List<GoalView> goals) {
	}

	/** {@code GET /goals} 응답. */
	public record CurrentGoals(Slots weekly, Slots monthly) {
	}

	/** {@code POST /goals} 요청. */
	public record NewGoal(String goalType, String title, String detail) {
	}

	/** {@code POST /goals/{id}/complete} 응답. {@code gold}는 받은 뒤 잔액. */
	public record Completed(long goalId, String status, int goldAwarded, long gold) {
	}

	private final GoalRepository goals;
	private final BusinessDates dates;
	private final BalanceConfig config;
	private final WalletService wallet;

	GoalService(GoalRepository goals, BusinessDates dates, BalanceConfig config, WalletService wallet) {
		this.goals = goals;
		this.dates = dates;
		this.config = config;
		this.wallet = wallet;
	}

	/** 기간이 남은 목표 (명세 8장 — 끝난 목표 · 삭제한 목표는 안 보낸다). */
	@Transactional(readOnly = true)
	public CurrentGoals current(long userId) {
		LocalDate today = dates.today();
		return new CurrentGoals(slots(userId, GoalType.WEEKLY, today), slots(userId, GoalType.MONTHLY, today));
	}

	private Slots slots(long userId, GoalType type, LocalDate today) {
		List<GoalView> live = live(userId, type, today).stream().map(this::view).toList();
		return new Slots(slotsTotal(userId, type), live.size(), rewardGold(type), live);
	}

	/** 온보딩: 목표 프로필(사용자 잠금 행)을 만든다. */
	@Transactional
	public void startProfile(long userId) {
		goals.createGoalUser(userId);
	}

	/** 오늘부터 기간이 시작되는 목표를 등록한다. 새 목표 id. 개수 검사는 부르는 쪽 (온보딩 · {@link #create}). */
	@Transactional
	public long addGoal(long userId, GoalType type, String title, String detail) {
		return goals.insertGoal(userId, type.name(), dates.today(), title, detail);
	}

	/** 목표 등록 (4-2). 값 400 → 칸 422. */
	@Transactional
	public GoalView create(long userId, NewGoal req) {
		lock(userId); // 같은 사람의 등록이 동시에 와도 칸 수를 한 줄로 센다
		List<FieldError> errors = new ArrayList<>();
		GoalType type = type(req.goalType());
		if (type == null) {
			errors.add(new FieldError("goalType", "WEEKLY · MONTHLY 중 하나예요."));
		}
		String title = checkTitle(req.title(), errors);
		String detail = checkDetail(req.detail(), errors);
		throwIfAny(errors);

		LocalDate today = dates.today();
		if (live(userId, type, today).size() >= slotsTotal(userId, type)) {
			throw new ApiException(ErrorCode.GOAL_SLOT_FULL);
		}
		long id = goals.insertGoal(userId, type.name(), today, title, detail);
		return view(goals.goal(userId, id).orElseThrow());
	}

	/**
	 * 목표 수정 (4-2). 보낸 필드만 바꾼다 — 안 보냄과 {@code null}을 가르려고 본문을 Map으로 받는다.
	 * {@code detail: null}은 상세 지우기, {@code title: null}은 400, {@code goalType}은 바꿀 수 없어 400.
	 */
	@Transactional
	public GoalView update(long userId, long goalId, Map<String, Object> body) {
		lock(userId);
		GoalRow g = goals.goal(userId, goalId).orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND));
		List<FieldError> errors = new ArrayList<>();
		if (body.containsKey("goalType")) {
			errors.add(new FieldError("goalType", "목표 종류는 바꿀 수 없어요."));
		}
		String title = g.title();
		if (body.containsKey("title")) {
			title = body.get("title") instanceof String s ? checkTitle(s, errors) : checkTitle(null, errors);
		}
		String detail = g.detail();
		if (body.containsKey("detail")) {
			Object d = body.get("detail");
			if (d == null || d instanceof String) {
				detail = checkDetail((String) d, errors);
			} else {
				errors.add(new FieldError("detail", "상세는 글자로 보내 주세요."));
			}
		}
		throwIfAny(errors);
		checkChangeable(g);
		goals.updateTexts(goalId, title, detail);
		return view(goals.goal(userId, goalId).orElseThrow());
	}

	/** 목표 삭제 (4-2). 칸이 바로 빈다. */
	@Transactional
	public void delete(long userId, long goalId) {
		lock(userId);
		GoalRow g = goals.goal(userId, goalId).orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND));
		checkChangeable(g);
		goals.delete(goalId);
	}

	/** 목표 완료 (4-2). 보상 골드는 원장 {@code GOAL_WEEKLY} · {@code GOAL_MONTHLY}(ref = 목표 id)로 한 번만. */
	@Transactional
	public Completed complete(long userId, long goalId) {
		lock(userId);
		GoalRow g = goals.goal(userId, goalId).orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND));
		checkChangeable(g);
		if (g.periodStart().equals(dates.today())) {
			throw new ApiException(ErrorCode.GOAL_TOO_EARLY); // C1
		}
		goals.complete(goalId);
		GoalType type = GoalType.valueOf(g.goalType());
		int gold = rewardGold(type);
		LedgerReason reason = type == GoalType.WEEKLY ? LedgerReason.GOAL_WEEKLY : LedgerReason.GOAL_MONTHLY;
		long balance = wallet.credit(userId, gold, reason, String.valueOf(goalId)).balance();
		return new Completed(goalId, "COMPLETED", gold, balance);
	}

	@Transactional
	public void clearPersonalText(long userId) {
		goals.clearTexts(userId);
	}

	// ---------- 규칙 ----------
	private void lock(long userId) {
		goals.lockGoalUser(userId).orElseThrow(() -> new IllegalStateException("목표 프로필 없음: " + userId));
	}

	/** 완료한 목표 · 기간이 끝난 목표는 바꿀 수 없다 (명세 8장). */
	private void checkChangeable(GoalRow g) {
		if (g.status().equals("COMPLETED")) {
			throw new ApiException(ErrorCode.GOAL_COMPLETED);
		}
		if (periodEnd(g).isBefore(dates.today())) {
			throw new ApiException(ErrorCode.GOAL_PERIOD_ENDED);
		}
	}

	private List<GoalRow> live(long userId, GoalType type, LocalDate today) {
		return goals.liveGoals(userId, type.name(), today.minusDays(days(type) - 1L));
	}

	private int days(GoalType type) {
		return type == GoalType.WEEKLY ? config.weeklyGoalDays() : config.monthlyGoalDays();
	}

	private int slotsTotal(long userId, GoalType type) {
		return type == GoalType.WEEKLY ? config.weeklyGoalSlots() + goals.extraWeeklySlots(userId)
				: config.monthlyGoalSlots();
	}

	private int rewardGold(GoalType type) {
		return type == GoalType.WEEKLY ? config.weeklyGoalGold() : config.monthlyGoalGold();
	}

	private LocalDate periodEnd(GoalRow g) {
		return g.periodStart().plusDays(days(GoalType.valueOf(g.goalType())) - 1L);
	}

	private GoalView view(GoalRow g) {
		return new GoalView(g.goalId(), g.goalType(), g.periodStart(), periodEnd(g), g.title(), g.detail(), g.status());
	}

	private static GoalType type(String code) {
		for (GoalType t : GoalType.values()) {
			if (t.name().equals(code)) {
				return t;
			}
		}
		return null;
	}

	/** 제목: 앞뒤 공백을 뺀 1~50자. */
	private static String checkTitle(String raw, List<FieldError> errors) {
		String title = raw == null ? "" : raw.strip();
		int length = title.codePointCount(0, title.length());
		if (length < 1 || length > TITLE_MAX) {
			errors.add(new FieldError("title", "제목은 1~" + TITLE_MAX + "자예요."));
		}
		return title;
	}

	/** 상세: 0~500자. 비었거나 공백뿐이면 없음({@code null}) — 앱은 빈 칸을 {@code ""}로 보낸다. */
	private static String checkDetail(String raw, List<FieldError> errors) {
		if (raw == null || raw.isBlank()) {
			return null;
		}
		String detail = raw.strip();
		if (detail.codePointCount(0, detail.length()) > DETAIL_MAX) {
			errors.add(new FieldError("detail", "상세는 " + DETAIL_MAX + "자까지예요."));
		}
		return detail;
	}

	private static void throwIfAny(List<FieldError> errors) {
		if (!errors.isEmpty()) {
			throw new ApiException(ErrorCode.INVALID_REQUEST, ErrorCode.INVALID_REQUEST.message, errors);
		}
	}
}
