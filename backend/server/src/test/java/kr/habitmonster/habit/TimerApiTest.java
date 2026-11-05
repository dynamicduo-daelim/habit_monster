package kr.habitmonster.habit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.LocalDate;
import java.util.UUID;

import com.jayway.jsonpath.JsonPath;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;

/**
 * 습관 타이머 (API 명세 v6 9장, D-62 · D-63). 기본 온보딩의 "아침 러닝"(운동 시간, 분) + 공부 시간(분) · 학습량(p) 습관.
 * 시간이 흐른 것은 SQL로 시작 · 일시정지 시각을 앞당겨 흉내 낸다 (서버 시계는 그대로).
 */
class TimerApiTest extends PostgresTest {

	static final String E = "t@habit.kr";

	@Autowired
	BusinessDates dates;

	String access;
	long running; // 아침 러닝 (운동 시간, 분)
	long study; // 전공 공부 (공부 시간, 분)
	long pages; // 문제집 (학습량, p) — 타이머 못 씀

	@BeforeEach
	void user() throws Exception {
		access = onboardedUser(E);
		running = jdbc.queryForObject("select id from habit.habit where name = '아침 러닝'", Long.class);
		study = addHabit(4, "전공 공부", 60);
		pages = addHabit(5, "문제집", 20);
	}

	long addHabit(int measure, String name, int target) throws Exception {
		String res = mvc.perform(post("/habits").header("Authorization", "Bearer " + access)
				.header(IdempotencyFilter.HEADER, UUID.randomUUID().toString()).contentType(MediaType.APPLICATION_JSON)
				.content("{\"categoryCode\": \"st\", \"measureTypeId\": " + measure + ", \"name\": \"" + name
						+ "\", \"dailyTarget\": " + target + ", \"periodCode\": \"D30\"}"))
			.andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
		return ((Number) JsonPath.read(res, "$.habitId")).longValue();
	}

	ResultActions start(long habitId) throws Exception {
		return start(habitId, dates.today());
	}

	ResultActions start(long habitId, LocalDate day) throws Exception {
		return mvc.perform(post("/timers").header("Authorization", "Bearer " + access)
			.header(IdempotencyFilter.HEADER, UUID.randomUUID().toString()).contentType(MediaType.APPLICATION_JSON)
			.content("{\"businessDate\": \"" + day + "\", \"habitId\": " + habitId + "}"));
	}

	ResultActions act(long timerId, String body) throws Exception {
		return mvc.perform(patch("/timers/" + timerId).header("Authorization", "Bearer " + access)
			.header(IdempotencyFilter.HEADER, UUID.randomUUID().toString()).contentType(MediaType.APPLICATION_JSON)
			.content(body));
	}

	ResultActions today() throws Exception {
		return mvc.perform(get("/timers/today").header("Authorization", "Bearer " + access));
	}

	long idOf(ResultActions res) throws Exception {
		return ((Number) JsonPath.read(res.andReturn().getResponse().getContentAsString(), "$.timerId")).longValue();
	}

	/** 시작 시각을 {@code minutes}분 앞당긴다 = 그만큼 잰 것으로. */
	void ago(long timerId, int minutes) {
		jdbc.update("update habit.habit_timer set started_at = started_at - make_interval(mins => ?) where id = ?", minutes,
				timerId);
	}

	@Test
	void 시작하면_도는_타이머가_생기고_오늘_목록에_보인다() throws Exception {
		long id = idOf(start(running).andExpect(status().isCreated())
			.andExpect(jsonPath("$.status").value("RUNNING"))
			.andExpect(jsonPath("$.habitId").value(running))
			.andExpect(jsonPath("$.elapsedSeconds").value(0))
			.andExpect(jsonPath("$.endReason").value(nullValue())));

		today().andExpect(status().isOk())
			.andExpect(jsonPath("$.active", hasSize(1)))
			.andExpect(jsonPath("$.active[0].timerId").value(id))
			.andExpect(jsonPath("$.habits", hasSize(0)));
	}

