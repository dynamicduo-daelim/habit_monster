package kr.habitmonster.home;

import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.support.PostgresTest;
import kr.habitmonster.wallet.LedgerReason;
import kr.habitmonster.wallet.WalletService;

import org.junit.jupiter.api.Test;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/** 메인 화면 조회 (API 명세 v5 "3. 상단 바 · 메인 화면" + 습관 · 목표 목록, 3-2단계). 기본 온보딩 직후 사용자 기준. */
class MainQueryApiTest extends PostgresTest {

	@Autowired
	BusinessDates dates;

	@Autowired
	WalletService wallet;

	ResultActions as(String access, MockHttpServletRequestBuilder req) throws Exception {
		return mvc.perform(req.header("Authorization", "Bearer " + access));
	}

	long monsterId(long user, String code) {
		return jdbc.queryForObject("""
			select m.id from monster.user_monster m join monster.monster_species s on s.id = m.species_id
			 where m.user_id = ? and s.code = ?""", Long.class, user, code);
	}

	@Test
	void 온보딩_전에는_모두_403() throws Exception {
		String access = signUp("a@habit.kr");
		for (String path : new String[] { "/me/status", "/me/today", "/monsters", "/shop/items", "/inventory", "/habits",
				"/goals" }) {
			as(access, get(path)).andExpect(status().isForbidden())
				.andExpect(jsonPath("$.code").value("ONBOARDING_REQUIRED"));
		}
	}

	@Test
	void 상단_바_체크인_전() throws Exception {
		String access = onboardedUser("a@habit.kr");
		as(access, get("/me/status")).andExpect(status().isOk())
			.andExpect(jsonPath("$.businessDate").value(dates.today().toString()))
			.andExpect(jsonPath("$.dayCount").value(1))
			.andExpect(jsonPath("$.currentStreak").value(0))
			.andExpect(jsonPath("$.gold").value(0))
			.andExpect(jsonPath("$.ballCount").value(0))
			.andExpect(jsonPath("$.checkedInToday").value(false))
			.andExpect(jsonPath("$.exploreRemaining").value(0))
			.andExpect(jsonPath("$.exploreTotal").value(0))
			.andExpect(jsonPath("$.endedHabitCount").value(0));

		as(access, post("/me/attendance")).andExpect(status().isOk());
		jdbc.update("update identity.users set onboarded_at = onboarded_at - interval '2 days'");
		as(access, get("/me/status")).andExpect(jsonPath("$.currentStreak").value(1))
			.andExpect(jsonPath("$.dayCount").value(3));
	}

	@Test
	void 오늘_요약_체크인_전에는_보상_필드가_null() throws Exception {
		String access = onboardedUser("a@habit.kr");
		as(access, get("/me/today")).andExpect(status().isOk())
			.andExpect(jsonPath("$.checkedIn").value(false))
			.andExpect(content().string(containsString("\"goldEarned\":null")))
			.andExpect(content().string(containsString("\"overallRate\":null")))
			.andExpect(jsonPath("$.habits.length()").value(1))
			.andExpect(jsonPath("$.habits[0].name").value("아침 러닝"))
			.andExpect(jsonPath("$.habits[0].categoryCode").value("ex"))
			.andExpect(jsonPath("$.habits[0].unit").value("분"))
			.andExpect(jsonPath("$.habits[0].dailyTarget").value(30))
			.andExpect(content().string(containsString("\"rewardedScore\":null")))
			.andExpect(content().string(containsString("\"counted\":null")))
			.andExpect(jsonPath("$.habits[0].filledDays").value(0))
			.andExpect(jsonPath("$.habits[0].periodDays").value(30));
	}

