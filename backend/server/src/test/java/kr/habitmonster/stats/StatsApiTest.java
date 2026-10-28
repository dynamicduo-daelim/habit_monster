package kr.habitmonster.stats;

import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.LocalDate;
import java.util.UUID;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * 통계 (API 명세 v5 "6. 통계", 4-4단계). 기본 온보딩 = 운동 · 공부, 습관 "아침 러닝"(운동 30분) 1개.
 * 지난 날의 출석 · 체크인은 SQL로 넣는다 (오늘 것은 실제 API로).
 */
class StatsApiTest extends PostgresTest {

	static final String E = "a@habit.kr";

	@Autowired
	BusinessDates dates;

	ResultActions as(String access, MockHttpServletRequestBuilder req) throws Exception {
		return mvc.perform(req.header("Authorization", "Bearer " + access));
	}

	ResultActions checkin(String access, MockHttpServletRequestBuilder req, long habitId, int value) throws Exception {
		return as(access, req.header(IdempotencyFilter.HEADER, UUID.randomUUID().toString())
			.contentType(MediaType.APPLICATION_JSON)
			.content("{\"businessDate\": \"" + dates.today() + "\", \"answers\": [{\"habitId\": " + habitId
					+ ", \"done\": true, \"value\": " + value + "}]}"));
	}

	long habitId() {
		return jdbc.queryForObject("select id from habit.habit where name = '아침 러닝'", Long.class);
	}

	void attendedOn(long user, LocalDate day) {
		jdbc.update("insert into habit.attendance (user_id, attended_on) values (?, ?)", user, day);
	}

	/** 지난 날 체크인 1건 (아침 러닝 하나, 최신 점수 {@code score}). */
	void checkedInOn(long user, LocalDate day, int score) {
		long id = jdbc.queryForObject("""
			insert into habit.daily_checkin (user_id, checkin_date, habit_count, total_score, counted_score)
			values (?, ?, 1, ?, ?) returning id""", Long.class, user, day, score, score);
		jdbc.update("""
			insert into habit.habit_checkin (daily_checkin_id, habit_id, period_seq, value, target_snapshot, score,
			                                 rewarded_value, rewarded_score, is_counted, is_filled)
			values (?, ?, 1, 15, 30, ?, 15, ?, true, true)""", id, habitId(), score, score);
	}

	@Test
	void 첫날은_오늘만_있고_평균은_없다() throws Exception {
		String access = onboardedUser(E);
		as(access, post("/me/attendance")).andExpect(status().isOk());
		LocalDate today = dates.today();
		as(access, get("/stats")).andExpect(status().isOk())
			.andExpect(jsonPath("$.attendance.currentStreak").value(1))
			.andExpect(jsonPath("$.attendance.longestStreak").value(1))
			.andExpect(jsonPath("$.attendance.last14Days.length()").value(14))
			.andExpect(jsonPath("$.attendance.last14Days[0].date").value(today.minusDays(13).toString()))
			.andExpect(jsonPath("$.attendance.last14Days[0].attended").value(false))
			.andExpect(jsonPath("$.attendance.last14Days[13].date").value(today.toString()))
			.andExpect(jsonPath("$.attendance.last14Days[13].attended").value(true))
			.andExpect(jsonPath("$.sincerity.last7Days.length()").value(7))
			.andExpect(jsonPath("$.sincerity.last7Days[6].date").value(today.toString()))
			.andExpect(jsonPath("$.sincerity.last7Days[6].dayOfWeek").value(today.getDayOfWeek().name().substring(0, 3)))
			.andExpect(jsonPath("$.sincerity.last7Days[6].rate").value(nullValue()))
			.andExpect(jsonPath("$.sincerity.averageRate").value(nullValue()));
	}

	@Test
	void 출석_14일은_범위_안만_성실도는_최신_값이고_평균은_한_날만() throws Exception {
		String access = onboardedUser(E);
		long user = userIdOf(E);
		LocalDate today = dates.today();
		attendedOn(user, today.minusDays(14)); // 범위 밖
		attendedOn(user, today.minusDays(13));
		attendedOn(user, today.minusDays(3));
		checkedInOn(user, today.minusDays(2), 16); // 80%
		checkedInOn(user, today.minusDays(7), 20); // 범위 밖

		checkin(access, post("/checkins/today"), habitId(), 30).andExpect(status().isCreated()); // 20점 = 100%
		checkin(access, put("/checkins/today"), habitId(), 15).andExpect(status().isOk()); // 다시 체크 → 10점 = 50%

		as(access, get("/stats"))
			.andExpect(jsonPath("$.attendance.last14Days[0].attended").value(true))
			.andExpect(jsonPath("$.attendance.last14Days[10].attended").value(true))
			.andExpect(jsonPath("$.attendance.last14Days[11].attended").value(false))
			.andExpect(jsonPath("$.sincerity.last7Days[0].rate").value(nullValue()))
			.andExpect(jsonPath("$.sincerity.last7Days[4].rate").value(80))
			.andExpect(jsonPath("$.sincerity.last7Days[6].rate").value(50))
			.andExpect(jsonPath("$.sincerity.averageRate").value(65));
	}

	@Test
	void 카테고리는_연_것만_레벨_잠긴_것은_레벨_없음_최대_레벨은_필요량_null() throws Exception {
		String access = onboardedUser(E);
		long user = userIdOf(E);
		checkin(access, post("/checkins/today"), habitId(), 30).andExpect(status().isCreated()); // 운동 경험치 20 → Lv.2
		jdbc.update("update habit.user_category set level = 20, exp_total = 1900 where user_id = ? and category_code = 'st'", user);

		as(access, get("/stats"))
			.andExpect(jsonPath("$.categories.length()").value(6))
			.andExpect(jsonPath("$.categories[0].code").value("ex"))
			.andExpect(jsonPath("$.categories[0].name").value("운동"))
			.andExpect(jsonPath("$.categories[0].opened").value(true))
			.andExpect(jsonPath("$.categories[0].level").value(2))
			.andExpect(jsonPath("$.categories[0].maxLevel").value(20))
			.andExpect(jsonPath("$.categories[0].expInLevel").value(10))
			.andExpect(jsonPath("$.categories[0].expRequired").value(20))
			.andExpect(jsonPath("$.categories[0].levelUpGold").value(20))
			.andExpect(jsonPath("$.categories[1].level").value(20))
			.andExpect(jsonPath("$.categories[1].expInLevel").value(0))
			.andExpect(jsonPath("$.categories[1].expRequired").value(nullValue()))
			.andExpect(jsonPath("$.categories[2].opened").value(false))
			.andExpect(jsonPath("$.categories[2].level").doesNotExist())
			.andExpect(jsonPath("$.categories[2].expRequired").doesNotExist());
	}
}