	@Test
	void 끝내면_경과_분이_기록되고_집중_분을_보내면_작은_값() throws Exception {
		long a = idOf(start(running));
		ago(a, 50);
		act(a, "{\"action\": \"STOP\"}").andExpect(status().isOk())
			.andExpect(jsonPath("$.status").value("STOPPED"))
			.andExpect(jsonPath("$.endReason").value("USER"))
			.andExpect(jsonPath("$.todayMinutes").value(50));

		// 뽀모도로: 서버는 50분 쟀지만 앱이 집중 40분이라고 보냄 → 40 / 앱이 더 크게 보내도 서버 경과까지만
		long b = idOf(start(running));
		ago(b, 50);
		act(b, "{\"action\": \"STOP\", \"focusMinutes\": 40}").andExpect(jsonPath("$.todayMinutes").value(90));
		long c = idOf(start(running));
		ago(c, 10);
		act(c, "{\"action\": \"STOP\", \"focusMinutes\": 999}").andExpect(jsonPath("$.todayMinutes").value(100));

		today().andExpect(jsonPath("$.active", hasSize(0)))
			.andExpect(jsonPath("$.habits[0].habitId").value(running))
			.andExpect(jsonPath("$.habits[0].todayMinutes").value(100))
			.andExpect(jsonPath("$.habits[0].sessions").value(3));
	}

	@Test
	void 일시정지한_시간은_빼고_센다() throws Exception {
		long id = idOf(start(study));
		act(id, "{\"action\": \"PAUSE\"}").andExpect(jsonPath("$.status").value("PAUSED"));
		// 60분 전에 시작해 20분 전에 일시정지 = 40분 잼, 그 뒤 20분은 쉬는 중
		jdbc.update("""
			update habit.habit_timer set started_at = started_at - interval '60 minutes',
			       paused_at = paused_at - interval '20 minutes' where id = ?""", id);
		act(id, "{\"action\": \"PAUSE\"}").andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PAUSED"));
		act(id, "{\"action\": \"STOP\"}").andExpect(jsonPath("$.todayMinutes").value(40));
		assertThat(jdbc.queryForObject("select paused_seconds from habit.habit_timer where id = ?", Integer.class, id))
			.isBetween(1199, 1201);
	}

	@Test
	void 같은_습관은_하나_도는_것은_사람당_하나_일시정지한_것은_여러_개() throws Exception {
		long a = idOf(start(running));
		start(running).andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("TIMER_ALREADY_RUNNING"))
			.andExpect(jsonPath("$.timerId").value(a));
		start(study).andExpect(status().isConflict()).andExpect(jsonPath("$.timerId").value(a));

