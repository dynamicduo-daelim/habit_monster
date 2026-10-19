package kr.habitmonster.onboarding;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import kr.habitmonster.auth.AuthService;
import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ApiExceptionHandler.FieldError;
import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.goal.GoalService;
import kr.habitmonster.goal.GoalService.GoalType;
import kr.habitmonster.habit.HabitService;
import kr.habitmonster.habit.HabitService.Category;
import kr.habitmonster.habit.HabitService.MeasureRule;
import kr.habitmonster.monster.MonsterService;
import kr.habitmonster.monster.MonsterService.GrantedStarter;
import kr.habitmonster.monster.MonsterService.Starter;
import kr.habitmonster.wallet.WalletService;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 온보딩 (API 명세 v5 "2. 온보딩") — 여러 모듈에 걸친 일이라 이 서비스가 **각 모듈의 서비스를** 차례로 부른다.
 * 자기 테이블은 없다 (SQL을 쓰지 않는다 — 모듈 규칙).
 *
 * <p>{@code POST /onboarding}은 한 트랜잭션: 하나라도 틀리면 아무것도 남지 않는다 (DB v1.5 "온보딩은 마지막에 한 번에 저장").
 * 모듈을 부르는 순서는 사용자 잠금 순서와 같다: 회원 → 습관 → 목표 → 몬스터 → 지갑 (교착 방지, DB 원칙 3-1).
 */
@Service
public class OnboardingService {

	/** {@code GET /categories} 한 줄. {@code color} · {@code glyph}는 앱이 쓰지 않는다 (D3). */
	public record CategoryView(String code, String name, String shortName, String element, String glyph, String color,
			int sortOrder, boolean opened, Starter starter) {
	}

	public record HabitInput(String categoryCode, Integer measureTypeId, String name, BigDecimal dailyTarget,
			String periodCode) {
	}

	public record GoalInput(String goalType, String title, String detail) {
	}

	/**
	 * 온보딩 요청. {@code partnerCategory}는 명세에 더한 선택 필드 — 앱 1단계에서 사용자가 고른 "첫 파트너"의 카테고리.
	 * 없으면 명세 규칙(운동, 없으면 순서가 앞선 카테고리)으로 정한다 (결정 D-36).
	 */
	public record OnboardingRequest(List<String> categories, String partnerCategory, List<HabitInput> habits,
			List<GoalInput> goals) {
	}

	public record OnboardingResult(List<GrantedStarter> starters, long partnerMonsterId, List<Long> habitIds,
			List<Long> goalIds) {
	}

	private static final int NAME_MAX = 30;
	private static final int TITLE_MAX = 50;
	private static final int DETAIL_MAX = 500;

	private final AuthService auth;
	private final HabitService habits;
	private final GoalService goals;
	private final MonsterService monsters;
	private final WalletService wallet;
	private final BalanceConfig config;
	private final BusinessDates dates;

	OnboardingService(AuthService auth, HabitService habits, GoalService goals, MonsterService monsters,
			WalletService wallet, BalanceConfig config, BusinessDates dates) {
		this.auth = auth;
		this.habits = habits;
		this.goals = goals;
		this.monsters = monsters;
		this.wallet = wallet;
		this.config = config;
		this.dates = dates;
	}

	/** 카테고리 목록 + 내가 열었는지 + 스타터 (온보딩 화면 · 통계 · 도감이 같이 쓴다). */
	@Transactional(readOnly = true)
	public List<CategoryView> categories(long userId) {
		Set<String> opened = Set.copyOf(habits.openedCategories(userId));
		Map<String, Starter> starters = monsters.starters();
		return habits.categories().stream()
			.map(c -> new CategoryView(c.code(), c.name(), c.shortName(), c.element(), c.glyph(), c.color(),
					c.sortOrder(), opened.contains(c.code()), starters.get(c.code())))
			.toList();
	}