	@Test
	void 체크인_후의_상단_바와_오늘_요약은_첫_제출_기준() throws Exception {
		String access = onboardedUser("a@habit.kr");
		long user = userIdOf("a@habit.kr");
		long habit = jdbc.queryForObject("select id from habit.habit where user_id = ?", Long.class, user);
		// 3-3(체크인 제출)이 만들 행을 직접 넣는다: 30분 목표에 20분 → 13점, 반영, 채운 날 1
		long checkin = jdbc.queryForObject("""
			insert into habit.daily_checkin (user_id, checkin_date, habit_count, total_score, counted_score)
			values (?, ?, 1, 13, 13) returning id""", Long.class, user, dates.today());
		jdbc.update("""
			insert into habit.habit_checkin (daily_checkin_id, habit_id, period_seq, value, target_snapshot, score,
			                                 rewarded_value, rewarded_score, is_counted, is_filled)
			values (?, ?, 1, 20, 30, 13, 20, 13, true, true)""", checkin, habit);
		jdbc.update("update habit.habit_period set filled_days = 1, counted_score_sum = 13 where habit_id = ?", habit);
		jdbc.update("""
			insert into monster.daily_explore_quota (user_id, quota_date, base_count, used_count, source_checkin_id)
			values (?, ?, 3, 1, ?)""", user, dates.today(), checkin);
		wallet.credit(user, 13, LedgerReason.CHECKIN, String.valueOf(checkin));
		wallet.credit(user, 20, LedgerReason.LEVELUP, checkin + ":ex");
		wallet.credit(user, 15, LedgerReason.DUPLICATE, "999"); // 체크인과 상관없는 골드는 오늘 요약에 안 들어감

		as(access, get("/me/status"))
			.andExpect(jsonPath("$.checkedInToday").value(true))
			.andExpect(jsonPath("$.gold").value(48))
			.andExpect(jsonPath("$.exploreRemaining").value(2))
			.andExpect(jsonPath("$.exploreTotal").value(3));
		as(access, get("/me/today"))
			.andExpect(jsonPath("$.checkedIn").value(true))
			.andExpect(jsonPath("$.goldEarned").value(33))
			.andExpect(jsonPath("$.overallRate").value(65)) // 13점 → 65%
			.andExpect(jsonPath("$.habits[0].rewardedValue").value(20))
			.andExpect(jsonPath("$.habits[0].rewardedScore").value(13))
			.andExpect(jsonPath("$.habits[0].counted").value(true))
			.andExpect(jsonPath("$.habits[0].filledDays").value(1));
	}

	@Test
	void 몬스터_목록과_상세() throws Exception {
		String access = onboardedUser("a@habit.kr");
		long user = userIdOf("a@habit.kr");
		long monkey = monsterId(user, "monkey");

		as(access, get("/monsters")).andExpect(status().isOk())
			.andExpect(jsonPath("$.length()").value(2))
			.andExpect(jsonPath("$[0].userMonsterId").value(monkey))
			.andExpect(jsonPath("$[0].speciesId").value(1))
			.andExpect(jsonPath("$[0].name").value("불씨 원숭이"))
			.andExpect(jsonPath("$[0].imageKey").value("monkey"))
			.andExpect(jsonPath("$[0].imageUrl").doesNotExist())
			.andExpect(jsonPath("$[0].level").value(1))
			.andExpect(jsonPath("$[0].stage").value(0))
			.andExpect(jsonPath("$[0].displayHeight").value(72))
			.andExpect(jsonPath("$[0].facing").value("FRONT"))
			.andExpect(jsonPath("$[0].location").value("FIELD"))
			.andExpect(jsonPath("$[0].isPartner").value(true))
			.andExpect(jsonPath("$[1].isPartner").value(false));
		as(access, get("/monsters").param("location", "BAG")).andExpect(jsonPath("$.length()").value(0));
		as(access, get("/monsters").param("location", "SKY")).andExpect(status().isBadRequest());

		as(access, get("/monsters/" + monkey)).andExpect(status().isOk())
			.andExpect(jsonPath("$.rarity").value(1))
			.andExpect(jsonPath("$.level").value(1))
			.andExpect(jsonPath("$.expInLevel").value(0))
			.andExpect(jsonPath("$.expRequired").value(125))
			.andExpect(jsonPath("$.expToNextLevel").doesNotExist())
			.andExpect(jsonPath("$.nextEvolutionLevel").value(10))
			.andExpect(jsonPath("$.affection").value(3))
			.andExpect(jsonPath("$.affectionMax").value(10))
			.andExpect(jsonPath("$.affectionTier").value("LOW"))
			.andExpect(jsonPath("$.todayActions.pet").value(false))
			.andExpect(jsonPath("$.todayActions.play").value(false));

		// Lv.7 + 40 EXP, 호감도 6, 오늘 쓰다듬음
		jdbc.update("update monster.user_monster set level = 7, exp_total = ?, affection = 6 where id = ?", 6 * 125 + 40, monkey);
		jdbc.update("insert into monster.affection_action (user_monster_id, action_date, action_type, gain) values (?, ?, 'PET', 2)",
				monkey, dates.today());
		as(access, get("/monsters/" + monkey))
			.andExpect(jsonPath("$.expInLevel").value(40))
			.andExpect(jsonPath("$.affectionTier").value("MID"))
			.andExpect(jsonPath("$.todayActions.pet").value(true))
			.andExpect(jsonPath("$.todayActions.play").value(false));

		// 최대 레벨 · 최종 진화
		jdbc.update("update monster.user_monster set level = 20, exp_total = 19 * 125 where id = ?", monkey);
		as(access, get("/monsters/" + monkey))
			.andExpect(jsonPath("$.stage").value(2))
			.andExpect(content().string(containsString("\"expRequired\":null")))
			.andExpect(content().string(containsString("\"nextEvolutionLevel\":null")));
	}

