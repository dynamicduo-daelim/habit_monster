package kr.habitmonster.onboarding;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.hasItems;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.LocalDate;
import java.util.UUID;

import com.jayway.jsonpath.JsonPath;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Test;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/** 온보딩 · 출석 (API 명세 v5 "2. 온보딩" · "POST /me/attendance", 3-1단계). */
class OnboardingApiTest extends PostgresTest {

	@Autowired
	BusinessDates dates;

	ResultActions as(String access, MockHttpServletRequestBuilder req) throws Exception {
		return mvc.perform(req.header("Authorization", "Bearer " + access));
	}

	int count(String sql, Object... args) {
		return jdbc.queryForObject(sql, Integer.class, args);
	}

	@Test
	void 온보딩_전에는_카테고리_측정항목만_되고_출석은_403() throws Exception {
		String access = signUp("a@habit.kr");

		as(access, get("/categories")).andExpect(status().isOk())
			.andExpect(jsonPath("$.length()").value(6))
			.andExpect(jsonPath("$[0].code").value("ex"))
			.andExpect(jsonPath("$[0].opened").value(false))
			.andExpect(jsonPath("$[0].starter.speciesId").value(1))
			.andExpect(jsonPath("$[0].starter.imageKey").value("monkey"))
			.andExpect(jsonPath("$[0].starter.imageUrl").doesNotExist())
			.andExpect(jsonPath("$[4].starter.imageKey").value("squirrel"));

		as(access, get("/measure-types").param("categories", "sl,ex")).andExpect(status().isOk())
			.andExpect(jsonPath("$[0].categoryCode").value("ex")) // 카테고리 순서대로
			.andExpect(jsonPath("$[0].measureTypes[0].defaultTarget").value(30))
			.andExpect(jsonPath("$[0].measureTypes[0].rangeBelow").doesNotExist())
			.andExpect(jsonPath("$[0].presets[0].name").value("아침 러닝"))
			.andExpect(jsonPath("$[1].measureTypes[0].scoringMode").value("RANGE"))
			.andExpect(jsonPath("$[1].measureTypes[0].step").value(0.5))
			.andExpect(jsonPath("$[1].measureTypes[0].rangeAbove").value(1.5));
		as(access, get("/measure-types").param("categories", "ex,zz")).andExpect(status().isBadRequest());

		as(access, post("/me/attendance"))
			.andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("ONBOARDING_REQUIRED"));
	}

	@Test
	void 온보딩하면_모든_모듈의_행이_한_번에_생긴다() throws Exception {
		String access = signUp("a@habit.kr");
		String res = onboard(access, DEFAULT_ONBOARDING).andExpect(status().isCreated())
			.andExpect(jsonPath("$.starters.length()").value(2))
			.andExpect(jsonPath("$.starters[0].categoryCode").value("ex"))
			.andExpect(jsonPath("$.starters[0].imageKey").value("monkey"))
			.andExpect(jsonPath("$.starters[0].location").value("FIELD"))
			.andExpect(jsonPath("$.starters[1].imageKey").value("mouse"))
			.andExpect(jsonPath("$.habitIds.length()").value(1))
			.andExpect(jsonPath("$.goalIds.length()").value(1))
			.andReturn().getResponse().getContentAsString();
		long monkey = ((Number) JsonPath.read(res, "$.starters[0].userMonsterId")).longValue();
		assertThat(((Number) JsonPath.read(res, "$.partnerMonsterId")).longValue()).isEqualTo(monkey); // 운동 먼저
		long user = userIdOf("a@habit.kr");

		as(access, get("/me")).andExpect(jsonPath("$.onboarded").value(true));
		assertThat(count("select count(*) from habit.habit_user where user_id = ?", user)).isEqualTo(1);
		assertThat(count("select count(*) from habit.user_category where user_id = ? and opened_via = 'INITIAL' and level = 1",
				user)).isEqualTo(2);
		assertThat(jdbc.queryForObject("""
			select h.status || ' ' || p.seq || ' ' || p.period_code || ' ' || p.daily_target || ' ' || p.started_on
			  from habit.habit h join habit.habit_period p on p.habit_id = h.id where h.user_id = ?""", String.class, user))
			.isEqualTo("ACTIVE 1 D30 30.00 " + dates.today());
		assertThat(jdbc.queryForObject("select period_start from goal.goal where user_id = ?", LocalDate.class, user))
			.isEqualTo(dates.weekStart());
		assertThat(count("select dex_count from monster.monster_user where user_id = ?", user)).isEqualTo(2);
		assertThat(count("select count(*) from monster.user_monster where user_id = ? and affection = 3 and acquired_via = 'STARTER'",
				user)).isEqualTo(2);
		assertThat(count("select count(*) from monster.starter_grant where user_id = ?", user)).isEqualTo(2);
		assertThat(count("select count(*) from monster.dex_entry where user_id = ?", user)).isEqualTo(2);
		assertThat(count("select balance from wallet.wallet where user_id = ?", user)).isZero(); // 시작 골드 없음 (D-35)

		as(access, get("/categories")).andExpect(jsonPath("$[0].opened").value(true))
			.andExpect(jsonPath("$[2].opened").value(false));
		as(access, post("/me/attendance")).andExpect(status().isOk()); // 온보딩 전 차단이 풀림
	}

	@Test
	void 대화_상대는_고른_카테고리_없으면_운동_그것도_없으면_순서가_앞선_카테고리() throws Exception {
		String a = signUp("a@habit.kr");
		onboard(a, """
			{"categories": ["ex", "st"], "partnerCategory": "st",
			 "habits": [{"categoryCode": "st", "measureTypeId": 4, "name": "전공 공부", "dailyTarget": 60, "periodCode": "D7"}]}""")
			.andExpect(status().isCreated());
		assertThat(partnerOf("a@habit.kr")).isEqualTo("mouse");

		String b = signUp("b@habit.kr");
		onboard(b, """
			{"categories": ["sl", "md"],
			 "habits": [{"categoryCode": "sl", "measureTypeId": 16, "name": "7시간 자기", "dailyTarget": 7, "periodCode": "D100"}]}""")
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.starters[0].categoryCode").value("md")); // 카테고리 순서대로 지급
		assertThat(partnerOf("b@habit.kr")).isEqualTo("koala");
	}

	String partnerOf(String email) {
		return jdbc.queryForObject("""
			select s.code from monster.user_monster m join monster.monster_species s on s.id = m.species_id
			 where m.user_id = ? and m.is_partner""", String.class, userIdOf(email));
	}

	@Test
	void 틀린_곳이_여럿이면_400에_모두_담고_아무것도_저장하지_않는다() throws Exception {
		String access = signUp("a@habit.kr");
		onboard(access, """
			{"categories": ["ex", "st", "fd", "md"], "partnerCategory": "mn",
			 "habits": [
			   {"categoryCode": "ex", "measureTypeId": 4, "name": "공부를 운동에", "dailyTarget": 30, "periodCode": "D30"},
			   {"categoryCode": "fd", "measureTypeId": 7, "name": "물 6L", "dailyTarget": 6, "periodCode": "D30"},
			   {"categoryCode": "ex", "measureTypeId": 1, "name": "%s", "dailyTarget": 0, "periodCode": "D14"}],
			 "goals": [{"goalType": "WEEKLY", "title": "1"}, {"goalType": "WEEKLY", "title": "2"},
			           {"goalType": "WEEKLY", "title": "3"}, {"goalType": "WEEKLY", "title": "4"},
			           {"goalType": "DAILY", "title": ""}]}""".formatted("가".repeat(31)))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
			.andExpect(jsonPath("$.errors[*].field", hasItems("categories", "partnerCategory",
					"habits[0].measureTypeId", "habits[1].dailyTarget", "habits[2].name", "habits[2].dailyTarget",
					"habits[2].periodCode", "goals", "goals[4].goalType", "goals[4].title")));

		long user = userIdOf("a@habit.kr");
		assertThat(jdbc.queryForObject("select onboarded_at is null from identity.users where id = ?", Boolean.class, user))
			.isTrue();
		assertThat(count("select count(*) from habit.habit_user where user_id = ?", user)).isZero();
		assertThat(count("select count(*) from monster.monster_user where user_id = ?", user)).isZero();
	}

	@Test
	void 습관_0개나_6개_고르지_않은_카테고리의_습관은_400() throws Exception {
		String access = signUp("a@habit.kr");
		String habit = "{\"categoryCode\": \"ex\", \"measureTypeId\": 1, \"name\": \"러닝\", \"dailyTarget\": 30, \"periodCode\": \"D7\"}";
		onboard(access, "{\"categories\": [\"ex\"], \"habits\": []}")
			.andExpect(status().isBadRequest()).andExpect(jsonPath("$.errors[0].field").value("habits"));
		onboard(access, "{\"categories\": [\"ex\"], \"habits\": [" + String.join(",", java.util.Collections.nCopies(6, habit)) + "]}")
			.andExpect(status().isBadRequest()).andExpect(jsonPath("$.errors[0].field").value("habits"));
		onboard(access, """
			{"categories": ["st"], "habits": [%s]}""".formatted(habit))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.errors[*].field", containsInAnyOrder("habits[0].categoryCode")));
		onboard(access, "{\"categories\": [], \"habits\": [" + habit + "]}")
			.andExpect(status().isBadRequest());
	}

	@Test
	void 두_번이면_409_같은_키로_다시_보내면_처음_응답() throws Exception {
		String access = signUp("a@habit.kr");
		UUID key = UUID.randomUUID();
		String first = mvc.perform(onboardWithKey(access, key)).andExpect(status().isCreated())
			.andReturn().getResponse().getContentAsString();

		mvc.perform(onboardWithKey(access, key))
			.andExpect(status().isCreated())
			.andExpect(header().string(IdempotencyFilter.REPLAYED_HEADER, "true"))
			.andExpect(jsonPath("$.partnerMonsterId").value((Integer) JsonPath.read(first, "$.partnerMonsterId")));
		onboard(access, DEFAULT_ONBOARDING)
			.andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("ALREADY_ONBOARDED"));
		assertThat(count("select count(*) from monster.user_monster where user_id = ?", userIdOf("a@habit.kr"))).isEqualTo(2);
	}

	MockHttpServletRequestBuilder onboardWithKey(String access, UUID key) {
		return post("/onboarding").header("Authorization", "Bearer " + access)
			.header(IdempotencyFilter.HEADER, key.toString())
			.contentType(MediaType.APPLICATION_JSON).content(DEFAULT_ONBOARDING);
	}

	@Test
	void 출석은_하루_1행_어제_왔으면_이어서_며칠_빠지면_1부터() throws Exception {
		String access = onboardedUser("a@habit.kr");
		long user = userIdOf("a@habit.kr");

		as(access, post("/me/attendance")).andExpect(status().isOk())
			.andExpect(jsonPath("$.date").value(dates.today().toString()))
			.andExpect(jsonPath("$.alreadyAttended").value(false))
			.andExpect(jsonPath("$.currentStreak").value(1))
			.andExpect(jsonPath("$.longestStreak").value(1));
		as(access, post("/me/attendance")).andExpect(jsonPath("$.alreadyAttended").value(true))
			.andExpect(jsonPath("$.currentStreak").value(1));
		assertThat(count("select count(*) from habit.attendance where user_id = ?", user)).isEqualTo(1);

		// 어제까지 4일 연속이었다면 → 5일
		jdbc.update("delete from habit.attendance where user_id = ?", user);
		jdbc.update("update habit.habit_user set current_streak = 4, longest_streak = 9, last_attended_date = ? where user_id = ?",
				dates.today().minusDays(1), user);
		as(access, post("/me/attendance")).andExpect(jsonPath("$.currentStreak").value(5))
			.andExpect(jsonPath("$.longestStreak").value(9));

		// 사흘 전이 마지막이면 끊김 → 1
		jdbc.update("delete from habit.attendance where user_id = ?", user);
		jdbc.update("update habit.habit_user set current_streak = 4, last_attended_date = ? where user_id = ?",
				dates.today().minusDays(3), user);
		as(access, post("/me/attendance")).andExpect(jsonPath("$.currentStreak").value(1))
			.andExpect(jsonPath("$.longestStreak").value(9));
	}

	@Test
	void 탈퇴하면_습관_이름과_목표_제목을_비운다() throws Exception {
		String access = onboardedUser("a@habit.kr");
		long user = userIdOf("a@habit.kr");
		as(access, delete("/me")).andExpect(status().isNoContent());

		assertThat(count("select count(*) from habit.habit where user_id = ? and name is null", user)).isEqualTo(1);
		assertThat(count("select count(*) from goal.goal where user_id = ? and title is null", user)).isEqualTo(1);
	}
}
