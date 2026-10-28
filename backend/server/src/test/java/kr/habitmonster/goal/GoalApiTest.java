package kr.habitmonster.goal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
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

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Test;
import org.skyscreamer.jsonassert.JSONAssert;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;

/**
 * 목표 등록 · 수정 · 삭제 · 완료 (API 명세 v5 8장 + 보충 10-28, 4-2단계). 기본 온보딩 = 주간 목표 "헬스장 3번 가기" 1개.
 * 기간은 등록한 날부터 주간 7일 · 월간 30일. 날이 지난 것은 {@code period_start}를 SQL로 앞당겨 흉내 낸다.
 */
class GoalApiTest extends PostgresTest {

	static final String E = "a@habit.kr";

	@Autowired
	BusinessDates dates;

	ResultActions add(String access, String key, String body) throws Exception {
		return mvc.perform(post("/goals").header("Authorization", "Bearer " + access)
			.header(IdempotencyFilter.HEADER, key).contentType(MediaType.APPLICATION_JSON).content(body));
	}

	ResultActions addTitled(String access, String type, String title) throws Exception {
		return add(access, UUID.randomUUID().toString(), "{\"goalType\": \"" + type + "\", \"title\": \"" + title + "\"}");
	}

	ResultActions edit(String access, long goalId, String body) throws Exception {
		return mvc.perform(patch("/goals/" + goalId).header("Authorization", "Bearer " + access)
			.contentType(MediaType.APPLICATION_JSON).content(body));
	}

	ResultActions remove(String access, long goalId) throws Exception {
		return mvc.perform(delete("/goals/" + goalId).header("Authorization", "Bearer " + access));
	}

	ResultActions complete(String access, long goalId, String key) throws Exception {
		return mvc.perform(post("/goals/" + goalId + "/complete").header("Authorization", "Bearer " + access)
			.header(IdempotencyFilter.HEADER, key));
	}

	ResultActions complete(String access, long goalId) throws Exception {
		return complete(access, goalId, UUID.randomUUID().toString());
	}

	ResultActions list(String access) throws Exception {
		return mvc.perform(get("/goals").header("Authorization", "Bearer " + access));
	}

	long goalId(String title) {
		return jdbc.queryForObject("select id from goal.goal where title = ?", Long.class, title);
	}

	long idOf(ResultActions res) throws Exception {
		return ((Number) JsonPath.read(res.andReturn().getResponse().getContentAsString(), "$.goalId")).longValue();
	}

	/** {@code days}일 전에 등록한 것으로. */
	void registeredDaysAgo(long goalId, int days) {
		jdbc.update("update goal.goal set period_start = ? where id = ?", dates.today().minusDays(days), goalId);
	}

	long gold() {
		return jdbc.queryForObject("select balance from wallet.wallet", Long.class);
	}

	// ---------- 등록 ----------
	@Test
	void 등록하면_오늘부터_주간_7일_월간_30일() throws Exception {
		String access = onboardedUser(E);
		add(access, UUID.randomUUID().toString(), "{\"goalType\": \"WEEKLY\", \"title\": \" 전공 2챕터 \", \"detail\": \"\"}")
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.goalType").value("WEEKLY"))
			.andExpect(jsonPath("$.periodStart").value(dates.today().toString()))
			.andExpect(jsonPath("$.periodEnd").value(dates.today().plusDays(6).toString()))
			.andExpect(jsonPath("$.title").value("전공 2챕터"))
			.andExpect(jsonPath("$.detail").doesNotExist()) // 빈 상세 → 없음
			.andExpect(jsonPath("$.status").value("ACTIVE"));
		addTitled(access, "MONTHLY", "책 2권")
			.andExpect(jsonPath("$.periodEnd").value(dates.today().plusDays(29).toString()));

		list(access).andExpect(jsonPath("$.weekly.slotsUsed").value(2))
			.andExpect(jsonPath("$.weekly.goals[1].title").value("전공 2챕터"))
			.andExpect(jsonPath("$.monthly.slotsUsed").value(1))
			.andExpect(jsonPath("$.monthly.rewardGold").value(150))
			.andExpect(jsonPath("$.monthly.goals[0].periodStart").value(dates.today().toString()));
	}

	@Test
	void 값이_틀리면_400() throws Exception {
		String access = onboardedUser(E);
		add(access, UUID.randomUUID().toString(), "{\"goalType\": \"DAILY\", \"title\": \"   \", \"detail\": \"" + "가".repeat(501) + "\"}")
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.errors[*].field", containsInAnyOrder("goalType", "title", "detail")));
		addTitled(access, "WEEKLY", "가".repeat(51)).andExpect(status().isBadRequest());
		addTitled(access, "WEEKLY", "가".repeat(50)).andExpect(status().isCreated());
	}

