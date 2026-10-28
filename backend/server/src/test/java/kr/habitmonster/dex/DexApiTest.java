package kr.habitmonster.dex;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.nullValue;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.monster.Dice;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.Test;
import org.skyscreamer.jsonassert.JSONAssert;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * 도감 · 카테고리 열기 (API 명세 v5 "7. 도감", 4-3단계). 기본 온보딩 = 운동 · 공부, 스타터 불씨 원숭이(1번) · 찌릿 쥐(6번).
 * 본 종은 실제 탐색으로 만든다 (체크인 → Lv.3 → 깡총 불토끼 2번 등장, 랜덤은 {@link Dice} 고정).
 */
class DexApiTest extends PostgresTest {

	static final String E = "a@habit.kr";

	@MockitoBean
	Dice dice;

	@Autowired
	BusinessDates dates;

	ResultActions as(String access, MockHttpServletRequestBuilder req) throws Exception {
		return mvc.perform(req.header("Authorization", "Bearer " + access));
	}

	ResultActions unlock(String access, String code, String key) throws Exception {
		return as(access, post("/categories/" + code + "/unlock").header(IdempotencyFilter.HEADER, key));
	}

	ResultActions unlock(String access, String code) throws Exception {
		return unlock(access, code, UUID.randomUUID().toString());
	}

	/** 기본 온보딩 + 체크인 + 운동 Lv.3 + 탐색에서 깡총 불토끼를 만남(안 잡음). */
	String sawRabbit(String email) throws Exception {
		String access = onboardedUser(email);
		long user = userIdOf(email);
		long habit = jdbc.queryForObject("select id from habit.habit where user_id = ?", Long.class, user);
		as(access, post("/checkins/today").header(IdempotencyFilter.HEADER, UUID.randomUUID().toString())
			.contentType(MediaType.APPLICATION_JSON)
			.content("{\"businessDate\": \"" + dates.today() + "\", \"answers\": [{\"habitId\": " + habit
					+ ", \"done\": true, \"value\": 30}]}"))
			.andExpect(status().isCreated());
		jdbc.update("update habit.user_category set exp_total = 30, level = 3 where user_id = ?", user);
		when(dice.roll()).thenReturn(0.5, 0.3); // 꽝 아님 → 불토끼
		as(access, post("/explores").header(IdempotencyFilter.HEADER, UUID.randomUUID().toString())
			.contentType(MediaType.APPLICATION_JSON).content("{\"businessDate\": \"" + dates.today() + "\"}"))
			.andExpect(jsonPath("$.result").value("ENCOUNTER"))
			.andExpect(jsonPath("$.species.speciesId").value(2));
		return access;
	}

	/** 탐색 없이 종을 가진 것으로 (가방에, 도감 수 +1). */
	void own(long user, int speciesId, String location) {
		jdbc.update("""
			insert into monster.user_monster (user_id, species_id, affection, location, acquired_via)
			values (?, ?, 0, ?, 'EXPLORE')""", user, speciesId, location);
		jdbc.update("insert into monster.dex_entry (user_id, species_id) values (?, ?)", user, speciesId);
		jdbc.update("update monster.monster_user set dex_count = dex_count + 1 where user_id = ?", user);
	}

	void ticket(long user, int milestone) {
		jdbc.update("insert into habit.category_unlock_ticket (user_id, milestone) values (?, ?)", user, milestone);
	}

