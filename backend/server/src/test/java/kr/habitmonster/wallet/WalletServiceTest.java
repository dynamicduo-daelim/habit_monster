package kr.habitmonster.wallet;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import org.springframework.beans.factory.annotation.Autowired;

/** 지갑: 잔액 + 원장 한 줄, 같은 보상 한 번만, 잔액 부족 422, 동시 차감에도 음수 없음. */
class WalletServiceTest extends PostgresTest {

	@Autowired
	WalletService wallet;

	long userId;

	@BeforeEach
	void user() {
		userId = jdbc.queryForObject("insert into identity.users (email) values ('w@habit.kr') returning id", Long.class);
		wallet.open(userId);
	}

	int ledgerRows() {
		return jdbc.queryForObject("select count(*) from wallet.wallet_ledger where user_id = ?", Integer.class, userId);
	}

	@Test
	void 적립과_차감은_잔액과_원장을_같이_바꾼다() {
		assertThat(wallet.balance(userId)).isZero();

		assertThat(wallet.credit(userId, 120, LedgerReason.CHECKIN, "1")).isEqualTo(new WalletService.Change(true, 120));
		assertThat(wallet.debit(userId, 50, LedgerReason.SHOP_PURCHASE, "7")).isEqualTo(new WalletService.Change(true, 70));

		assertThat(wallet.balance(userId)).isEqualTo(70);
		assertThat(jdbc.queryForList("""
			select amount || ' ' || balance_after || ' ' || reason_code || ' ' || direction
			  from wallet.wallet_ledger where user_id = ? order by id""", String.class, userId))
			.containsExactly("120 120 CHECKIN CREDIT", "-50 70 SHOP_PURCHASE DEBIT");
	}

	@Test
	void 금액_0이면_원장에_쓰지_않는다() {
		assertThat(wallet.credit(userId, 0, LedgerReason.CHECKIN, "1").applied()).isFalse();
		assertThat(ledgerRows()).isZero();
	}

	@Test
	void 같은_사유_같은_ref는_한_번만() {
		wallet.credit(userId, 20, LedgerReason.LEVELUP, "5:ex");
		WalletService.Change again = wallet.credit(userId, 20, LedgerReason.LEVELUP, "5:ex");

		assertThat(again).isEqualTo(new WalletService.Change(false, 20));
		assertThat(ledgerRows()).isEqualTo(1);
		// 사유가 다르면 같은 ref여도 다른 보상
		wallet.credit(userId, 30, LedgerReason.CHECKIN, "5:ex");
		assertThat(wallet.balance(userId)).isEqualTo(50);
	}

	@Test
	void 잔액이_모자라면_422_NOT_ENOUGH_GOLD_아무것도_안_바뀜() {
		wallet.credit(userId, 40, LedgerReason.CHECKIN, "1");

		assertThatThrownBy(() -> wallet.debit(userId, 50, LedgerReason.SHOP_PURCHASE, "9"))
			.isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo(ErrorCode.NOT_ENOUGH_GOLD));
		assertThat(wallet.balance(userId)).isEqualTo(40);
		assertThat(ledgerRows()).isEqualTo(1);
	}

	@Test
	void 동시에_차감_두_건이_와도_음수가_되지_않는다() throws Exception {
		wallet.credit(userId, 100, LedgerReason.CHECKIN, "1");
		CountDownLatch start = new CountDownLatch(1);
		ExecutorService pool = Executors.newFixedThreadPool(2);
		List<Future<String>> results = new ArrayList<>();
		for (String ref : List.of("a", "b")) {
			results.add(pool.submit(() -> {
				start.await();
				try {
					wallet.debit(userId, 60, LedgerReason.SHOP_PURCHASE, ref);
					return "ok";
				}
				catch (ApiException e) {
					return e.code().name();
				}
			}));
		}
		start.countDown();
		List<String> outcomes = new ArrayList<>();
		for (Future<String> f : results) {
			outcomes.add(f.get(10, TimeUnit.SECONDS));
		}
		pool.shutdown();

		assertThat(outcomes).containsExactlyInAnyOrder("ok", "NOT_ENOUGH_GOLD");
		assertThat(wallet.balance(userId)).isEqualTo(40);
	}
}
