package kr.habitmonster.shop;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import com.jayway.jsonpath.JsonPath;

import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Test;
import org.skyscreamer.jsonassert.JSONAssert;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;

/** 상점 구매 (API 명세 v5 {@code POST /shop/purchases}, 3-5단계). 가격은 서버의 상점 가격 (BALL 50G). */
class PurchaseApiTest extends PostgresTest {

	static final String E = "a@habit.kr";

	ResultActions buy(String access, String key, String body) throws Exception {
		return mvc.perform(post("/shop/purchases").header("Authorization", "Bearer " + access)
			.header(IdempotencyFilter.HEADER, key).contentType(MediaType.APPLICATION_JSON).content(body));
	}

	ResultActions buy(String access, String itemCode, Object quantity) throws Exception {
		return buy(access, UUID.randomUUID().toString(), "{\"itemCode\": \"" + itemCode + "\", \"quantity\": " + quantity + "}");
	}

	String rich(String email, long gold) throws Exception {
		String access = onboardedUser(email);
		jdbc.update("update wallet.wallet set balance = ? where user_id = ?", gold, userIdOf(email));
		return access;
	}

	long gold() {
		return jdbc.queryForObject("select balance from wallet.wallet where user_id = ?", Long.class, userIdOf(E));
	}

	int count(String table) {
		return jdbc.queryForObject("select count(*) from " + table, Integer.class);
	}

	@Test
	void 사면_골드가_줄고_가방이_늘고_원장_한_줄() throws Exception {
		String access = rich(E, 200);
		String res = buy(access, "BALL", 3).andExpect(status().isCreated())
			.andExpect(jsonPath("$.totalPrice").value(150))
			.andExpect(jsonPath("$.gold").value(50))
			.andExpect(jsonPath("$.itemCode").value("BALL"))
			.andExpect(jsonPath("$.quantity").value(3))
			.andReturn().getResponse().getContentAsString();
		long purchaseId = ((Number) JsonPath.read(res, "$.purchaseId")).longValue();
		buy(access, "BALL", 1).andExpect(jsonPath("$.quantity").value(4)); // 응답 수량 = 산 뒤 가방 개수
		assertThat(jdbc.queryForObject("select amount from wallet.wallet_ledger where reason_code = 'SHOP_PURCHASE' and ref_id = ?",
				Integer.class, String.valueOf(purchaseId))).isEqualTo(-150);
		assertThat(jdbc.queryForObject("select unit_price from shop.purchase where id = ?", Integer.class, purchaseId)).isEqualTo(50);
	}

	@Test
	void 골드가_모자라면_422_아무것도_안_남는다() throws Exception {
		String access = rich(E, 40);
		buy(access, "BALL", 1).andExpect(status().isUnprocessableContent())
			.andExpect(jsonPath("$.code").value("NOT_ENOUGH_GOLD"));
		assertThat(gold()).isEqualTo(40);
		assertThat(count("shop.purchase")).isZero();
		assertThat(count("shop.inventory")).isZero();
	}

	@Test
	void 수량_1_99_밖이나_없는_아이템은_400() throws Exception {
		String access = rich(E, 10000);
		buy(access, "BALL", 0).andExpect(status().isBadRequest());
		buy(access, "BALL", 100).andExpect(status().isBadRequest());
		buy(access, "BALL", (Object) null).andExpect(status().isBadRequest());
		buy(access, "SWORD", 1).andExpect(status().isBadRequest());
		buy(access, "POTION_S", 99).andExpect(status().isCreated()).andExpect(jsonPath("$.totalPrice").value(1980));
	}

	@Test
	void 같은_키로_다시_보내면_골드는_한_번만() throws Exception {
		String access = rich(E, 200);
		String key = UUID.randomUUID().toString();
		String body = "{\"itemCode\": \"POTION_M\", \"quantity\": 2}";
		String first = buy(access, key, body).andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
		String again = buy(access, key, body).andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
		JSONAssert.assertEquals(first, again, true); // 재전송은 저장해 둔 첫 응답 (JSON 필드 순서만 다를 수 있음)
		assertThat(gold()).isEqualTo(20);
		assertThat(count("shop.purchase")).isEqualTo(1);
	}

	@Test
	void 다른_키로_동시에_두_건이어도_잔액은_음수가_안_된다() throws Exception {
		String access = rich(E, 100);
		CountDownLatch start = new CountDownLatch(1);
		ExecutorService pool = Executors.newFixedThreadPool(2);
		List<Future<Integer>> results = new ArrayList<>();
		for (int i = 0; i < 2; i++) {
			results.add(pool.submit(() -> {
				start.await();
				return buy(access, "BALL", 2).andReturn().getResponse().getStatus();
			}));
		}
		start.countDown();
		List<Integer> statuses = new ArrayList<>();
		for (Future<Integer> f : results) {
			statuses.add(f.get(20, TimeUnit.SECONDS));
		}
		pool.shutdown();

		assertThat(statuses).containsExactlyInAnyOrder(201, 422);
		assertThat(gold()).isZero();
		assertThat(jdbc.queryForObject("select quantity from shop.inventory", Integer.class)).isEqualTo(2);
	}
}