	@Test
	void 남의_몬스터는_404() throws Exception {
		onboardedUser("a@habit.kr");
		String other = onboardedUser("b@habit.kr");
		long monkeyOfA = monsterId(userIdOf("a@habit.kr"), "monkey");

		as(other, get("/monsters/" + monkeyOfA))
			.andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("NOT_FOUND"));
		as(other, get("/monsters/987654321")).andExpect(status().isNotFound());
	}

	@Test
	void 상점과_가방() throws Exception {
		String access = onboardedUser("a@habit.kr");
		long user = userIdOf("a@habit.kr");

		as(access, get("/shop/items")).andExpect(status().isOk())
			.andExpect(jsonPath("$.gold").value(0))
			.andExpect(jsonPath("$.items.length()").value(4))
			.andExpect(jsonPath("$.items[0].code").value("POTION_S"))
			.andExpect(jsonPath("$.items[0].shortName").value("하급"))
			.andExpect(jsonPath("$.items[0].price").value(20))
			.andExpect(jsonPath("$.items[0].effectType").value("MONSTER_EXP"))
			.andExpect(jsonPath("$.items[0].effectValue").value(20))
			.andExpect(jsonPath("$.items[3].code").value("BALL"))
			.andExpect(jsonPath("$.items[3].effectType").value("CAPTURE"));

		as(access, get("/inventory")).andExpect(jsonPath("$.items.length()").value(0));
		jdbc.update("insert into shop.inventory (user_id, item_code, quantity) values (?, 'BALL', 2), (?, 'POTION_S', 0)",
				user, user);
		as(access, get("/inventory"))
			.andExpect(jsonPath("$.items.length()").value(1)) // 0개는 빠짐
			.andExpect(jsonPath("$.items[0].itemCode").value("BALL"))
			.andExpect(jsonPath("$.items[0].name").value("성실볼"))
			.andExpect(jsonPath("$.items[0].quantity").value(2));
		as(access, get("/me/status")).andExpect(jsonPath("$.ballCount").value(2));
	}

	@Test
	void 습관_목록과_목표_목록() throws Exception {
		String access = onboardedUser("a@habit.kr");

		as(access, get("/habits")).andExpect(status().isOk())
			.andExpect(jsonPath("$.length()").value(1))
			.andExpect(jsonPath("$[0].categoryCode").value("ex"))
			.andExpect(jsonPath("$[0].name").value("아침 러닝"))
			.andExpect(jsonPath("$[0].measureTypeId").value(1))
			.andExpect(jsonPath("$[0].unit").value("분"))
			.andExpect(jsonPath("$[0].dailyTarget").value(30))
			.andExpect(jsonPath("$[0].periodCode").value("D30"))
			.andExpect(jsonPath("$[0].startDate").value(dates.today().toString()))
			.andExpect(jsonPath("$[0].filledDays").value(0))
			.andExpect(jsonPath("$[0].periodDays").value(30))
			.andExpect(jsonPath("$[0].status").value("ACTIVE"));
		as(access, get("/habits").param("status", "STOPPED")).andExpect(jsonPath("$.length()").value(0));
		as(access, get("/habits").param("status", "DONE")).andExpect(status().isBadRequest());

		as(access, get("/goals")).andExpect(status().isOk())
			.andExpect(jsonPath("$.weekly.slotsTotal").value(3))
			.andExpect(jsonPath("$.weekly.slotsUsed").value(1))
			.andExpect(jsonPath("$.weekly.rewardGold").value(40))
			.andExpect(jsonPath("$.weekly.goals[0].title").value("헬스장 3번 가기"))
			.andExpect(jsonPath("$.weekly.goals[0].status").value("ACTIVE"))
			.andExpect(jsonPath("$.weekly.goals[0].periodStart").value(dates.today().toString()))
			.andExpect(jsonPath("$.weekly.goals[0].periodEnd").value(dates.today().plusDays(6).toString()))
			.andExpect(jsonPath("$.monthly.slotsTotal").value(1))
			.andExpect(jsonPath("$.monthly.slotsUsed").value(0))
			.andExpect(jsonPath("$.monthly.rewardGold").value(150));
	}
}
