package kr.habitmonster.explore;

import java.time.LocalDate;
import java.util.Optional;
import java.util.UUID;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.habit.HabitService;
import kr.habitmonster.monster.MonsterService;
import kr.habitmonster.monster.MonsterService.CapturedMonster;
import kr.habitmonster.monster.MonsterService.Caught;
import kr.habitmonster.monster.MonsterService.Explored;
import kr.habitmonster.monster.MonsterService.SpeciesView;
import kr.habitmonster.monster.MonsterService.Target;
import kr.habitmonster.shop.ShopService;
import kr.habitmonster.shop.ShopService.Consumed;
import kr.habitmonster.wallet.LedgerReason;
import kr.habitmonster.wallet.WalletService;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 탐색 · 포획 (API 명세 v5 "5. 챗봇 — 탐색") — 습관 · 몬스터 · 가방 · 지갑 모듈을 차례로 부르는 조율 서비스. 자기 테이블은 없다.
 *
 * <p>부르는 순서는 사용자 잠금 순서와 같다: 습관(사용자 잠금 · 카테고리 레벨 · 해금권) → 몬스터(탐색 기록) → 가방(볼) → 지갑(골드).
 * 그래서 같은 사람의 탐색 · 던지기가 동시에 와도 한 줄로 서고, 같은 등장에 두 번 던지면 두 번째는 409다.
 */
@Service
public class ExploreService {

	public record ExploreRequest(LocalDate businessDate) {
	}

	/** {@code POST /explores} 응답 (명세 그대로, {@code imageUrl} 대신 {@code imageKey}). */
	public record ExploreResult(long exploreId, String result, SpeciesView species, boolean newlySeen, int goldAwarded,
			long gold, Long skippedExploreId, int exploreRemaining) {
	}

	public record Dex(int dexCount, boolean newSlotAvailable) {
	}

	/**
	 * {@code POST /explores/{id}/capture} 응답. {@code newSlotAvailable}은 이번 포획으로 카테고리 해금권을 받았는지
	 * (카테고리를 실제로 여는 API는 4단계).
	 */
	public record CaptureResult(String outcome, CapturedMonster monster, int ballCount, Dex dex) {
	}

	private final HabitService habits;
	private final MonsterService monsters;
	private final ShopService shop;
	private final WalletService wallet;
	private final BusinessDates dates;

	ExploreService(HabitService habits, MonsterService monsters, ShopService shop, WalletService wallet,
			BusinessDates dates) {
		this.habits = habits;
		this.monsters = monsters;
		this.shop = shop;
		this.wallet = wallet;
		this.dates = dates;
	}

	@Transactional
	public ExploreResult explore(long userId, UUID key, ExploreRequest req) {
		LocalDate today = dates.requireToday(req.businessDate()); // ⑤ 업무 날짜 (다르면 409)
		habits.lockProfile(userId);
		Explored e = monsters.explore(userId, today, key, habits.categoryLevels(userId));
		// 가진 종이면 볼 없이 골드. 원장 ref = 탐색 id라 같은 탐색으로 두 번 받을 수 없다
		long gold = wallet.credit(userId, e.goldAwarded(), LedgerReason.DUPLICATE, String.valueOf(e.exploreId())).balance();
		return new ExploreResult(e.exploreId(), e.result(), e.species(), e.newlySeen(), e.goldAwarded(), gold,
				e.skippedExploreId(), e.exploreRemaining());
	}

	/** 오늘 처리하지 않은 등장. 없으면 비어 있다 (204). */
	@Transactional(readOnly = true)
	public Optional<ExploreResult> pending(long userId) {
		long gold = wallet.balance(userId);
		return monsters.pending(userId).map(e -> new ExploreResult(e.exploreId(), e.result(), e.species(), false, 0, gold,
				null, e.exploreRemaining()));
	}

	@Transactional
	public CaptureResult capture(long userId, long exploreId, UUID key, ExploreRequest req) {
		LocalDate today = dates.requireToday(req.businessDate());
		habits.lockProfile(userId);
		Target target = monsters.captureTarget(userId, exploreId, today);
		Consumed ball = shop.useBall(userId, "CAPTURE:" + key); // 0개면 422, 아무것도 바뀌지 않는다
		Caught c = monsters.capture(userId, target, ball.consumptionId());
		boolean ticket = c.dexAdded() && habits.grantUnlockTicket(userId, c.dexCount());
		return new CaptureResult(c.outcome(), c.monster(), ball.remaining(), new Dex(c.dexCount(), ticket));
	}
}
