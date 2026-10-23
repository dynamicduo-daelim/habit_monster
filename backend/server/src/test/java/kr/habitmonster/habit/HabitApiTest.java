package kr.habitmonster.habit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

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
 * 습관 추가 · 연장 · 그만두기 (API 명세 v5 4장, 4-1단계). 기본 온보딩 = 운동 · 공부, 습관 "아침 러닝"(운동 30분 · 30일) 1개.
 * 칸 = 진행 중 + 기간 완료, 최대 5 · 최소 1 (사용자 결정 10-23).
 */
class HabitApiTest extends PostgresTest {

	static final String E = "a@habit.kr";

	@Autowired
	BusinessDates dates;

	ResultActions add(String access, String key, String body) throws Exception {
		return mvc.perform(post("/habits").header("Authorization", "Bearer " + access)
			.header(IdempotencyFilter.HEADER, key).contentType(MediaType.APPLICATION_JSON).content(body));
	}

	ResultActions add(String access, String name) throws Exception {
		return add(access, UUID.randomUUID().toString(), habit("st", 4, name, 60, "D7"));
	}

	static String habit(String category, Object measure, Object name, Object target, Object period) {
		return "{\"categoryCode\": \"" + category + "\", \"measureTypeId\": " + measure + ", \"name\": "
				+ (name == null ? "null" : "\"" + name + "\"") + ", \"dailyTarget\": " + target + ", \"periodCode\": "
				+ (period == null ? "null" : "\"" + period + "\"") + "}";
	}

	ResultActions renew(String access, long habitId, String body) throws Exception {
		return mvc.perform(post("/habits/" + habitId + "/renew").header("Authorization", "Bearer " + access)
			.header(IdempotencyFilter.HEADER, UUID.randomUUID().toString()).contentType(MediaType.APPLICATION_JSON)
			.content(body));
	}

	ResultActions stop(String access, long habitId) throws Exception {
		return mvc.perform(post("/habits/" + habitId + "/stop").header("Authorization", "Bearer " + access));
	}

	ResultActions list(String access) throws Exception {
		return mvc.perform(get("/habits").header("Authorization", "Bearer " + access));
	}

	long habitId(String name) {
		return jdbc.queryForObject("select id from habit.habit where name = ?", Long.class, name);
	}

	long idOf(ResultActions res) throws Exception {
		return ((Number) JsonPath.read(res.andReturn().getResponse().getContentAsString(), "$.habitId")).longValue();
	}

	/** 기간을 다 채운 상태로 (체크인 30번 대신 SQL — 체크인으로 기간이 끝나는 흐름은 CheckinApiTest가 본다). */
	void finishPeriod(long habitId) {
		jdbc.update("""
			update habit.habit_period set filled_days = period_days, ended_on = started_on + period_days, period_bonus = 0
			 where habit_id = ? and ended_on is null""", habitId);
		jdbc.update("update habit.habit set status = 'ENDED' where id = ?", habitId);
	}

	void checkInToday(String access) throws Exception {
		mvc.perform(post("/checkins/today").header("Authorization", "Bearer " + access)
			.header(IdempotencyFilter.HEADER, UUID.randomUUID().toString()).contentType(MediaType.APPLICATION_JSON)
			.content("{\"businessDate\": \"" + dates.today() + "\", \"answers\": [{\"habitId\": " + habitId("아침 러닝")
					+ ", \"done\": true, \"value\": 30}]}"))
			.andExpect(status().isCreated());
	}

	// ---------- 추가 ----------
	@Test
	void 추가하면_201_진행_중_0일부터_오늘_시작() throws Exception {
		String access = onboardedUser(E);
		add(access, UUID.randomUUID().toString(), habit("st", 4, "  전공 공부  ", 90, "D7"))
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.name").value("전공 공부"))
			.andExpect(jsonPath("$.categoryCode").value("st"))
			.andExpect(jsonPath("$.unit").value("분"))
			.andExpect(jsonPath("$.dailyTarget").value(90))
			.andExpect(jsonPath("$.periodCode").value("D7"))
			.andExpect(jsonPath("$.periodDays").value(7))
			.andExpect(jsonPath("$.filledDays").value(0))
			.andExpect(jsonPath("$.startDate").value(dates.today().toString()))
			.andExpect(jsonPath("$.status").value("ACTIVE"));
		list(access).andExpect(jsonPath("$.length()").value(2));
	}

