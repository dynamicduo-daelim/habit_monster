package kr.habitmonster.wallet;

import java.util.List;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 골드 지갑 — 체크인 · 탐색 · 상점 · 목표가 모두 이 서비스로만 골드를 바꾼다.
 *
 * <p>골드가 바뀔 때마다 잔액({@code wallet.wallet})과 원장({@code wallet.wallet_ledger}, "언제 왜 얼마") 한 줄을 같은 트랜잭션에 쓴다.
 * 원장은 {@code (사유, ref_id)}가 유일해서, 같은 보상을 두 번 주는 일(재시도 · 버튼 두 번)을 DB가 막는다.
 */
@Service
public class WalletService {

	/** 골드 변경 결과. {@code applied}가 false면 같은 사유 · ref로 이미 처리돼 이번엔 아무것도 안 바뀌었다. */
	public record Change(boolean applied, long balance) {
	}

	private final WalletRepository wallets;

	WalletService(WalletRepository wallets) {
		this.wallets = wallets;
	}

	/** 지갑을 만든다 (잔액 0, 온보딩 때). 이미 있으면 그대로. */
	@Transactional
	public void open(long userId) {
		wallets.create(userId);
	}

	@Transactional(readOnly = true)
	public long balance(long userId) {
		return wallets.balance(userId).orElse(0L);
	}

	/** 오늘 요약의 "받은 골드": 체크인 하나로 들어온 골드 합 ({@link WalletRepository#checkinCredits}). */
	@Transactional(readOnly = true)
	public long checkinGold(long userId, long checkinId, List<Long> periodsEnded) {
		return wallets.checkinCredits(userId, checkinId, periodsEnded);
	}

	/**
	 * 적립. 금액 0이면 원장에 쓰지 않고 그대로 (DB 원칙: 0원 원장 없음).
	 * 지갑 행을 잠근 뒤 같은 {@code (사유, ref)}가 있는지 보므로, 같은 보상이 동시에 두 번 와도 한 번만 들어간다.
	 */
	@Transactional
	public Change credit(long userId, int amount, LedgerReason reason, String refId) {
		return credit(userId, amount, reason, refId, null);
	}

	/** @param memo 운영 보정(ADJUST)이면 필수 */
	@Transactional
	public Change credit(long userId, int amount, LedgerReason reason, String refId, String memo) {
		requireNotNegative(amount);
		long current = wallets.lockBalance(userId).orElseThrow(() -> new IllegalStateException("지갑 없음: " + userId));
		if (amount == 0 || wallets.ledgerExists(reason, refId)) {
			return new Change(false, current);
		}
		long after = wallets.add(userId, amount);
		wallets.appendLedger(userId, amount, after, reason, refId, memo);
		return new Change(true, after);
	}

	/**
	 * 차감. 잔액이 모자라면 422 {@code NOT_ENOUGH_GOLD}이고 아무것도 바뀌지 않는다.
	 * 조건부 UPDATE({@code … where balance >= ?})라서 다른 키의 구매 두 건이 동시에 와도 잔액이 음수가 되지 않는다.
	 */
	@Transactional
	public Change debit(long userId, int amount, LedgerReason reason, String refId) {
		requireNotNegative(amount);
		if (amount == 0 || wallets.ledgerExists(reason, refId)) {
			return new Change(false, balance(userId));
		}
		long after = wallets.subtractIfEnough(userId, amount)
			.orElseThrow(() -> new ApiException(ErrorCode.NOT_ENOUGH_GOLD));
		wallets.appendLedger(userId, -amount, after, reason, refId, null);
		return new Change(true, after);
	}

	private static void requireNotNegative(int amount) {
		if (amount < 0) {
			throw new IllegalArgumentException("금액은 0 이상: " + amount);
		}
	}
}