	@Test
	void 칸이_차면_422() throws Exception {
		String access = onboardedUser(E); // 주간 1개
		addTitled(access, "WEEKLY", "2").andExpect(status().isCreated());
		addTitled(access, "WEEKLY", "3").andExpect(status().isCreated());
		addTitled(access, "WEEKLY", "4").andExpect(status().isUnprocessableContent())
			.andExpect(jsonPath("$.code").value("GOAL_SLOT_FULL"));
		addTitled(access, "MONTHLY", "월1").andExpect(status().isCreated());
		addTitled(access, "MONTHLY", "월2").andExpect(jsonPath("$.code").value("GOAL_SLOT_FULL"));
	}

	@Test
	void 완료해도_기간_동안은_칸을_차지하고_기간이_끝나면_빈다() throws Exception {
		String access = onboardedUser(E);
		addTitled(access, "WEEKLY", "2");
		addTitled(access, "WEEKLY", "3");
		long first = goalId("헬스장 3번 가기");
		registeredDaysAgo(first, 1);
		complete(access, first).andExpect(status().isOk());
		addTitled(access, "WEEKLY", "4").andExpect(jsonPath("$.code").value("GOAL_SLOT_FULL")); // 완료 즉시 비우지 않음

		registeredDaysAgo(first, 6); // 마지막 날 — 아직 목록에 있다
		list(access).andExpect(jsonPath("$.weekly.slotsUsed").value(3))
			.andExpect(jsonPath("$.weekly.goals[0].status").value("COMPLETED"));
		registeredDaysAgo(first, 7); // 기간 끝 → 빠지고 칸이 빈다
		list(access).andExpect(jsonPath("$.weekly.slotsUsed").value(2));
		addTitled(access, "WEEKLY", "4").andExpect(status().isCreated());
	}

	@Test
	void 기간이_끝난_진행_중_목표도_칸에서_빠진다() throws Exception {
		String access = onboardedUser(E);
		addTitled(access, "MONTHLY", "책");
		registeredDaysAgo(goalId("책"), 30);
		list(access).andExpect(jsonPath("$.monthly.slotsUsed").value(0));
		addTitled(access, "MONTHLY", "책 다시").andExpect(status().isCreated());
	}

	@Test
	void 같은_키로_다시_보내면_목표는_하나만() throws Exception {
		String access = onboardedUser(E);
		String key = UUID.randomUUID().toString();
		String body = "{\"goalType\": \"WEEKLY\", \"title\": \"전공\"}";
		String first = add(access, key, body).andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
		String again = add(access, key, body).andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
		JSONAssert.assertEquals(first, again, true);
		assertThat(jdbc.queryForObject("select count(*) from goal.goal where title = '전공'", Integer.class)).isEqualTo(1);
	}

	// ---------- 수정 · 삭제 ----------
	@Test
	void 수정은_보낸_필드만_바꾸고_null인_상세는_지운다() throws Exception {
		String access = onboardedUser(E);
		long id = idOf(add(access, UUID.randomUUID().toString(),
				"{\"goalType\": \"WEEKLY\", \"title\": \"전공\", \"detail\": \"5장\"}"));
		edit(access, id, "{\"title\": \"전공 2챕터\"}").andExpect(status().isOk())
			.andExpect(jsonPath("$.title").value("전공 2챕터"))
			.andExpect(jsonPath("$.detail").value("5장"));
		edit(access, id, "{}").andExpect(jsonPath("$.detail").value("5장"));
		edit(access, id, "{\"detail\": null}").andExpect(status().isOk())
			.andExpect(jsonPath("$.title").value("전공 2챕터"))
			.andExpect(jsonPath("$.detail").doesNotExist());
		edit(access, id, "{\"title\": null}").andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.errors[0].field").value("title"));
		edit(access, id, "{\"goalType\": \"MONTHLY\"}").andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.errors[0].field").value("goalType"));
		edit(access, id, "{\"detail\": 3}").andExpect(status().isBadRequest());
	}

	@Test
	void 삭제하면_칸이_바로_빈다() throws Exception {
		String access = onboardedUser(E);
		addTitled(access, "WEEKLY", "2");
		addTitled(access, "WEEKLY", "3");
		long first = goalId("헬스장 3번 가기");
		remove(access, first).andExpect(status().isNoContent());
		list(access).andExpect(jsonPath("$.weekly.slotsUsed").value(2));
		addTitled(access, "WEEKLY", "4").andExpect(status().isCreated());
		remove(access, first).andExpect(status().isNotFound()); // 삭제한 목표는 없는 것
		edit(access, first, "{\"title\": \"x\"}").andExpect(status().isNotFound());
	}

