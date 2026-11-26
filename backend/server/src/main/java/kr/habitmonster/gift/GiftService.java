package kr.habitmonster.gift;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.gift.GiftRepository.GiftRow;
import kr.habitmonster.shop.ShopService;
import kr.habitmonster.wallet.LedgerReason;
import kr.habitmonster.wallet.WalletService;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 선물함 (API 명세 v10 11장, 기획 {@code docs/기획/2026-11-26-선물함.md}, 결정 D-89).
 *
 * <ul>
 * <li>퀘스트 계열 보상은 지갑 · 가방에 바로 넣지 않고 여기에 한 줄 ({@link #send}) → 사용자가 받을 때 지급</li>
 * <li>체크인 · 레벨업 · 기간 보너스 · 목표 · 탐색 중복 골드는 이 모듈을 거치지 않는다 (즉시 지급)</li>
 * <li><b>잠금 순서</b>: 받기는 선물 행을 맨 먼저 잡고(id 순) → 가방 → 지갑. 선물 만들기는 새 행 INSERT만 — 있는 선물 행을 잠그는 건
 * 받기뿐이라 가방 · 지갑을 쥔 채 선물 행을 기다리는 요청이 없다 (스키마 원칙 3-1)</li>
 * <li>골드는 원장에 출처와 같은 사유로, {@code ref_id} = 선물 id</li>
 * </ul>
 */
@Service
public class GiftService {

	private static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");

	/** {@code GET /gifts}의 한 줄. 아이템이 없으면 {@code itemCode} · {@code itemName}은 null, {@code quantity}는 0. */
	public record GiftView(long id, String source, String title, int gold, String itemCode, String itemName, int quantity,
			OffsetDateTime createdAt) {
	}

	public record Gifts(List<GiftView> gifts) {
	}

	public record ReceivedItem(String itemCode, int quantity) {
	}

	/** 받기 · 모두 받기 응답. {@code gold} · {@code ballCount}는 받은 뒤 지갑 잔액 · 가방의 볼 개수 (상단 바와 같은 이름). */
	public record Claimed(int claimedCount, int goldReceived, List<ReceivedItem> items, long gold, int ballCount) {
	}

	private final GiftRepository gifts;
	private final ShopService shop;
	private final WalletService wallet;

	GiftService(GiftRepository gifts, ShopService shop, WalletService wallet) {
		this.gifts = gifts;
		this.shop = shop;
		this.wallet = wallet;
	}

	/**
	 * 선물을 보낸다 (부른 쪽 트랜잭션 안). 골드 0 · 아이템 없음이면 만들지 않는다 (빈 선물 금지).
	 * 같은 출처 · 출처 번호로 두 번 불러도 한 줄만 생긴다.
	 *
	 * @param itemCode 없으면 null (그때 {@code itemQuantity}는 무시)
	 */
	@Transactional
	public void send(long userId, GiftSource source, String sourceRef, String title, int gold, String itemCode,
			int itemQuantity) {
		if (gold < 0 || (itemCode != null && itemQuantity <= 0)) {
			throw new IllegalArgumentException("선물 값 오류: gold=" + gold + ", " + itemCode + " x" + itemQuantity);
		}
		if (gold == 0 && itemCode == null) {
			return;
		}
		gifts.insert(userId, source, sourceRef, title, gold, itemCode, itemCode == null ? null : itemQuantity);
	}

	/** 받지 않은 선물, 최신순. */
	@Transactional(readOnly = true)
	public Gifts list(long userId) {
		return new Gifts(gifts.unclaimed(userId).stream().map(this::view).toList());
	}

	/** 받지 않은 선물이 하나라도 있나 (홈 아이콘의 점). */
	@Transactional(readOnly = true)
	public boolean hasGift(long userId) {
		return gifts.hasUnclaimed(userId);
	}

	/**
	 * 선물 하나를 받는다.
	 *
	 * @throws ApiException 404 {@code NOT_FOUND} — 없거나 남의 선물, 409 {@code GIFT_ALREADY_CLAIMED} — 이미 받음
	 */
	@Transactional
	public Claimed claim(long userId, long giftId) {
		GiftRow g = gifts.lockOne(userId, giftId).orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND));
		if (g.claimed()) {
			throw new ApiException(ErrorCode.GIFT_ALREADY_CLAIMED);
		}
		return give(userId, List.of(g));
	}

	/** 받지 않은 선물을 모두 받는다. 없으면 0개 (오류 아님). */
	@Transactional
	public Claimed claimAll(long userId) {
		return give(userId, gifts.lockUnclaimed(userId));
	}

	/** 잠근 선물들: 받음 표시 → 가방(아이템 코드 순) → 지갑(선물마다 원장 한 줄). */
	private Claimed give(long userId, List<GiftRow> rows) {
		if (!rows.isEmpty()) {
			gifts.markClaimed(rows.stream().map(GiftRow::id).toList());
		}
		Map<String, Integer> items = new TreeMap<>();
		for (GiftRow g : rows) {
			if (g.itemCode() != null) {
				items.merge(g.itemCode(), g.itemQuantity(), Integer::sum);
			}
		}
		List<ReceivedItem> received = new ArrayList<>();
		items.forEach((code, qty) -> {
			shop.receive(userId, code, qty);
			received.add(new ReceivedItem(code, qty));
		});
		int goldReceived = 0;
		for (GiftRow g : rows) {
			if (g.gold() > 0) {
				wallet.credit(userId, g.gold(), LedgerReason.valueOf(g.sourceCode()), String.valueOf(g.id()));
				goldReceived += g.gold();
			}
		}
		return new Claimed(rows.size(), goldReceived, received, wallet.balance(userId),
				shop.quantity(userId, ShopService.BALL));
	}

	private GiftView view(GiftRow g) {
		String itemName = g.itemCode() == null ? null : shop.itemName(g.itemCode()).orElse(g.itemCode());
		return new GiftView(g.id(), g.sourceCode(), g.title(), g.gold(), g.itemCode(), itemName, g.itemQuantity(),
				OffsetDateTime.ofInstant(Instant.ofEpochMilli(g.createdMs()), SEOUL));
	}
}
