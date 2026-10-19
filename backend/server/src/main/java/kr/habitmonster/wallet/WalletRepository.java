package kr.habitmonster.wallet;

import java.util.List;
import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** {@code wallet.wallet} · {@code wallet.wallet_ledger}만 읽고 쓴다 (모듈 = 스키마). */
@Repository
class WalletRepository {

	private final JdbcClient db;

	WalletRepository(JdbcClient db) {
		this.db = db;
	}

	void create(long userId) {
		db.sql("insert into wallet.wallet (user_id) values (?) on conflict do nothing").param(userId).update();
	}

	Optional<Long> balance(long userId) {
		return db.sql("select balance from wallet.wallet where user_id = ?").param(userId).query(Long.class).optional();
	}

	/** 잔액 행을 잠근다 (사용자 잠금 순서의 마지막). 같은 사용자의 다른 골드 변경은 이 트랜잭션이 끝날 때까지 기다린다. */
	Optional<Long> lockBalance(long userId) {
		return db.sql("select balance from wallet.wallet where user_id = ? for no key update")
			.param(userId).query(Long.class).optional();
	}

	boolean ledgerExists(LedgerReason reason, String refId) {
		return db.sql("select exists (select 1 from wallet.wallet_ledger where reason_code = ? and ref_id = ?)")
			.params(reason.name(), refId).query(Boolean.class).single();
	}

	/** 적립. 바뀐 잔액. */
	long add(long userId, long amount) {
		return db.sql("""
			update wallet.wallet set balance = balance + ?, version = version + 1, updated_at = now()
			 where user_id = ? returning balance""")
			.params(amount, userId).query(Long.class).single();
	}

	/** 조건부 차감 — 잔액이 모자라면 아무것도 바꾸지 않고 비어 있다. 동시에 두 건이 와도 음수가 되지 않는다. */
	Optional<Long> subtractIfEnough(long userId, long amount) {
		return db.sql("""
			update wallet.wallet set balance = balance - ?, version = version + 1, updated_at = now()
			 where user_id = ? and balance >= ? returning balance""")
			.params(amount, userId, amount).query(Long.class).optional();
	}

	/** @param signedAmount 적립은 양수, 차감은 음수 (DB가 부호로 방향을 계산한다) */
	void appendLedger(long userId, int signedAmount, long balanceAfter, LedgerReason reason, String refId, String memo) {
		db.sql("""
			insert into wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id, memo)
			values (?, ?, ?, ?, ?, ?)""")
			.params(userId, signedAmount, balanceAfter, reason.name(), refId, memo).update();
	}

	/** 체크인 하나로 받은 골드: 점수(CHECKIN) + 카테고리 레벨업(LEVELUP "체크인id:카테고리") + 그 제출로 채운 기간 보너스. */
	long checkinCredits(long userId, long checkinId, List<Long> periodIds) {
		List<String> periods = periodIds.isEmpty() ? List.of("") : periodIds.stream().map(String::valueOf).toList();
		return db.sql("""
			select coalesce(sum(amount), 0) from wallet.wallet_ledger
			 where user_id = :user and ((reason_code = 'CHECKIN' and ref_id = :checkin)
			    or (reason_code = 'LEVELUP' and ref_id like :levelup)
			    or (reason_code = 'PERIOD_BONUS' and ref_id in (:periods)))""")
			.param("user", userId).param("checkin", String.valueOf(checkinId)).param("levelup", checkinId + ":%")
			.param("periods", periods).query(Long.class).single();
	}
}