	// ---------- 완료 ----------
	@Test
	void 완료하면_보상_골드와_원장() throws Exception {
		String access = onboardedUser(E);
		long weekly = goalId("헬스장 3번 가기");
		long monthly = idOf(addTitled(access, "MONTHLY", "책"));
		registeredDaysAgo(weekly, 1);
		registeredDaysAgo(monthly, 29); // 월간 마지막 날

		complete(access, weekly).andExpect(status().isOk())
			.andExpect(jsonPath("$.goalId").value(weekly))
			.andExpect(jsonPath("$.status").value("COMPLETED"))
			.andExpect(jsonPath("$.goldAwarded").value(40))
			.andExpect(jsonPath("$.gold").value(40));
		complete(access, monthly).andExpect(jsonPath("$.goldAwarded").value(150)).andExpect(jsonPath("$.gold").value(190));

		assertThat(gold()).isEqualTo(190);
		assertThat(jdbc.queryForList("select reason_code || ' ' || ref_id || ' ' || amount from wallet.wallet_ledger order by id",
				String.class)).containsExactly("GOAL_WEEKLY " + weekly + " 40", "GOAL_MONTHLY " + monthly + " 150");
	}

	@Test
	void 등록한_날에는_완료할_수_없다() throws Exception {
		String access = onboardedUser(E);
		complete(access, goalId("헬스장 3번 가기")).andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("GOAL_TOO_EARLY"))
			.andExpect(jsonPath("$.message").value("목표는 다음 날부터 완료할 수 있어요"));
		assertThat(gold()).isZero();
	}

	@Test
	void 완료한_목표는_수정_삭제_완료_모두_409() throws Exception {
		String access = onboardedUser(E);
		long id = goalId("헬스장 3번 가기");
		registeredDaysAgo(id, 2);
		complete(access, id).andExpect(status().isOk());
		complete(access, id).andExpect(jsonPath("$.code").value("GOAL_COMPLETED"));
		edit(access, id, "{\"title\": \"x\"}").andExpect(jsonPath("$.code").value("GOAL_COMPLETED"));
		remove(access, id).andExpect(jsonPath("$.code").value("GOAL_COMPLETED"));
		assertThat(gold()).isEqualTo(40);
	}

	@Test
	void 기간이_끝난_목표는_수정_삭제_완료_모두_409() throws Exception {
		String access = onboardedUser(E);
		long id = goalId("헬스장 3번 가기");
		registeredDaysAgo(id, 7);
		complete(access, id).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("GOAL_PERIOD_ENDED"));
		edit(access, id, "{\"title\": \"x\"}").andExpect(jsonPath("$.code").value("GOAL_PERIOD_ENDED"));
		remove(access, id).andExpect(jsonPath("$.code").value("GOAL_PERIOD_ENDED"));
	}

	@Test
	void 남의_목표는_404() throws Exception {
		onboardedUser(E);
		long id = goalId("헬스장 3번 가기");
		registeredDaysAgo(id, 1);
		String other = onboardedUser("b@habit.kr");
		complete(other, id).andExpect(status().isNotFound());
		edit(other, id, "{\"title\": \"x\"}").andExpect(status().isNotFound());
		remove(other, id).andExpect(status().isNotFound());
	}

	@Test
	void 같은_키로_다시_완료하면_첫_응답이고_골드는_한_번() throws Exception {
		String access = onboardedUser(E);
		long id = goalId("헬스장 3번 가기");
		registeredDaysAgo(id, 1);
		String key = UUID.randomUUID().toString();
		String first = complete(access, id, key).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
		String again = complete(access, id, key).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
		JSONAssert.assertEquals(first, again, true);
		assertThat(gold()).isEqualTo(40);
	}

	@Test
	void 다른_키로_동시에_완료해도_골드는_한_번() throws Exception {
		String access = onboardedUser(E);
		long id = goalId("헬스장 3번 가기");
		registeredDaysAgo(id, 1);
		CountDownLatch start = new CountDownLatch(1);
		ExecutorService pool = Executors.newFixedThreadPool(2);
		List<Future<Integer>> results = new ArrayList<>();
		for (int i = 0; i < 2; i++) {
			results.add(pool.submit(() -> {
				start.await();
				return complete(access, id).andReturn().getResponse().getStatus();
			}));
		}
		start.countDown();
		List<Integer> statuses = new ArrayList<>();
		for (Future<Integer> f : results) {
			statuses.add(f.get(20, TimeUnit.SECONDS));
		}
		pool.shutdown();

		assertThat(statuses).containsExactlyInAnyOrder(200, 409);
		assertThat(gold()).isEqualTo(40);
	}
}