		act(a, "{\"action\": \"PAUSE\"}").andExpect(status().isOk());
		long b = idOf(start(study).andExpect(status().isCreated()));
		act(a, "{\"action\": \"RESUME\"}").andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("TIMER_ALREADY_RUNNING"))
			.andExpect(jsonPath("$.timerId").value(b));
		today().andExpect(jsonPath("$.active", hasSize(2)));

		act(b, "{\"action\": \"PAUSE\"}").andExpect(status().isOk());
		act(a, "{\"action\": \"RESUME\"}").andExpect(status().isOk()).andExpect(jsonPath("$.status").value("RUNNING"));
	}

	@Test
	void 분_단위_시간_습관만_본인_습관만_오늘_날짜만() throws Exception {
		start(pages).andExpect(status().isUnprocessableContent()).andExpect(jsonPath("$.code").value("NOT_TIMER_HABIT"));
		start(999_999).andExpect(status().isNotFound());
		start(running, dates.today().minusDays(1)).andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("BUSINESS_DATE_CHANGED"));
	}

	@Test
	void 남의_타이머는_404() throws Exception {
		long mine = idOf(start(running));
		access = onboardedUser("other@habit.kr");
		act(mine, "{\"action\": \"STOP\"}").andExpect(status().isNotFound());
	}

	@Test
	void 잘못된_요청은_400() throws Exception {
		long id = idOf(start(running));
		act(id, "{\"action\": \"JUMP\"}").andExpect(status().isBadRequest());
		act(id, "{\"action\": \"STOP\", \"focusMinutes\": -1}").andExpect(status().isBadRequest());
		act(id, "{\"action\": \"PAUSE\", \"focusMinutes\": 10}").andExpect(status().isBadRequest());
	}

	@Test
	void 최대_시간에_닿으면_그_시각에_자동_종료되고_끝난_날_기록() throws Exception {
		// 5시간 전에 시작하고 잊음(시작한 날은 어제로 적어 둠) → 시작 + 240분에 끝난 것, 기록되는 날 = 그 끝난 시각의 날
		long id = idOf(start(running));
		jdbc.update("""
			update habit.habit_timer set business_date = ?, started_at = started_at - interval '5 hours' where id = ?""",
				dates.today().minusDays(1), id);

		today().andExpect(jsonPath("$.active", hasSize(0)));
		assertThat(jdbc.queryForObject("""
			select abs(extract(epoch from ended_at - started_at) - 240 * 60) < 1   -- 서버는 밀리초까지 읽음 (DB는 마이크로초)
			   and business_date = (ended_at at time zone 'Asia/Seoul')::date
			   and counted_minutes = 240 and end_reason = 'MAX_DURATION'
			  from habit.habit_timer where id = ?""", Boolean.class, id)).isTrue();
		act(id, "{\"action\": \"STOP\"}").andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("TIMER_NOT_RUNNING"))
			.andExpect(jsonPath("$.endReason").value("MAX_DURATION"));
	}

	@Test
	void 날을_넘겨도_끊지_않고_끝난_날에_전부() throws Exception {
		// 어제 시작한 타이머(30분 전 시작)를 오늘 끝내면 오늘 기록. 00시 자동 종료는 없다
		long id = idOf(start(running));
		ago(id, 30);
		jdbc.update("update habit.habit_timer set business_date = ? where id = ?", dates.today().minusDays(1), id);
		today().andExpect(jsonPath("$.active", hasSize(1)));
		act(id, "{\"action\": \"STOP\"}").andExpect(jsonPath("$.todayMinutes").value(30));
		assertThat(jdbc.queryForObject("select business_date from habit.habit_timer where id = ?", LocalDate.class, id))
			.isEqualTo(dates.today());
	}

	@Test
	void 습관을_그만두면_타이머도_함께_끝난다() throws Exception {
		long id = idOf(start(study));
		ago(id, 15);
		mvc.perform(post("/habits/" + study + "/stop").header("Authorization", "Bearer " + access))
			.andExpect(status().isOk());
		act(id, "{\"action\": \"STOP\"}").andExpect(status().isConflict())
			.andExpect(jsonPath("$.endReason").value("HABIT_STOPPED"));
		assertThat(jdbc.queryForObject("select counted_minutes from habit.habit_timer where id = ?", Integer.class, id))
			.isEqualTo(15);
		start(study).andExpect(status().isUnprocessableContent()).andExpect(jsonPath("$.code").value("NOT_TIMER_HABIT"));
	}

	@Test
	void 중복_방지_키_같으면_한_번만() throws Exception {
		String key = UUID.randomUUID().toString();
		String body = "{\"businessDate\": \"" + dates.today() + "\", \"habitId\": " + running + "}";
		for (int i = 0; i < 2; i++) {
			mvc.perform(post("/timers").header("Authorization", "Bearer " + access).header(IdempotencyFilter.HEADER, key)
				.contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isCreated());
		}
		assertThat(jdbc.queryForObject("select count(*) from habit.habit_timer", Integer.class)).isEqualTo(1);
	}
}