	@Transactional
	public OnboardingResult complete(long userId, OnboardingRequest req) {
		// ② 상태: 이미 끝냈으면 409 — 이 UPDATE가 사용자 행을 잠가서 동시에 온 두 번째 요청도 여기서 막힌다
		auth.markOnboarded(userId);
		List<Category> chosen = validate(req); // ⑥ 값 형식: 틀리면 400 + errors (위 UPDATE도 함께 되돌려짐)

		List<String> codes = chosen.stream().map(Category::code).toList();
		habits.startProfile(userId, codes);
		List<Long> habitIds = new ArrayList<>();
		for (HabitInput h : req.habits()) {
			habitIds.add(habits.addHabit(userId, h.categoryCode(), h.measureTypeId(), h.name().strip(),
					h.dailyTarget(), h.periodCode(), dates.today())); // 온보딩 습관은 오늘부터 (명세)
		}

		goals.startProfile(userId);
		List<Long> goalIds = new ArrayList<>();
		for (GoalInput g : nonNull(req.goals())) {
			goalIds.add(goals.addGoal(userId, GoalType.valueOf(g.goalType()), g.title().strip(), blankToNull(g.detail())));
		}

		monsters.startProfile(userId);
		String partner = partnerCategory(req.partnerCategory(), chosen);
		List<GrantedStarter> starters = new ArrayList<>();
		int field = 0;
		for (String code : codes) {
			GrantedStarter s = monsters.grantStarter(userId, code, field, code.equals(partner));
			starters.add(s);
			field += "FIELD".equals(s.location()) ? 1 : 0;
		}
		long partnerId = starters.stream().filter(s -> s.categoryCode().equals(partner)).findFirst().orElseThrow()
			.userMonsterId();

		// 시작 골드 · 성실볼은 지금 주지 않는다 — DB에 지급 사유 · 설정 키가 없어서 (결정 D-35, backend/db/README.md 제안)
		wallet.open(userId);
		return new OnboardingResult(starters, partnerId, habitIds, goalIds);
	}

	/** 대화 상대: 고른 것 → 운동 → 순서가 가장 앞선 카테고리. */
	private static String partnerCategory(String requested, List<Category> chosen) {
		if (requested != null) {
			return requested;
		}
		return chosen.stream().anyMatch(c -> c.code().equals("ex")) ? "ex" : chosen.getFirst().code();
	}