	@Test
	void 오늘_체크인을_낸_뒤에_추가하면_내일부터() throws Exception {
		String access = onboardedUser(E);
		checkInToday(access);
		add(access, "전공 공부").andExpect(status().isCreated())
			.andExpect(jsonPath("$.startDate").value(dates.today().plusDays(1).toString()));
	}

	@Test
	void 값_형식이_틀리면_400() throws Exception {
		String access = onboardedUser(E);
		add(access, UUID.randomUUID().toString(), habit("st", 4, "", 60, "D7")).andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.errors[0].field").value("name"));
		add(access, UUID.randomUUID().toString(), habit("st", 4, "가".repeat(31), 60, "D7")).andExpect(status().isBadRequest());
		add(access, UUID.randomUUID().toString(), habit("st", 4, "공부", 0, "D7")).andExpect(status().isBadRequest());
		add(access, UUID.randomUUID().toString(), habit("st", 4, "공부", 901, "D7")).andExpect(status().isBadRequest()); // 상한 900분
		add(access, UUID.randomUUID().toString(), habit("st", 1, "공부", 60, "D7")).andExpect(status().isBadRequest()); // 운동 측정 항목
		add(access, UUID.randomUUID().toString(), habit("st", 4, "공부", 60, "D14")).andExpect(status().isBadRequest());
		assertThat(jdbc.queryForObject("select count(*) from habit.habit", Integer.class)).isEqualTo(1);
	}

	@Test
	void 열지_않은_카테고리면_422_CATEGORY_LOCKED() throws Exception {
		String access = onboardedUser(E);
		add(access, UUID.randomUUID().toString(), habit("md", 12, "명상", 10, "D7"))
			.andExpect(status().isUnprocessableContent()).andExpect(jsonPath("$.code").value("CATEGORY_LOCKED"));
	}

	@Test
	void 칸은_진행_중_더하기_기간_완료_5개까지() throws Exception {
		String access = onboardedUser(E);
		for (int i = 1; i <= 4; i++) {
			add(access, "공부 " + i).andExpect(status().isCreated());
		}
		add(access, "공부 5").andExpect(status().isUnprocessableContent()).andExpect(jsonPath("$.code").value("HABIT_LIMIT"));

		long first = habitId("아침 러닝");
		finishPeriod(first); // 기간 완료도 칸을 차지한다
		add(access, "공부 5").andExpect(jsonPath("$.code").value("HABIT_LIMIT"));

		stop(access, first).andExpect(status().isOk()); // 그만두면 자리가 생긴다
		add(access, "공부 5").andExpect(status().isCreated());
	}

	@Test
	void 같은_키로_다시_보내면_습관은_하나만() throws Exception {
		String access = onboardedUser(E);
		String key = UUID.randomUUID().toString();
		String body = habit("st", 4, "전공 공부", 60, "D30");
		String first = add(access, key, body).andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
		String again = add(access, key, body).andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
		JSONAssert.assertEquals(first, again, true);
		assertThat(jdbc.queryForObject("select count(*) from habit.habit where name = '전공 공부'", Integer.class)).isEqualTo(1);
	}

	// ---------- 연장 ----------
	@Test
	void 기간_완료_습관을_연장하면_새_기간_0일부터_이전_기간은_남는다() throws Exception {
		String access = onboardedUser(E);
		long id = habitId("아침 러닝");
		finishPeriod(id);
		list(access).andExpect(jsonPath("$[0].status").value("ENDED"));

		renew(access, id, "{\"periodCode\": \"D7\", \"dailyTarget\": 40}").andExpect(status().isOk())
			.andExpect(jsonPath("$.habitId").value(id))
			.andExpect(jsonPath("$.status").value("ACTIVE"))
			.andExpect(jsonPath("$.periodCode").value("D7"))
			.andExpect(jsonPath("$.periodDays").value(7))
			.andExpect(jsonPath("$.filledDays").value(0))
			.andExpect(jsonPath("$.dailyTarget").value(40))
			.andExpect(jsonPath("$.startDate").value(dates.today().toString()));
		assertThat(jdbc.queryForList("select filled_days from habit.habit_period where habit_id = ? order by seq",
				Integer.class, id)).containsExactly(30, 0);
	}

