package kr.habitmonster.dex;

import java.util.List;

import com.fasterxml.jackson.annotation.JsonInclude;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.habit.HabitService;
import kr.habitmonster.habit.HabitService.Category;
import kr.habitmonster.monster.MonsterService;
import kr.habitmonster.monster.MonsterService.DexSpecies;
import kr.habitmonster.monster.MonsterService.GrantedStarter;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 도감 · 카테고리 열기 (API 명세 v5 "7. 도감", 4-3) — 습관(연 카테고리 · 레벨 · 해금권) · 몬스터(종 · 도감 기록) 모듈을 모으는
 * 조율 서비스. 자기 테이블은 없다. 그림은 {@code imageUrl} · {@code silhouetteUrl} 대신 {@code imageKey}(= 종 코드, D1 · D6) —
 * 모르는 종의 실루엣은 앱이 같은 그림을 검게 칠해 그린다.
 */
@Service
public class DexService {

	public record Slot(int dexCount, Integer nextMilestone, int availableTickets) {
	}

	public record CategorySummary(String code, String name, boolean opened, int ownedCount, int seenCount,
			int totalCount) {
	}

	/** {@code GET /dex}. */
	public record DexSummary(Slot slot, List<CategorySummary> categories) {
	}

	/**
	 * 카테고리 목록의 한 종. OWNED · SEEN = 번호 · 이름 · 그림(OWNED만 레벨), UNKNOWN = 번호 · 그림 이름 · 출현 레벨 ·
	 * 지금 카테고리 레벨로 나올 수 있는지만 (이름 · 종 번호 없음, D6). 없는 값은 응답에서 뺀다.
	 */
	@JsonInclude(JsonInclude.Include.NON_NULL)
	public record DexMonster(int dexNo, String status, Integer speciesId, String name, String imageKey, Integer level,
			Integer unlockLevel, Boolean unlocked) {
	}

	/** {@code GET /dex/categories/{code}}. */
	public record DexCategory(String code, int ownedCount, int seenCount, int totalCount, List<DexMonster> monsters) {
	}

	/** {@code GET /dex/species/{id}}. 본 종(SEEN)은 레벨 · 진화 단계가 null. */
	public record DexDetail(int dexNo, String status, String name, String imageKey, String element, int rarity,
			Integer level, Integer stage, String description) {
	}

	@JsonInclude(JsonInclude.Include.NON_NULL)
	public record UnlockedStarter(long userMonsterId, String name, String imageKey, String location) {
	}

	/** {@code POST /categories/{code}/unlock} 응답. 시작 몬스터가 없는 카테고리면 {@code starter}가 null. */
	public record Unlocked(String categoryCode, UnlockedStarter starter, int availableTickets) {
	}

	private final HabitService habits;
	private final MonsterService monsters;
	private final BalanceConfig config;

	DexService(HabitService habits, MonsterService monsters, BalanceConfig config) {
		this.habits = habits;
		this.monsters = monsters;
		this.config = config;
	}

	@Transactional(readOnly = true)
	public DexSummary summary(long userId) {
		int dexCount = monsters.dexCount(userId);
		Integer next = config.dexUnlockThresholds().stream().filter(t -> t > dexCount).findFirst().orElse(null);
		List<String> opened = habits.openedCategories(userId);
		List<DexSpecies> all = monsters.dex(userId, null);
		List<CategorySummary> categories = habits.categories().stream()
			.map(c -> {
				List<DexSpecies> mine = all.stream().filter(s -> s.categoryCode().equals(c.code())).toList();
				return new CategorySummary(c.code(), c.name(), opened.contains(c.code()), count(mine, "OWNED"),
						mine.size() - count(mine, "UNKNOWN"), mine.size());
			})
			.toList();
		return new DexSummary(new Slot(dexCount, next, habits.availableTickets(userId)), categories);
	}

	/** 없는 카테고리 코드면 404. */
	@Transactional(readOnly = true)
	public DexCategory category(long userId, String code) {
		category(code);
		int level = habits.categoryLevels(userId).getOrDefault(code, 0); // 안 연 카테고리는 아무 종도 안 나온다
		List<DexSpecies> list = monsters.dex(userId, code);
		List<DexMonster> rows = list.stream().map(s -> switch (s.status()) {
			case "UNKNOWN" -> new DexMonster(s.dexNo(), s.status(), null, null, s.code(), null, s.unlockLevel(),
					s.unlockLevel() <= level);
			default -> new DexMonster(s.dexNo(), s.status(), s.speciesId(), s.name(), s.code(), s.level(), null, null);
		}).toList();
		return new DexCategory(code, count(list, "OWNED"), list.size() - count(list, "UNKNOWN"), list.size(), rows);
	}

	/** 본 적 없는 종(없는 번호 포함)이면 404 {@code NOT_DISCOVERED}. */
	@Transactional(readOnly = true)
	public DexDetail species(long userId, int speciesId) {
		DexSpecies s = monsters.dex(userId, null).stream()
			.filter(d -> d.speciesId() == speciesId && !d.status().equals("UNKNOWN")).findFirst()
			.orElseThrow(() -> new ApiException(ErrorCode.NOT_DISCOVERED));
		return new DexDetail(s.dexNo(), s.status(), s.name(), s.code(), category(s.categoryCode()).element(), s.rarity(),
				s.level(), s.stage(), s.description());
	}

	/**
	 * 카테고리 열기: 해금권 1장 → 카테고리 Lv.1 → 시작 몬스터(필드가 꽉 찼으면 가방). 부르는 순서 = 잠금 순서(습관 → 몬스터).
	 * 시작 몬스터로 가진 종이 기준값(5 · 10 · 15)에 닿으면 해금권을 또 받는다 (포획과 같은 규칙).
	 */
	@Transactional
	public Unlocked unlock(long userId, String code) {
		habits.openWithTicket(userId, code);
		UnlockedStarter starter = null;
		if (monsters.starters().containsKey(code)) {
			int before = monsters.dexCount(userId);
			GrantedStarter g = monsters.grantStarter(userId, code, monsters.fieldCount(userId), false);
			int after = monsters.dexCount(userId);
			if (after > before) {
				habits.grantUnlockTicket(userId, after);
			}
			starter = new UnlockedStarter(g.userMonsterId(), g.name(), g.imageKey(), g.location());
		}
		return new Unlocked(code, starter, habits.availableTickets(userId));
	}

	private Category category(String code) {
		return habits.categories().stream().filter(c -> c.code().equals(code)).findFirst()
			.orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND));
	}

	private static int count(List<DexSpecies> list, String status) {
		return (int) list.stream().filter(s -> s.status().equals(status)).count();
	}
}