	// ---------- 조회 ----------
	@Test
	void 요약은_가진_종_본_종_전체_수와_해금권() throws Exception {
		String access = sawRabbit(E);
		as(access, get("/dex")).andExpect(status().isOk())
			.andExpect(jsonPath("$.slot.dexCount").value(2))
			.andExpect(jsonPath("$.slot.nextMilestone").value(5))
			.andExpect(jsonPath("$.slot.availableTickets").value(0))
			.andExpect(jsonPath("$.categories.length()").value(6))
			.andExpect(jsonPath("$.categories[0].code").value("ex"))
			.andExpect(jsonPath("$.categories[0].name").value("운동"))
			.andExpect(jsonPath("$.categories[0].opened").value(true))
			.andExpect(jsonPath("$.categories[0].ownedCount").value(1))
			.andExpect(jsonPath("$.categories[0].seenCount").value(2)) // 가진 종 포함
			.andExpect(jsonPath("$.categories[0].totalCount").value(5))
			.andExpect(jsonPath("$.categories[2].code").value("fd"))
			.andExpect(jsonPath("$.categories[2].opened").value(false))
			.andExpect(jsonPath("$.categories[2].seenCount").value(0));
	}

	@Test
	void 카테고리_목록은_세_상태_모르는_종은_이름과_번호를_숨긴다() throws Exception {
		String access = sawRabbit(E);
		as(access, get("/dex/categories/ex")).andExpect(status().isOk())
			.andExpect(jsonPath("$.ownedCount").value(1))
			.andExpect(jsonPath("$.seenCount").value(2))
			.andExpect(jsonPath("$.totalCount").value(5))
			.andExpect(jsonPath("$.monsters[0].dexNo").value(1))
			.andExpect(jsonPath("$.monsters[0].status").value("OWNED"))
			.andExpect(jsonPath("$.monsters[0].speciesId").value(1))
			.andExpect(jsonPath("$.monsters[0].name").value("불씨 원숭이"))
			.andExpect(jsonPath("$.monsters[0].imageKey").value("monkey"))
			.andExpect(jsonPath("$.monsters[0].level").value(1))
			.andExpect(jsonPath("$.monsters[0].unlockLevel").doesNotExist())
			.andExpect(jsonPath("$.monsters[1].status").value("SEEN"))
			.andExpect(jsonPath("$.monsters[1].name").value("깡총 불토끼"))
			.andExpect(jsonPath("$.monsters[1].level").doesNotExist())
			.andExpect(jsonPath("$.monsters[2].status").value("UNKNOWN"))
			.andExpect(jsonPath("$.monsters[2].dexNo").value(3))
			.andExpect(jsonPath("$.monsters[2].name").doesNotExist())
			.andExpect(jsonPath("$.monsters[2].speciesId").doesNotExist())
			.andExpect(jsonPath("$.monsters[2].imageKey").value("chicken"))
			.andExpect(jsonPath("$.monsters[2].unlockLevel").value(6))
			.andExpect(jsonPath("$.monsters[2].unlocked").value(false));
		as(access, get("/dex/categories/fd")).andExpect(jsonPath("$.monsters[0].status").value("UNKNOWN"))
			.andExpect(jsonPath("$.monsters[0].unlocked").value(false)); // 안 연 카테고리
		as(access, get("/dex/categories/zz")).andExpect(status().isNotFound());
	}

	@Test
	void 상세는_가진_종과_본_종만_본_적_없으면_404() throws Exception {
		String access = sawRabbit(E);
		as(access, get("/dex/species/1")).andExpect(status().isOk())
			.andExpect(jsonPath("$.dexNo").value(1))
			.andExpect(jsonPath("$.status").value("OWNED"))
			.andExpect(jsonPath("$.imageKey").value("monkey"))
			.andExpect(jsonPath("$.element").value("불꽃"))
			.andExpect(jsonPath("$.rarity").value(1))
			.andExpect(jsonPath("$.level").value(1))
			.andExpect(jsonPath("$.stage").value(0))
			.andExpect(jsonPath("$.description").isNotEmpty());
		as(access, get("/dex/species/2")).andExpect(jsonPath("$.status").value("SEEN"))
			.andExpect(jsonPath("$.level").value(nullValue()))
			.andExpect(jsonPath("$.stage").value(nullValue()));
		as(access, get("/dex/species/3")).andExpect(status().isNotFound())
			.andExpect(jsonPath("$.code").value("NOT_DISCOVERED"));
		as(access, get("/dex/species/999")).andExpect(jsonPath("$.code").value("NOT_DISCOVERED"));
	}