	@Test
	void 목표값을_생략하면_이전_값_체크인_뒤면_내일부터() throws Exception {
		String access = onboardedUser(E);
		checkInToday(access);
		long id = habitId("아침 러닝");
		finishPeriod(id);
		renew(access, id, "{\"periodCode\": \"D100\"}").andExpect(status().isOk())
			.andExpect(jsonPath("$.dailyTarget").value(30))
			.andExpect(jsonPath("$.periodDays").value(100))
			.andExpect(jsonPath("$.startDate").value(dates.today().plusDays(1).toString()));
	}

	@Test
	void 진행_중이거나_그만둔_습관은_409_HABIT_NOT_ENDED() throws Exception {
		String access = onboardedUser(E);
		long id = habitId("아침 러닝");
		renew(access, id, "{\"periodCode\": \"D7\"}").andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("HABIT_NOT_ENDED"));

		long other = idOf(add(access, "전공 공부"));
		stop(access, other).andExpect(status().isOk());
		renew(access, other, "{\"periodCode\": \"D7\"}").andExpect(jsonPath("$.code").value("HABIT_NOT_ENDED"));
	}

	@Test
	void 연장_값_형식이_틀리면_400_남의_습관은_404() throws Exception {
		String access = onboardedUser(E);
		long id = habitId("아침 러닝");
		finishPeriod(id);
		renew(access, id, "{\"periodCode\": \"D14\"}").andExpect(status().isBadRequest());
		renew(access, id, "{\"periodCode\": \"D7\", \"dailyTarget\": 601}").andExpect(status().isBadRequest()); // 상한 600분
		renew(access, id, "{\"periodCode\": \"D7\", \"dailyTarget\": 0}").andExpect(status().isBadRequest());

		String other = onboardedUser("b@habit.kr");
		renew(other, id, "{\"periodCode\": \"D7\"}").andExpect(status().isNotFound());
		list(access).andExpect(jsonPath("$[0].status").value("ENDED"));
	}

	// ---------- 그만두기 ----------
	@Test
	void 그만두면_목록에서_빠지고_기록은_남는다() throws Exception {
		String access = onboardedUser(E);
		long id = idOf(add(access, "전공 공부"));
		stop(access, id).andExpect(status().isOk())
			.andExpect(jsonPath("$.habitId").value(id))
			.andExpect(jsonPath("$.status").value("STOPPED"));
		list(access).andExpect(jsonPath("$.length()").value(1));
		mvc.perform(get("/habits?status=STOPPED").header("Authorization", "Bearer " + access))
			.andExpect(jsonPath("$[0].habitId").value(id));
		assertThat(jdbc.queryForObject("select stopped_at is not null from habit.habit where id = ?", Boolean.class, id)).isTrue();

		stop(access, id).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("HABIT_ALREADY_STOPPED"));
	}

	@Test
	void 마지막_1개는_그만둘_수_없다_422_LAST_HABIT() throws Exception {
		String access = onboardedUser(E);
		long run = habitId("아침 러닝");
		stop(access, run).andExpect(status().isUnprocessableContent()).andExpect(jsonPath("$.code").value("LAST_HABIT"));

		long study = idOf(add(access, "전공 공부"));
		finishPeriod(run);
		stop(access, study).andExpect(status().isOk()); // 기간 완료 1개가 남는다
		stop(access, run).andExpect(jsonPath("$.code").value("LAST_HABIT")); // 기간 완료도 마지막 1개면 못 그만둔다
	}

	@Test
	void 남의_습관은_404() throws Exception {
		String access = onboardedUser(E);
		long id = habitId("아침 러닝");
		String other = onboardedUser("b@habit.kr");
		stop(other, id).andExpect(status().isNotFound());
	}
}