	/**
	 * 모든 항목을 끝까지 검사해 틀린 것을 한꺼번에 돌려준다 (앱이 한 번에 고칠 수 있게).
	 * @return 고른 카테고리 (카테고리 순서대로)
	 */
	private List<Category> validate(OnboardingRequest req) {
		List<FieldError> errors = new ArrayList<>();
		Map<String, Category> all = new LinkedHashMap<>();
		habits.categories().forEach(c -> all.put(c.code(), c));

		List<String> cats = nonNull(req.categories());
		int min = config.categorySelectMin();
		int max = config.categorySelectMax();
		if (cats.size() < min || cats.size() > max) {
			errors.add(new FieldError("categories", "카테고리는 " + min + "~" + max + "개 골라 주세요."));
		}
		if (new HashSet<>(cats).size() != cats.size()) {
			errors.add(new FieldError("categories", "같은 카테고리를 두 번 고를 수 없어요."));
		}
		for (int i = 0; i < cats.size(); i++) {
			if (!all.containsKey(cats.get(i))) {
				errors.add(new FieldError("categories[" + i + "]", "없는 카테고리예요."));
			}
		}
		Set<String> picked = Set.copyOf(cats.stream().filter(all::containsKey).toList());
		if (req.partnerCategory() != null && !picked.contains(req.partnerCategory())) {
			errors.add(new FieldError("partnerCategory", "고른 카테고리 중에서 골라 주세요."));
		}

		List<HabitInput> hs = nonNull(req.habits());
		if (hs.isEmpty() || hs.size() > config.maxActiveHabits()) {
			errors.add(new FieldError("habits", "습관은 1~" + config.maxActiveHabits() + "개 등록해 주세요."));
		}
		for (int i = 0; i < hs.size(); i++) {
			validateHabit("habits[" + i + "]", hs.get(i), picked, errors);
		}

		List<GoalInput> gs = nonNull(req.goals());
		long weekly = gs.stream().filter(g -> "WEEKLY".equals(g.goalType())).count();
		long monthly = gs.stream().filter(g -> "MONTHLY".equals(g.goalType())).count();
		if (weekly > config.weeklyGoalSlots() || monthly > config.monthlyGoalSlots()) {
			errors.add(new FieldError("goals", "주간 목표는 " + config.weeklyGoalSlots() + "개, 월간 목표는 "
					+ config.monthlyGoalSlots() + "개까지예요."));
		}
		for (int i = 0; i < gs.size(); i++) {
			GoalInput g = gs.get(i);
			String f = "goals[" + i + "]";
			if (g == null) {
				errors.add(new FieldError(f, "목표를 확인해 주세요."));
				continue;
			}
			if (!"WEEKLY".equals(g.goalType()) && !"MONTHLY".equals(g.goalType())) {
				errors.add(new FieldError(f + ".goalType", "WEEKLY 또는 MONTHLY예요."));
			}
			if (!lengthBetween(g.title(), 1, TITLE_MAX)) {
				errors.add(new FieldError(f + ".title", "제목은 1~" + TITLE_MAX + "자예요."));
			}
			if (g.detail() != null && g.detail().codePointCount(0, g.detail().length()) > DETAIL_MAX) {
				errors.add(new FieldError(f + ".detail", "상세는 " + DETAIL_MAX + "자까지예요."));
			}
		}

		if (!errors.isEmpty()) {
			throw new ApiException(ErrorCode.INVALID_REQUEST, ErrorCode.INVALID_REQUEST.message, errors);
		}
		return all.values().stream().filter(c -> picked.contains(c.code()))
			.sorted(Comparator.comparingInt(Category::sortOrder)).toList();
	}

	private void validateHabit(String f, HabitInput h, Set<String> picked, List<FieldError> errors) {
		if (h == null) {
			errors.add(new FieldError(f, "습관을 확인해 주세요."));
			return;
		}
		if (h.categoryCode() == null || !picked.contains(h.categoryCode())) {
			errors.add(new FieldError(f + ".categoryCode", "고른 카테고리의 습관만 등록할 수 있어요."));
		}
		Optional<MeasureRule> measure = h.measureTypeId() == null ? Optional.empty() : habits.measureRule(h.measureTypeId());
		if (measure.isEmpty() || !measure.get().categoryCode().equals(h.categoryCode())) {
			errors.add(new FieldError(f + ".measureTypeId", "그 카테고리의 측정 항목이 아니에요."));
		}
		if (!lengthBetween(h.name(), 1, NAME_MAX)) {
			errors.add(new FieldError(f + ".name", "이름은 1~" + NAME_MAX + "자예요."));
		}
		BigDecimal max = measure.map(MeasureRule::maxValue).orElse(null);
		if (h.dailyTarget() == null || h.dailyTarget().signum() <= 0
				|| (max != null && h.dailyTarget().compareTo(max) > 0)) {
			errors.add(new FieldError(f + ".dailyTarget",
					max == null ? "0보다 커야 해요." : "0보다 크고 " + max.stripTrailingZeros().toPlainString() + " 이하여야 해요."));
		}
		if (!habits.isPeriodCode(h.periodCode())) {
			errors.add(new FieldError(f + ".periodCode", "D7 · D30 · D100 중 하나예요."));
		}
	}

	private static boolean lengthBetween(String s, int min, int max) {
		if (s == null) {
			return false;
		}
		int n = s.strip().codePointCount(0, s.strip().length());
		return n >= min && n <= max;
	}

	private static String blankToNull(String s) {
		return s == null || s.isBlank() ? null : s.strip();
	}

	private static <T> List<T> nonNull(List<T> list) {
		return list == null ? List.of() : list;
	}
}