	@Test
	void 남의_도감은_섞이지_않는다() throws Exception {
		sawRabbit(E);
		String other = onboardedUser("b@habit.kr");
		as(other, get("/dex/categories/ex")).andExpect(jsonPath("$.monsters[1].status").value("UNKNOWN"));
		as(other, get("/dex/species/2")).andExpect(status().isNotFound());
	}

	// ---------- 카테고리 열기 ----------
	@Test
	void 해금권으로_열면_Lv1_시작_몬스터_해금권_사용() throws Exception {
		String access = onboardedUser(E);
		long user = userIdOf(E);
		unlock(access, "md").andExpect(status().isUnprocessableContent()).andExpect(jsonPath("$.code").value("NO_TICKET"));

		ticket(user, 5);
		unlock(access, "md").andExpect(status().isCreated())
			.andExpect(jsonPath("$.categoryCode").value("md"))
			.andExpect(jsonPath("$.starter.name").value("물방울 코알라"))
			.andExpect(jsonPath("$.starter.imageKey").value("koala"))
			.andExpect(jsonPath("$.starter.location").value("FIELD"))
			.andExpect(jsonPath("$.availableTickets").value(0));
		assertThat(jdbc.queryForObject("""
			select opened_via || ' ' || level from habit.user_category where user_id = ? and category_code = 'md'""",
				String.class, user)).isEqualTo("TICKET 1");
		assertThat(jdbc.queryForObject("select used_category_code from habit.category_unlock_ticket where user_id = ?",
				String.class, user)).isEqualTo("md");
		as(access, get("/dex")).andExpect(jsonPath("$.slot.dexCount").value(3))
			.andExpect(jsonPath("$.categories[3].opened").value(true));

		unlock(access, "md").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("ALREADY_OPENED"));
		unlock(access, "zz").andExpect(status().isNotFound());
	}

	@Test
	void 필드가_꽉_찼으면_시작_몬스터는_가방으로() throws Exception {
		String access = onboardedUser(E);
		long user = userIdOf(E);
		for (int species : new int[] { 2, 3, 7 }) {
			own(user, species, "FIELD"); // 스타터 2 + 3 = 5마리
		}
		ticket(user, 5);
		unlock(access, "sl").andExpect(jsonPath("$.starter.location").value("BAG"));
	}

	@Test
	void 시작_몬스터로_기준값에_닿으면_해금권을_또_받는다() throws Exception {
		String access = onboardedUser(E);
		long user = userIdOf(E);
		own(user, 2, "BAG");
		own(user, 7, "BAG"); // 가진 종 4
		ticket(user, 100); // 테스트용 기준값 (5와 겹치지 않게)
		unlock(access, "fd").andExpect(status().isCreated()).andExpect(jsonPath("$.availableTickets").value(1));
		assertThat(jdbc.queryForObject("select count(*) from habit.category_unlock_ticket where user_id = ? and milestone = 5",
				Integer.class, user)).isEqualTo(1);
	}

	@Test
	void 같은_키로_다시_보내면_첫_응답이고_해금권은_한_장만() throws Exception {
		String access = onboardedUser(E);
		long user = userIdOf(E);
		ticket(user, 5);
		ticket(user, 10);
		String key = UUID.randomUUID().toString();
		String first = unlock(access, "md", key).andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
		String again = unlock(access, "md", key).andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
		JSONAssert.assertEquals(first, again, true);
		assertThat(jdbc.queryForObject("select count(*) from habit.category_unlock_ticket where user_id = ? and used_at is null",
				Integer.class, user)).isEqualTo(1);
		assertThat(jdbc.queryForObject("select count(*) from monster.starter_grant where user_id = ? and category_code = 'md'",
				Integer.class, user)).isEqualTo(1);
	}
}
