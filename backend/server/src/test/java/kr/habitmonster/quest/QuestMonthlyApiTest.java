package kr.habitmonster.quest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.mockito.Mockito.doReturn;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.config.BalanceConfig;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * 퀘스트 4단계 — 월간 배지 (API 명세 v11 10장, 결정 D-96). 그달 완료 수를 카운터로 세고, 목표에 닿으면 배지 + 성실볼 선물.
 * 완료는 원숭이 쓰다듬기 · 말 걸기 · 체크인 첫 제출(일일 퀘스트 1개씩)로 만든다. 목표는 설정값을 바꿔 작게 한다
 * (실제 값 20은 DB verify S-37이 확인).
 *
 * <p>바꿔 끼우는 빈은 {@code QuestWeeklyApiTest}와 같은 조합(BusinessDates · BalanceConfig) — Spring 테스트 컨텍스트를 같이 써서
 * 테스트 DB 연결 한도를 넘지 않게 (backend/CLAUDE.md, 11-26).
 */
class QuestMonthlyApiTest extends PostgresTest {

	static final String E = "m@habit.kr";

	@MockitoSpyBean
	BusinessDates dates;

	@MockitoSpyBean
	BalanceConfig config;

	ResultActions as(String access, MockHttpServletRequestBuilder req) throws Exception {
		return mvc.perform(req.header("Authorization", "Bearer " + access));
	}

	ResultActions quests(String access) throws Exception {
		return as(access, get("/quests"));
	}

	ResultActions badges(String access) throws Exception {
		return as(access, get("/quests/badges"));
	}

	/** 원숭이 쓰다듬기 → 일일 "몬스터 쓰다듬기" 완료 1개 (그날 첫 번째만). */
	ResultActions pet(String access) throws Exception {
		return as(access, post("/monsters/" + monkey() + "/affection").contentType(MediaType.APPLICATION_JSON)
			.content("{\"action\": \"PET\"}"));
	}

	/** 말 걸기 → 일일 "몬스터에게 말 걸기" 완료 1개. */
	void talk(String access) throws Exception {
		as(access, get("/monsters/" + monkey() + "/line")).andExpect(status().isOk());
	}

	/** 체크인 첫 제출 → 일일 "오늘의 기록" 완료 1개. */
	ResultActions checkin(String access) throws Exception {
		long habit = jdbc.queryForObject("select id from habit.habit where user_id = ? and name = '아침 러닝'", Long.class,
				userIdOf(E));
		return as(access, post("/checkins/today").header(IdempotencyFilter.HEADER, UUID.randomUUID().toString())
			.contentType(MediaType.APPLICATION_JSON)
			.content("{\"businessDate\": \"" + dates.today() + "\", \"answers\": [{\"habitId\": " + habit
					+ ", \"done\": true, \"value\": 30}]}"));
	}

	long monkey() {
		return jdbc.queryForObject("select id from monster.user_monster where user_id = ? and species_id = 1", Long.class,
				userIdOf(E));
	}

	/** 월간 배지 선물 (출처 QUEST_MONTHLY) — 제목 목록. */
	List<String> badgeGifts() {
		return jdbc.queryForList("select title from gift.gift where user_id = ? and source_code = 'QUEST_MONTHLY'",
				String.class, userIdOf(E));
	}

	void target(int n) {
		doReturn(n).when(config).questMonthlyTarget();
	}

	/** 다음 달 1일로 옮긴다. */
	LocalDate nextMonth() {
		LocalDate first = dates.monthStart().plusMonths(1);
		doReturn(first).when(dates).today();
		return first;
	}

	// ---------- 조회 ----------
	@Test
	void 조회하면_이번_달_진행이_보이고_목표는_설정값() throws Exception {
		String access = onboardedUser(E);
		quests(access).andExpect(status().isOk())
			.andExpect(jsonPath("$.monthly.monthStart").value(dates.monthStart().toString()))
			.andExpect(jsonPath("$.monthly.completed").value(0))
			.andExpect(jsonPath("$.monthly.target").value(20))
			.andExpect(jsonPath("$.monthly.badgeEarned").value(false));
		badges(access).andExpect(status().isOk()).andExpect(jsonPath("$.badges", hasSize(0)));
	}

	@Test
	void 퀘스트를_끄면_monthly는_null() throws Exception {
		String access = onboardedUser(E);
		doReturn(false).when(config).questEnabled();
		quests(access).andExpect(jsonPath("$.enabled").value(false)).andExpect(jsonPath("$.monthly").isEmpty());
	}

	// ---------- 배지 ----------
	@Test
	void 목표_전에는_없고_닿으면_배지와_볼_선물이_한_번만() throws Exception {
		String access = onboardedUser(E);
		target(2);
		pet(access).andExpect(status().isOk());
		quests(access).andExpect(jsonPath("$.monthly.completed").value(1))
			.andExpect(jsonPath("$.monthly.badgeEarned").value(false));
		assertThat(badgeGifts()).isEmpty();

		talk(access);
		quests(access).andExpect(jsonPath("$.monthly.completed").value(2))
			.andExpect(jsonPath("$.monthly.badgeEarned").value(true));
		assertThat(badgeGifts()).containsExactly(QuestService.badgeTitle(dates.monthStart()));
		assertThat(jdbc.queryForObject("""
			select item_code || ':' || item_quantity || ':' || gold from gift.gift
			 where user_id = ? and source_code = 'QUEST_MONTHLY'""", String.class, userIdOf(E))).isEqualTo("BALL:1:0");

		checkin(access).andExpect(status().isCreated()); // 3개째 — 목표를 넘어도 계속 세지만 배지는 그대로
		quests(access).andExpect(jsonPath("$.monthly.completed").value(3))
			.andExpect(jsonPath("$.monthly.badgeEarned").value(true));
		assertThat(badgeGifts()).hasSize(1);
		badges(access).andExpect(jsonPath("$.badges", hasSize(1)))
			.andExpect(jsonPath("$.badges[0].month").value(YearMonth.from(dates.monthStart()).toString()))
			.andExpect(jsonPath("$.badges[0].earnedAt").isNotEmpty());
	}

