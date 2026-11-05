package kr.habitmonster.habit;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import com.fasterxml.jackson.annotation.JsonInclude;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ApiExceptionHandler.FieldError;
import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.common.Decimals;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.habit.HabitRepository.CategoryExpRow;
import kr.habitmonster.habit.HabitRepository.CategoryRow;
import kr.habitmonster.habit.HabitRepository.CheckinHabitRow;
import kr.habitmonster.habit.HabitRepository.DailyCheckinRow;
import kr.habitmonster.habit.HabitRepository.HabitRow;
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
	private final Scoring scoring;
	private final TimerService timers;

	HabitService(HabitRepository habits, BusinessDates dates, BalanceConfig config, Scoring scoring, TimerService timers) {
		this.habits = habits;
		this.dates = dates;
		this.config = config;
		this.scoring = scoring;
		this.timers = timers;
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
		return habits.habits(userId, statuses).stream().map(HabitService::view).toList();
	}

	private static HabitView view(HabitRow h) {
		return new HabitView(h.habitId(), h.categoryCode(), h.name(), h.measureTypeId(), h.unit(),
				Decimals.plain(h.dailyTarget()), h.periodCode(), h.startDate(), h.filledDays(), h.periodDays(), h.status());
	}

	// ---------- 추가 · 연장 · 그만두기 (4-1, API 명세 v5 4장) ----------
	/** {@code POST /habits} 요청. */
	public record NewHabit(String categoryCode, Integer measureTypeId, String name, BigDecimal dailyTarget,
			String periodCode) {
	}

	/** {@code POST /habits/{id}/renew} 요청. {@code dailyTarget}을 생략하면 이전 기간의 값. */
	public record Renewal(String periodCode, BigDecimal dailyTarget) {
	}

	/** {@code POST /habits/{id}/stop} 응답. */
	public record Stopped(long habitId, String status) {
	}

	static final int NAME_MAX = 30;

	/**
	 * 습관 추가 (홈 "내 습관"). 시작일은 오늘 체크인을 냈으면 내일, 아니면 오늘.
	 * 검사 순서: 값 형식 400 → 열지 않은 카테고리 422 {@code CATEGORY_LOCKED} → 칸이 꽉 참 422 {@code HABIT_LIMIT}.
	 * 칸 = 진행 중 + 기간 완료 (사용자 결정 10-23: 기간 완료도 칸을 차지해 연장 · 그만두기를 고르게 한다).
	 */
	@Transactional
	public HabitView create(long userId, NewHabit req) {
		lockProfile(userId); // 같은 사람의 추가 · 그만두기가 동시에 와도 칸 수를 한 줄로 센다
		Optional<MeasureTypeRow> measure = req.measureTypeId() == null ? Optional.empty()
				: habits.measureType(req.measureTypeId());
		List<FieldError> errors = new ArrayList<>();
		if (measure.isEmpty() || !measure.get().categoryCode().equals(req.categoryCode())) {
			errors.add(new FieldError("measureTypeId", "그 카테고리의 측정 항목이 아니에요."));
		}
		String name = req.name() == null ? "" : req.name().strip();
		int length = name.codePointCount(0, name.length());
		if (length < 1 || length > NAME_MAX) {
			errors.add(new FieldError("name", "이름은 1~" + NAME_MAX + "자예요."));
		}
		checkTarget(req.dailyTarget(), measure.map(MeasureTypeRow::maxValue).orElse(null), errors);
		checkPeriod(req.periodCode(), errors);
		throwIfAny(errors);

		if (!habits.isOpened(userId, req.categoryCode())) {
			throw new ApiException(ErrorCode.CATEGORY_LOCKED);
		}
		if (habits.countOpen(userId) >= config.maxActiveHabits()) {
			throw new ApiException(ErrorCode.HABIT_LIMIT);
		}
		long id = addHabit(userId, req.categoryCode(), req.measureTypeId(), name, req.dailyTarget(), req.periodCode(),
				startDate(userId));
		return view(habits.habit(userId, id).orElseThrow());
	}

	/**
	 * 기간 연장: 기간 완료(ENDED) 습관에 새 기간(seq + 1)을 붙이고 진행 중으로. 채운 날은 0부터, 이전 기간 기록은 그대로.
	 * 칸 수는 그대로라 상한 검사가 없다. 남의 습관 404 → 값 형식 400 → 기간 완료가 아님 409 {@code HABIT_NOT_ENDED}.
	 */
	@Transactional
	public HabitView renew(long userId, long habitId, Renewal req) {
		lockProfile(userId);
		HabitRow h = habits.habit(userId, habitId).orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND));
		List<FieldError> errors = new ArrayList<>();
		checkPeriod(req.periodCode(), errors);
		if (req.dailyTarget() != null) {
			checkTarget(req.dailyTarget(), habits.measureType(h.measureTypeId()).orElseThrow().maxValue(), errors);
		}
		throwIfAny(errors);
		if (!"ENDED".equals(h.status())) {
			throw new ApiException(ErrorCode.HABIT_NOT_ENDED);
		}
		BigDecimal target = req.dailyTarget() == null ? h.dailyTarget() : req.dailyTarget();
		habits.insertPeriod(habitId, habits.lastSeq(habitId) + 1, req.periodCode(),
				config.periodDays().get(req.periodCode()), target, startDate(userId));
		habits.reopenHabit(habitId);
		return view(habits.habit(userId, habitId).orElseThrow());
	}

	/**
	 * 그만두기 (진행 중 · 기간 완료 모두). 이미 그만둠 409 {@code HABIT_ALREADY_STOPPED},
	 * 칸을 차지한 습관이 이것 하나면 422 {@code LAST_HABIT} (D-14 — 체크할 습관이 없으면 앱의 흐름이 끊긴다).
	 * 오늘 체크인을 낸 뒤라면 오늘의 다시 체크에는 남는다 (다시 체크 대상 = 첫 제출의 습관).
	 */
	@Transactional
	public Stopped stop(long userId, long habitId) {
		lockProfile(userId);
		HabitRow h = habits.habit(userId, habitId).orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND));
		if ("STOPPED".equals(h.status())) {
			throw new ApiException(ErrorCode.HABIT_ALREADY_STOPPED);
		}
		if (habits.countOpen(userId) <= 1) {
			throw new ApiException(ErrorCode.LAST_HABIT);
		}
		habits.stopHabit(habitId);
		timers.endForHabit(userId, habitId); // 도는 · 일시정지한 타이머도 함께 끝낸다 (명세 v6 4장 · 9장)
		return new Stopped(habitId, "STOPPED");
	}

	/** 시작일 규칙 (명세 4-2): 오늘 체크인을 냈으면 내일 — 제출한 체크인에 새 습관이 끼어들지 않게. */
	private LocalDate startDate(long userId) {
		LocalDate today = dates.today();
		return habits.checkin(userId, today).isPresent() ? today.plusDays(1) : today;
	}

	private static void checkTarget(BigDecimal target, BigDecimal max, List<FieldError> errors) {
		if (target == null || target.signum() <= 0 || (max != null && target.compareTo(max) > 0)) {
			errors.add(new FieldError("dailyTarget",
					max == null ? "0보다 커야 해요." : "0보다 크고 " + max.stripTrailingZeros().toPlainString() + " 이하여야 해요."));
		}
	}

	private void checkPeriod(String periodCode, List<FieldError> errors) {
		if (!isPeriodCode(periodCode)) {
			errors.add(new FieldError("periodCode", "D7 · D30 · D100 중 하나예요."));
		}
	}

	private static void throwIfAny(List<FieldError> errors) {
		if (!errors.isEmpty()) {
			throw new ApiException(ErrorCode.INVALID_REQUEST, ErrorCode.INVALID_REQUEST.message, errors);
		}
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

	// ---------- 체크인 (3-3, API 명세 v5 "5. 챗봇") ----------
	/**
	 * 체크인 답 하나. {@code done:false}("못했어")면 {@code value}는 보지 않고 0으로 저장한다.
	 * {@code evidence}(명세 v6): SHORT · DETAILED(자기보고, 없으면 SHORT). VERIFIED는 서버만 붙인다 — 보내면 400.
	 */
	public record Answer(Long habitId, Boolean done, BigDecimal value, String evidence) {
		public Answer(Long habitId, Boolean done, BigDecimal value) {
			this(habitId, done, value, null);
		}
	}

	/** 앱이 보낼 수 있는 근거 (명세 v6 5장). */
	static final Set<String> CLAIMABLE_EVIDENCE = Set.of("SHORT", "DETAILED");

	/** {@code GET /checkins/today}의 습관 한 줄. {@code previousValue}는 제출 후의 최신 값 (다시 체크할 때 미리 채움). */
	/** {@code timerMinutes}(명세 v6): 오늘 기록된 타이머 분. 타이머를 못 쓰는 습관은 null, 쓸 수 있는데 없으면 0. */
	public record BoardHabit(long habitId, String name, String unit, String scoringMode, List<Number> options,
			Number previousValue, int filledDays, int periodDays, Integer timerMinutes) {
	}

	/** 카테고리 탭 하나 (카테고리 순서, 안은 등록 순서). */
	public record Tab(String categoryCode, String categoryName, List<BoardHabit> habits) {
	}

	public record Board(boolean submitted, int revision, List<Tab> tabs) {
	}

	/** 첫 제출의 습관 한 줄 (명세 v6): 근거 · 상한에 걸렸는지 · 이 습관이 준 카테고리 경험치(반영 아니면 0). */
	public record ScoredHabit(long habitId, int score, boolean counted, String evidence, boolean scoreCapped, int expGained) {
	}

	/**
	 * 카테고리 경험치 변화. {@code expInLevel} · {@code expRequired}는 명세 예시에 없는 추가 필드 — 지금 레벨에서 모은 경험치와
	 * 그 레벨에 필요한 총량 (이름은 결정 B2). 최대 레벨이면 {@code expRequired}가 null.
	 */
	public record CategoryGain(String categoryCode, int expGained, int levelBefore, int levelAfter, int expInLevel,
			Integer expRequired) {
	}

	/** 이번 제출로 채운 기간. {@code bonusGold} = {@code periodScore × (배수 − 1)} 반올림. */
	public record PeriodBonus(long habitId, long periodId, String periodCode, double multiplier, int periodScore,
			int bonusGold) {
	}

	/** 첫 제출 결과 (골드 지급 · 탐색 기회는 부른 쪽이 이 값으로 한다). */
	public record FirstCheckin(long checkinId, int revision, List<ScoredHabit> habits, int overallRate,
			int countedScore, List<CategoryGain> categories, List<PeriodBonus> periodBonuses, boolean allMissed) {
	}

	public record RevisedHabit(long habitId, Number value, int score, String evidence, boolean scoreCapped) {
	}

	public record Revision(int revision, List<RevisedHabit> habits, int overallRate) {
	}

	/** AI 대화 해석에 넘길 오늘 습관 한 줄 (값으로 넘긴다 — {@code ai} 모듈은 습관 테이블을 읽지 않는다). */
	public record ChatHabit(long habitId, String name, String categoryName, String unit, String scoringMode, Number target,
			Number maxValue, List<Number> options, Integer timerMinutes) {
	}

	/**
	 * 오늘 대화로 체크할 습관 ({@link #board}와 같은 대상, 등록 순서). AI 해석(챗봇 대화)의 문맥 · 검사용.
	 * 오늘 타이머 분도 붙인다 (값 맞추기, 명세 v6) — 타이머 자동 종료 정리가 쓰기라 쓰기 트랜잭션.
	 */
	@Transactional
	public List<ChatHabit> chatHabits(long userId) {
		LocalDate today = dates.today();
		Map<Long, Integer> timed = timers.todayMinutes(userId);
		List<CheckinHabitRow> rows = habits.dailyCheckin(userId, today).map(c -> habits.submittedHabits(c.id()))
			.orElseGet(() -> habits.targetHabits(userId, today));
		return rows.stream().sorted(Comparator.comparingLong(CheckinHabitRow::habitId))
			.map(r -> new ChatHabit(r.habitId(), r.name(), r.categoryName(), r.unit(), r.scoringMode(),
					Decimals.plain(r.target()), r.maxValue() == null ? null : Decimals.plain(r.maxValue()),
					scoring.options(measure(r)).stream().map(Decimals::plain).toList(),
					TimerService.isTimerMeasure(r.unit(), r.scoringMode()) ? timed.getOrDefault(r.habitId(), 0) : null))
			.toList();
	}

	/**
	 * 오늘 체크인 화면: 제출 전이면 대상 습관, 제출 후면 제출에 들어간 습관(최신 값과 함께).
	 * 쓰기 트랜잭션 — 타이머 자동 종료 정리를 먼저 하고 오늘 타이머 분을 붙인다 (명세 v6 5장).
	 */
	@Transactional
	public Board board(long userId) {
		LocalDate today = dates.today();
		Map<Long, Integer> timed = timers.todayMinutes(userId);
		Optional<DailyCheckinRow> checkin = habits.dailyCheckin(userId, today);
		List<CheckinHabitRow> rows = checkin.map(c -> habits.submittedHabits(c.id()))
			.orElseGet(() -> habits.targetHabits(userId, today));
		Map<String, List<CheckinHabitRow>> byCategory = new LinkedHashMap<>();
		rows.stream().sorted(Comparator.comparingInt(CheckinHabitRow::categorySort))
			.forEach(r -> byCategory.computeIfAbsent(r.categoryCode(), k -> new ArrayList<>()).add(r));
		List<Tab> tabs = byCategory.values().stream()
			.map(list -> new Tab(list.get(0).categoryCode(), list.get(0).categoryName(), list.stream()
				.map(r -> new BoardHabit(r.habitId(), r.name(), r.unit(), r.scoringMode(),
						scoring.options(measure(r)).stream().map(Decimals::plain).toList(), Decimals.plain(r.value()),
						r.filledDays(), r.periodDays(),
						TimerService.isTimerMeasure(r.unit(), r.scoringMode()) ? timed.getOrDefault(r.habitId(), 0) : null))
				.toList()))
			.toList();
		return new Board(checkin.isPresent(), checkin.map(DailyCheckinRow::revision).orElse(0), tabs);
	}

	/**
	 * 첫 제출 (한 트랜잭션, 습관 프로필 잠금이 처음 — 잠금 순서). 점수 → 반영 습관(점수 상위 N개, 동점은 등록 순서) →
	 * 기록 → 카테고리 경험치 · 레벨 → 기간 채운 날 · 보너스(B1: 반영 여부와 상관없이 "했어"면 채운 날 +1).
	 *
	 * @throws ApiException 409 {@code ALREADY_SUBMITTED} · {@code NO_ACTIVE_HABIT}, 400 빠진 · 남의 습관, 선택지 밖 값
	 */
	@Transactional
	public FirstCheckin submitFirst(long userId, LocalDate today, UUID key, List<Answer> answers) {
		lockProfile(userId);
		if (habits.dailyCheckin(userId, today).isPresent()) {
			throw new ApiException(ErrorCode.ALREADY_SUBMITTED);
		}
		List<CheckinHabitRow> targets = habits.targetHabits(userId, today);
		if (targets.isEmpty()) {
			throw new ApiException(ErrorCode.NO_ACTIVE_HABIT);
		}
		Map<Long, String> claimed = new LinkedHashMap<>();
		Map<Long, BigDecimal> values = validate(targets, answers, claimed);
		Map<Long, String> evidence = judge(userId, targets, values, claimed);

		// 점수(자기보고는 상한 20)와 반영 습관: 점수 높은 순, 같으면 습관 id(등록 순서)가 작은 쪽
		Map<Long, Integer> scores = new LinkedHashMap<>();
		Set<Long> capped = new java.util.HashSet<>();
		for (CheckinHabitRow t : targets) {
			int raw = scoring.score(measure(t), values.get(t.habitId()));
			int score = scoring.cap(raw, isVerified(evidence.get(t.habitId())));
			if (score < raw) {
				capped.add(t.habitId());
			}
			scores.put(t.habitId(), score);
		}
		Set<Long> counted = targets.stream()
			.sorted(Comparator.comparingInt((CheckinHabitRow t) -> -scores.get(t.habitId())).thenComparingLong(CheckinHabitRow::habitId))
			.limit(config.dailyCountedHabits()).map(CheckinHabitRow::habitId).collect(Collectors.toSet());

		int total = scores.values().stream().mapToInt(Integer::intValue).sum();
		int countedScore = counted.stream().mapToInt(scores::get).sum();
		long checkinId = habits.insertDailyCheckin(userId, today, targets.size(), total, countedScore);
		if (!habits.insertSubmission(key, checkinId, 1)) {
			throw new ApiException(ErrorCode.IDEMPOTENCY_KEY_REUSED);
		}
		for (CheckinHabitRow t : targets) {
			habits.insertHabitCheckin(checkinId, t.habitId(), t.periodSeq(), values.get(t.habitId()), t.target(),
					scores.get(t.habitId()), counted.contains(t.habitId()), evidence.get(t.habitId()),
					capped.contains(t.habitId()));
		}

		// 카테고리 경험치: 반영 습관마다 점수 × 방식 계수 × (확인됨 1.2), 습관마다 반올림 (명세 v6 4-1)
		Map<Long, Integer> exp = new LinkedHashMap<>();
		targets.forEach(t -> exp.put(t.habitId(), counted.contains(t.habitId())
				? scoring.exp(scores.get(t.habitId()), t.scoringMode(), isVerified(evidence.get(t.habitId()))) : 0));
		List<CategoryGain> categories = addCategoryExp(userId, targets, exp, counted);
		List<PeriodBonus> bonuses = fillPeriods(userId, today, targets, values, scores, counted);

		List<ScoredHabit> scored = targets.stream()
			.map(t -> new ScoredHabit(t.habitId(), scores.get(t.habitId()), counted.contains(t.habitId()),
					evidence.get(t.habitId()), capped.contains(t.habitId()), exp.get(t.habitId())))
			.toList();
		int overall = scoring.overallRate(List.copyOf(scores.values()));
		boolean allMissed = values.values().stream().allMatch(v -> v.signum() == 0);
		return new FirstCheckin(checkinId, 1, scored, overall, countedScore, categories, bonuses, allMissed);
	}

	/**
	 * 다시 체크: 첫 제출에 들어간 습관 전체의 최신 값 · 점수만 바꾼다. 보상 · 경험치 · 채운 날 · 탐색은 첫 제출 그대로
	 * (DB 트리거가 보상 기준값 수정을 막는다).
	 *
	 * @throws ApiException 404 {@code CHECKIN_NOT_FOUND}(오늘 제출 없음), 400 빠진 습관 · 선택지 밖 값
	 */
	@Transactional
	public Revision resubmit(long userId, LocalDate today, UUID key, List<Answer> answers) {
		lockProfile(userId);
		DailyCheckinRow checkin = habits.dailyCheckin(userId, today)
			.orElseThrow(() -> new ApiException(ErrorCode.CHECKIN_NOT_FOUND));
		List<CheckinHabitRow> rows = habits.submittedHabits(checkin.id());
		Map<Long, String> claimed = new LinkedHashMap<>();
		Map<Long, BigDecimal> values = validate(rows, answers, claimed);
		Map<Long, String> evidence = judge(userId, rows, values, claimed);

		List<RevisedHabit> revised = new ArrayList<>();
		for (CheckinHabitRow r : rows) {
			BigDecimal v = values.get(r.habitId());
			int raw = scoring.score(measure(r), v);
			String e = evidence.get(r.habitId());
			int score = scoring.cap(raw, isVerified(e));
			habits.updateHabitCheckin(checkin.id(), r.habitId(), v, score, e, score < raw);
			revised.add(new RevisedHabit(r.habitId(), Decimals.plain(v), score, e, score < raw));
		}
		int revision = habits.reviseDailyCheckin(checkin.id(), revised.stream().mapToInt(RevisedHabit::score).sum());
		if (!habits.insertSubmission(key, checkin.id(), revision)) {
			throw new ApiException(ErrorCode.IDEMPOTENCY_KEY_REUSED);
		}
		return new Revision(revision, revised, scoring.overallRate(revised.stream().map(RevisedHabit::score).toList()));
	}

	/**
	 * 답 검사 (400 + 틀린 항목 전부): 대상 습관을 빠짐없이 · 한 번씩, 대상이 아닌 습관(남의 습관 · 없는 습관 포함)은 안 됨,
	 * {@code done}은 필수, {@code done:true}면 값이 선택지 중 하나. 습관 id → 저장할 값("못했어"는 0).
	 */
	private Map<Long, BigDecimal> validate(List<CheckinHabitRow> targets, List<Answer> answers, Map<Long, String> claimed) {
		Map<Long, CheckinHabitRow> byId = targets.stream().collect(Collectors.toMap(CheckinHabitRow::habitId, t -> t));
		Map<Long, BigDecimal> values = new LinkedHashMap<>();
		List<FieldError> errors = new ArrayList<>();
		List<Answer> list = answers == null ? List.of() : answers;
		for (int i = 0; i < list.size(); i++) {
			Answer a = list.get(i);
			String f = "answers[" + i + "]";
			if (a == null || a.habitId() == null) {
				errors.add(new FieldError(f + ".habitId", "습관을 확인해 주세요."));
				continue;
			}
			CheckinHabitRow t = byId.get(a.habitId());
			if (t == null) {
				errors.add(new FieldError(f + ".habitId", "오늘 체크인할 습관이 아니에요."));
				continue;
			}
			if (values.containsKey(a.habitId())) {
				errors.add(new FieldError(f + ".habitId", "같은 습관을 두 번 보냈어요."));
				continue;
			}
			if (a.done() == null) {
				errors.add(new FieldError(f + ".done", "했는지 알려 주세요."));
				continue;
			}
			if (a.done() && !scoring.accepts(measure(t), a.value())) {
				errors.add(new FieldError(f + ".value", "선택지 중에서 골라 주세요."));
				continue;
			}
			if (a.evidence() != null && !CLAIMABLE_EVIDENCE.contains(a.evidence())) {
				errors.add(new FieldError(f + ".evidence", "SHORT · DETAILED 중 하나예요."));
				continue;
			}
			values.put(a.habitId(), a.done() ? a.value() : BigDecimal.ZERO);
			claimed.put(a.habitId(), a.evidence() == null ? "SHORT" : a.evidence());
		}
		List<Long> missing = targets.stream().map(CheckinHabitRow::habitId)
			.filter(id -> list.stream().noneMatch(a -> a != null && id.equals(a.habitId()))).toList();
		if (!missing.isEmpty()) {
			errors.add(new FieldError("answers", "오늘 체크인할 습관을 모두 보내 주세요. 빠진 습관: " + missing));
		}
		if (!errors.isEmpty()) {
			throw new ApiException(ErrorCode.INVALID_REQUEST, ErrorCode.INVALID_REQUEST.message, errors);
		}
		return values;
	}

	/**
	 * 근거 판정 (명세 v6 5장): 분 단위 시간 습관에서 오늘 기록된(끝난) 타이머 분이 제출 값 이상이면 VERIFIED, 아니면 앱이 보낸
	 * 자기보고 근거 그대로. 확인된 기록보다 많이 적으면 그 습관 전체가 자기보고다 (확인된 만큼만 따로 인정하지 않음).
	 * 도는 · 일시정지한 타이머는 넣지 않는다. 부르는 쪽이 사용자 잠금을 잡고 있다.
	 */
	private Map<Long, String> judge(long userId, List<CheckinHabitRow> rows, Map<Long, BigDecimal> values,
			Map<Long, String> claimed) {
		Map<Long, Integer> timed = timers.todayMinutes(userId);
		Map<Long, String> evidence = new LinkedHashMap<>();
		for (CheckinHabitRow r : rows) {
			BigDecimal v = values.get(r.habitId());
			int minutes = timed.getOrDefault(r.habitId(), 0);
			boolean verified = TimerService.isTimerMeasure(r.unit(), r.scoringMode()) && v.signum() > 0 && minutes > 0
					&& v.compareTo(BigDecimal.valueOf(minutes)) <= 0;
			evidence.put(r.habitId(), verified ? "VERIFIED" : claimed.get(r.habitId()));
		}
		return evidence;
	}

	private static boolean isVerified(String evidence) {
		return "VERIFIED".equals(evidence);
	}

	/**
	 * 반영 습관의 경험치({@code exp} — 점수 × 계수, 반영 아니면 0)를 그 카테고리 경험치에. 레벨 N → N+1에 {@code category_exp_base × N}, 최대 {@code category_max_level},
	 * 한 번에 여러 레벨이 오를 수 있다. 반영 습관이 있는 카테고리만 돌려준다 (카테고리 순서).
	 */
	private List<CategoryGain> addCategoryExp(long userId, List<CheckinHabitRow> targets, Map<Long, Integer> habitExp,
			Set<Long> counted) {
		Map<String, Integer> gained = new LinkedHashMap<>();
		targets.stream().filter(t -> counted.contains(t.habitId()))
			.sorted(Comparator.comparingInt(CheckinHabitRow::categorySort))
			.forEach(t -> gained.merge(t.categoryCode(), habitExp.get(t.habitId()), Integer::sum));
		Map<String, CategoryExpRow> rows = habits.categoryExp(userId).stream()
			.collect(Collectors.toMap(CategoryExpRow::categoryCode, r -> r));
		List<CategoryGain> result = new ArrayList<>();
		gained.forEach((code, exp) -> {
			CategoryExpRow row = rows.get(code);
			int total = row.expTotal() + exp;
			int level = Math.max(row.level(), levelFor(total));
			habits.updateCategoryExp(userId, code, total, level);
			boolean max = level >= config.categoryMaxLevel();
			int inLevel = max ? 0 : total - expToReach(level);
			result.add(new CategoryGain(code, exp, row.level(), level, inLevel, max ? null : config.categoryExpBase() * level));
		});
		return result;
	}

	/** 누적 경험치 → 레벨 (최대 레벨까지). */
	private int levelFor(int expTotal) {
		int level = 1;
		while (level < config.categoryMaxLevel() && expTotal >= expToReach(level + 1)) {
			level++;
		}
		return level;
	}

	/** 레벨 L에 닿는 데 필요한 누적 경험치 = base × (1 + 2 + … + (L − 1)). */
	private int expToReach(int level) {
		return config.categoryExpBase() * level * (level - 1) / 2;
	}

	/**
	 * 기간 채운 날 · 반영 점수 합을 더하고, 채운 날이 기간에 닿으면 보너스를 정하고 습관을 ENDED로 (결정 B1).
	 * "했어"(값 > 0)면 반영 여부와 상관없이 채운 날 +1, 반영 습관이면 점수 합에 더한다.
	 */
	private List<PeriodBonus> fillPeriods(long userId, LocalDate today, List<CheckinHabitRow> targets, Map<Long, BigDecimal> values,
			Map<Long, Integer> scores, Set<Long> counted) {
		Map<String, Double> multipliers = config.periodMultiplier();
		List<PeriodBonus> bonuses = new ArrayList<>();
		for (CheckinHabitRow t : targets) {
			boolean filled = values.get(t.habitId()).signum() > 0;
			int sum = t.countedScoreSum() + (counted.contains(t.habitId()) ? scores.get(t.habitId()) : 0);
			int days = t.filledDays() + (filled ? 1 : 0);
			if (days < t.periodDays()) {
				habits.updatePeriod(t.periodId(), days, sum, null, null);
				continue;
			}
			double multiplier = multipliers.get(t.periodCode());
			int bonus = BigDecimal.valueOf(sum).multiply(BigDecimal.valueOf(multiplier).subtract(BigDecimal.ONE))
				.setScale(0, RoundingMode.HALF_UP).intValueExact();
			habits.updatePeriod(t.periodId(), days, sum, today, bonus);
			habits.endHabit(t.habitId());
			timers.endForHabit(userId, t.habitId()); // 기간을 채운 습관은 체크인 대상이 아니라 타이머도 끝낸다 (명세 v6 9장)
			bonuses.add(new PeriodBonus(t.habitId(), t.periodId(), t.periodCode(), multiplier, sum, bonus));
		}
		return bonuses;
	}

	private static Scoring.Measure measure(CheckinHabitRow r) {
		return new Scoring.Measure(r.scoringMode(), r.target(), r.step(), r.maxValue(), r.rangeBelow(), r.rangeAbove());
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

	// ---------- 통계 (4-4) ----------
	public record Streak(int current, int longest) {
	}

	/** 연속 출석(끊겼으면 0) · 최장 기록. */
	@Transactional(readOnly = true)
	public Streak streak(long userId) {
		LocalDate today = dates.today();
		return habits.streak(userId).map(r -> new Streak(displayStreak(r, today), r.longestStreak())).orElse(new Streak(0, 0));
	}

	@Transactional(readOnly = true)
	public List<LocalDate> attendedDays(long userId, LocalDate from, LocalDate to) {
		return habits.attendedDays(userId, from, to);
	}

	/**
	 * 날짜 → 그날 전체 성실도 % (최신 점수 = 다시 체크 반영, 다시 체크 응답의 {@code overallRate}와 같은 계산).
	 * 체크인하지 않은 날은 없다.
	 */
	@Transactional(readOnly = true)
	public Map<LocalDate, Integer> dailyRates(long userId, LocalDate from, LocalDate to) {
		return habits.dayScores(userId, from, to).stream()
			.collect(Collectors.groupingBy(HabitRepository.DayScoreRow::checkinDate,
					Collectors.collectingAndThen(Collectors.mapping(HabitRepository.DayScoreRow::score, Collectors.toList()),
							scoring::overallRate)));
	}

	/** 연 카테고리의 레벨 진행. {@code expRequired}는 그 레벨에 필요한 총량(B2), 최대 레벨이면 null · {@code expInLevel} 0. */
	public record CategoryProgress(int level, int expInLevel, Integer expRequired) {
	}

	@Transactional(readOnly = true)
	public Map<String, CategoryProgress> categoryProgress(long userId) {
		return habits.categoryExp(userId).stream().collect(Collectors.toMap(CategoryExpRow::categoryCode, r -> {
			boolean max = r.level() >= config.categoryMaxLevel();
			return new CategoryProgress(r.level(), max ? 0 : r.expTotal() - expToReach(r.level()),
					max ? null : config.categoryExpBase() * r.level());
		}));
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

	// ---------- 탐색 (3-4) ----------
	/**
	 * 사용자 잠금 (잠금 순서의 처음). 탐색 · 포획처럼 다른 모듈에 쓰는 요청도 먼저 이걸 잡아서,
	 * 같은 사람의 요청이 한 줄로 서고 모듈끼리 잠금 순서가 엇갈리지 않게 한다.
	 */
	@Transactional
	public void lockProfile(long userId) {
		habits.lockHabitUser(userId).orElseThrow(() -> new IllegalStateException("습관 프로필 없음: " + userId));
	}

	/** 연 카테고리 → 레벨 (탐색 후보 = 출현 레벨이 이 레벨 이하인 종). */
	@Transactional(readOnly = true)
	public Map<String, Integer> categoryLevels(long userId) {
		return habits.categoryExp(userId).stream().collect(Collectors.toMap(CategoryExpRow::categoryCode, CategoryExpRow::level));
	}

	/**
	 * 가진 종 수가 도감 기준값({@code dex_unlock_thresholds}, 5 · 10 · 15)에 닿았으면 카테고리 해금권 1장.
	 * 이번에 새로 줬으면 true — 같은 기준값은 DB가 한 번만 받게 한다.
	 */
	@Transactional
	public boolean grantUnlockTicket(long userId, int dexCount) {
		return config.dexUnlockThresholds().contains(dexCount) && habits.insertUnlockTicket(userId, dexCount);
	}

	/** 안 쓴 카테고리 해금권 수. */
	@Transactional(readOnly = true)
	public int availableTickets(long userId) {
		return habits.countUnusedTickets(userId);
	}

	/**
	 * 해금권 1장으로 카테고리를 연다 (4-3, Lv.1). 사용자 잠금 뒤: 없는 카테고리 404 → 이미 연 카테고리 409 → 해금권 없음 422.
	 * 부르는 쪽(조율 서비스)이 이어서 시작 몬스터를 준다.
	 */
	@Transactional
	public void openWithTicket(long userId, String categoryCode) {
		lockProfile(userId);
		if (habits.categories().stream().noneMatch(c -> c.code().equals(categoryCode))) {
			throw new ApiException(ErrorCode.NOT_FOUND);
		}
		if (habits.isOpened(userId, categoryCode)) {
			throw new ApiException(ErrorCode.ALREADY_OPENED);
		}
		long ticket = habits.firstUnusedTicket(userId).orElseThrow(() -> new ApiException(ErrorCode.NO_TICKET));
		habits.openCategory(userId, categoryCode, "TICKET"); // 해금권이 이 행을 외래키로 가리키므로 먼저
		habits.useTicket(ticket, categoryCode);
	}
}