	@Test
	void 볼_선물을_받으면_가방에_성실볼이_들어간다() throws Exception {
		String access = onboardedUser(E);
		target(1);
		pet(access).andExpect(status().isOk());
		long gift = jdbc.queryForObject("select id from gift.gift where user_id = ? and source_code = 'QUEST_MONTHLY'",
				Long.class, userIdOf(E));
		as(access, post("/gifts/" + gift + "/claim").header(IdempotencyFilter.HEADER, UUID.randomUUID().toString()))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.items[0].itemCode").value("BALL"))
			.andExpect(jsonPath("$.ballCount").value(1));
	}

	// ---------- 달 ----------
	@Test
	void 달이_바뀌면_새로_세고_보관함엔_받은_달만() throws Exception {
		String access = onboardedUser(E);
		target(1);
		LocalDate thisMonth = dates.monthStart();
		pet(access).andExpect(status().isOk()); // 이번 달 배지

		LocalDate next = nextMonth(); // 다음 달 — 아무것도 안 함 (배지 없음)
		quests(access).andExpect(jsonPath("$.monthly.monthStart").value(next.toString()))
			.andExpect(jsonPath("$.monthly.completed").value(0))
			.andExpect(jsonPath("$.monthly.badgeEarned").value(false));

		LocalDate after = next.plusMonths(1); // 그다음 달 — 다시 배지
		doReturn(after).when(dates).today();
		pet(access).andExpect(status().isOk());
		quests(access).andExpect(jsonPath("$.monthly.completed").value(1))
			.andExpect(jsonPath("$.monthly.badgeEarned").value(true));

		badges(access).andExpect(jsonPath("$.badges", hasSize(2))) // 놓친 달은 없음, 최신순
			.andExpect(jsonPath("$.badges[0].month").value(YearMonth.from(after).toString()))
			.andExpect(jsonPath("$.badges[1].month").value(YearMonth.from(thisMonth).toString()));
		assertThat(badgeGifts()).hasSize(2);
	}

	// ---------- 시작값 ----------
	@Test
	void 그달_줄이_없으면_그달_기존_완료_수로_시작하고_그다음부터_더한다() throws Exception {
		String access = onboardedUser(E);
		pet(access).andExpect(status().isOk());
		talk(access);
		jdbc.update("delete from quest.user_month where user_id = ?", userIdOf(E)); // 이 기능 배포 전처럼

		quests(access).andExpect(jsonPath("$.monthly.completed").value(2)); // 기록에서 채움
		checkin(access).andExpect(status().isCreated());
		quests(access).andExpect(jsonPath("$.monthly.completed").value(3));
	}

	@Test
	void 줄이_없는_달의_첫_완료도_기존_완료를_더해_센다() throws Exception {
		String access = onboardedUser(E);
		pet(access).andExpect(status().isOk());
		jdbc.update("delete from quest.user_month where user_id = ?", userIdOf(E));

		talk(access); // 줄이 없을 때의 완료 — 시작값 = 1(방금 것) + 기존 1
		quests(access).andExpect(jsonPath("$.monthly.completed").value(2));
	}

	@Test
	void 조회할_때_이미_목표를_넘었으면_그때_배지를_준다() throws Exception {
		String access = onboardedUser(E);
		pet(access).andExpect(status().isOk());
		talk(access); // 목표 20이라 아직 배지 없음
		jdbc.update("delete from quest.user_month where user_id = ?", userIdOf(E));
		target(2); // 배포 전에 이미 채운 사용자 흉내

		quests(access).andExpect(jsonPath("$.monthly.completed").value(2))
			.andExpect(jsonPath("$.monthly.badgeEarned").value(true));
		assertThat(badgeGifts()).hasSize(1);
		quests(access); // 다시 조회해도 그대로
		assertThat(badgeGifts()).hasSize(1);
	}

	// ---------- 동시성 ----------
	@Test
	void 두_퀘스트가_동시에_완료돼도_둘_다_세고_배지는_한_번() throws Exception {
		String access = onboardedUser(E);
		target(2);
		CountDownLatch start = new CountDownLatch(1);
		ExecutorService pool = Executors.newFixedThreadPool(2);
		Future<Integer> c = pool.submit(() -> {
			start.await();
			return checkin(access).andReturn().getResponse().getStatus();
		});
		Future<Integer> p = pool.submit(() -> {
			start.await();
			return pet(access).andReturn().getResponse().getStatus();
		});
		start.countDown();
		assertThat(c.get(20, TimeUnit.SECONDS)).isEqualTo(201); // 교착이면 시간 초과
		assertThat(p.get(20, TimeUnit.SECONDS)).isEqualTo(200);
		pool.shutdown();

		quests(access).andExpect(jsonPath("$.monthly.completed").value(2))
			.andExpect(jsonPath("$.monthly.badgeEarned").value(true));
		assertThat(badgeGifts()).hasSize(1);
		assertThat(jdbc.queryForObject("select count(*) from quest.user_month where user_id = ?", Integer.class,
				userIdOf(E))).isEqualTo(1);
	}
}
