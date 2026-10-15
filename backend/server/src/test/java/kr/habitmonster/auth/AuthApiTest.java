package kr.habitmonster.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;

import kr.habitmonster.auth.social.KakaoVerifier;
import kr.habitmonster.auth.social.SocialIdentity;
import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.identity.AuthProvider;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/** 회원 · 설정 API — API 명세 v5 "1. 회원 · 설정" + 결정 A5 · C4 · D4. */
// 소셜 키는 비워서 "설정 전" 상태로 검사 (실제 카카오 · 구글에 접속하지 않게)
@SpringBootTest(properties = { "app.auth.google.client-ids=", "app.auth.kakao.app-id=" })
@AutoConfigureMockMvc
@ActiveProfiles("local")
class AuthApiTest {

	@Autowired
	MockMvc mvc;

	@Autowired
	JdbcTemplate jdbc;

	@MockitoBean
	KakaoVerifier kakao;

	@BeforeEach
	void clean() {
		jdbc.update("delete from api.idempotency_record");
		jdbc.update("delete from identity.device_token");
		jdbc.update("delete from identity.refresh_token");
		jdbc.update("delete from identity.auth_credential");
		jdbc.update("delete from identity.users");
		given(kakao.provider()).willReturn(AuthProvider.KAKAO);
	}

	ResultActions postJson(String url, String json) throws Exception {
		return mvc.perform(post(url).contentType(MediaType.APPLICATION_JSON).content(json));
	}

	ResultActions as(String access, MockHttpServletRequestBuilder req) throws Exception {
		return mvc.perform(req.header("Authorization", "Bearer " + access));
	}

	String body(ResultActions r) throws Exception {
		return r.andReturn().getResponse().getContentAsString();
	}

	String signUp(String email) throws Exception {
		return JsonPath.read(body(postJson("/auth/signup", "{\"email\":\"" + email + "\",\"password\":\"password1\"}")
			.andExpect(status().isCreated())), "$.accessToken");
	}

	@Test
	void 이메일_가입_로그인_내정보_온보딩() throws Exception {
		String signUp = body(postJson("/auth/signup", "{\"email\":\" Me@Habit.kr \",\"password\":\"password1\"}")
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.onboarded").value(false))
			.andExpect(jsonPath("$.refreshToken").isString())
			.andExpect(jsonPath("$.isNewUser").doesNotExist())
			.andExpect(jsonPath("$.user").doesNotExist()));
		String access = JsonPath.read(signUp, "$.accessToken");

		as(access, get("/me"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.userId").isNumber())
			.andExpect(jsonPath("$.email").value("me@habit.kr"))
			.andExpect(jsonPath("$.provider").value("EMAIL"))
			.andExpect(jsonPath("$.onboarded").value(false));

		postJson("/auth/signup", "{\"email\":\"me@habit.kr\",\"password\":\"password2\"}")
			.andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("EMAIL_TAKEN"))
			.andExpect(jsonPath("$.message").value("이미 가입된 이메일이에요"));

		as(access, patch("/me/onboarding")).andExpect(status().isOk()).andExpect(jsonPath("$.onboarded").value(true));
		as(access, patch("/me/onboarding")).andExpect(status().isOk()).andExpect(jsonPath("$.onboarded").value(true));

		postJson("/auth/login", "{\"email\":\"me@habit.kr\",\"password\":\"wrong-pass\"}")
			.andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_CREDENTIALS"));
		postJson("/auth/login", "{\"email\":\"nobody@habit.kr\",\"password\":\"password1\"}")
			.andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_CREDENTIALS"));

		String login = body(postJson("/auth/login", "{\"email\":\"ME@habit.kr\",\"password\":\"password1\"}")
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.onboarded").value(true)));
		as(JsonPath.read(login, "$.accessToken"), get("/me"))
			.andExpect(status().isOk()).andExpect(jsonPath("$.email").value("me@habit.kr"));
	}

	@Test
	void 입력_검사() throws Exception {
		postJson("/auth/signup", "{\"email\":\"not-email\",\"password\":\"password1\"}")
			.andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("INVALID_EMAIL"));
		postJson("/auth/signup", "{\"email\":\"a@b.co\",\"password\":\"short\"}")
			.andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("WEAK_PASSWORD"));
		postJson("/auth/signup", "{\"email\":\"a@b.co\",\"password\":\"" + "x".repeat(73) + "\"}")
			.andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("WEAK_PASSWORD"));
		postJson("/auth/signup", "not json").andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.code").value("INVALID_REQUEST"));
	}

	@Test
	void 토큰_없거나_가짜면_401() throws Exception {
		mvc.perform(get("/me")).andExpect(status().isUnauthorized())
			.andExpect(jsonPath("$.code").value("INVALID_TOKEN"));
		mvc.perform(get("/me").header("Authorization", "Bearer abc.def.ghi")).andExpect(status().isUnauthorized())
			.andExpect(jsonPath("$.code").value("INVALID_TOKEN"));
	}

	@Test
	void refresh_교체_재사용하면_전부_폐기() throws Exception {
		String r0 = JsonPath.read(body(postJson("/auth/signup", "{\"email\":\"r@habit.kr\",\"password\":\"password1\"}")),
				"$.refreshToken");

		String res1 = body(postJson("/auth/refresh", "{\"refreshToken\":\"" + r0 + "\"}")
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.accessToken").isString())
			.andExpect(jsonPath("$.onboarded").doesNotExist()));
		String r1 = JsonPath.read(res1, "$.refreshToken");
		assertThat(r1).isNotEqualTo(r0);

		// 옛 토큰 재사용 → 거절 + 새 토큰(r1)까지 폐기
		postJson("/auth/refresh", "{\"refreshToken\":\"" + r0 + "\"}")
			.andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_TOKEN"));
		postJson("/auth/refresh", "{\"refreshToken\":\"" + r1 + "\"}")
			.andExpect(status().isUnauthorized());

		// DB엔 해시만
		assertThat(jdbc.queryForList("select token_hash from identity.refresh_token", String.class))
			.allSatisfy(h -> assertThat(h).hasSize(64).isNotEqualTo(r0).isNotEqualTo(r1));
	}

	@Test
	void 만료된_refresh는_거절_로그아웃한_refresh도_거절() throws Exception {
		String res = body(postJson("/auth/signup", "{\"email\":\"e@habit.kr\",\"password\":\"password1\"}"));
		String r = JsonPath.read(res, "$.refreshToken");
		jdbc.update("update identity.refresh_token set expires_at = created_at");
		postJson("/auth/refresh", "{\"refreshToken\":\"" + r + "\"}").andExpect(status().isUnauthorized());

		String r2 = JsonPath.read(body(postJson("/auth/login", "{\"email\":\"e@habit.kr\",\"password\":\"password1\"}")),
				"$.refreshToken");
		postJson("/auth/logout", "{\"refreshToken\":\"" + r2 + "\"}").andExpect(status().isNoContent());
		postJson("/auth/logout", "{\"refreshToken\":\"" + r2 + "\"}").andExpect(status().isNoContent());
		postJson("/auth/refresh", "{\"refreshToken\":\"" + r2 + "\"}").andExpect(status().isUnauthorized());
	}

	@Test
	void 카카오_처음이면_가입_다음엔_같은_계정() throws Exception {
		given(kakao.verify("kakao-token")).willReturn(new SocialIdentity("12345", "k@habit.kr", true));
		given(kakao.verify(eq("bad"))).willThrow(new ApiException(ErrorCode.INVALID_PROVIDER_TOKEN));

		String first = body(postJson("/auth/social/kakao", "{\"providerToken\":\"kakao-token\"}")
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.isNewUser").value(true))
			.andExpect(jsonPath("$.onboarded").value(false)));
		String second = body(postJson("/auth/social/kakao", "{\"providerToken\":\"kakao-token\"}")
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.isNewUser").value(false)));

		Integer id1 = JsonPath.read(body(as(JsonPath.read(first, "$.accessToken"), get("/me"))
			.andExpect(jsonPath("$.provider").value("KAKAO"))
			.andExpect(jsonPath("$.email").value("k@habit.kr"))), "$.userId");
		Integer id2 = JsonPath.read(body(as(JsonPath.read(second, "$.accessToken"), get("/me"))), "$.userId");
		assertThat(id2).isEqualTo(id1);

		postJson("/auth/social/kakao", "{\"providerToken\":\"bad\"}")
			.andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_PROVIDER_TOKEN"));
		postJson("/auth/social/kakao", "{\"providerToken\":\"\"}")
			.andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_PROVIDER_TOKEN"));
		postJson("/auth/social/naver", "{\"providerToken\":\"x\"}")
			.andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("UNSUPPORTED_PROVIDER"));
		postJson("/auth/social/email", "{\"providerToken\":\"x\"}")
			.andExpect(status().isNotFound());
	}

	@Test
	void 이메일_하나에_계정_하나_다른_방법이면_원래_가입_방법_안내() throws Exception {
		// 이메일로 가입된 주소로 카카오 첫 로그인 → 409 + provider=email
		signUp("me@habit.kr");
		given(kakao.verify("k1")).willReturn(new SocialIdentity("111", "ME@habit.kr", true));
		postJson("/auth/social/kakao", "{\"providerToken\":\"k1\"}")
			.andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("EMAIL_REGISTERED_WITH_OTHER_METHOD"))
			.andExpect(jsonPath("$.provider").value("email"));

		// 카카오로 가입된 주소로 이메일 가입 → 409 + provider=kakao
		given(kakao.verify("k2")).willReturn(new SocialIdentity("222", "kakao@habit.kr", true));
		postJson("/auth/social/kakao", "{\"providerToken\":\"k2\"}").andExpect(status().isOk());
		postJson("/auth/signup", "{\"email\":\"kakao@habit.kr\",\"password\":\"password1\"}")
			.andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("EMAIL_REGISTERED_WITH_OTHER_METHOD"))
			.andExpect(jsonPath("$.provider").value("kakao"))
			.andExpect(jsonPath("$.message").value("카카오로 가입된 이메일이에요. 카카오로 로그인해 주세요"));
	}

	@Test
	void 검증되지_않은_소셜_이메일은_계정_이메일로_쓰지_않음() throws Exception {
		signUp("taken@habit.kr");
		// 같은 주소지만 카카오가 검증하지 않은 이메일 → 막지도 않고 저장하지도 않음 (결정 C4)
		given(kakao.verify("k3")).willReturn(new SocialIdentity("333", "taken@habit.kr", false));
		String res = body(postJson("/auth/social/kakao", "{\"providerToken\":\"k3\"}").andExpect(status().isOk()));
		as(JsonPath.read(res, "$.accessToken"), get("/me")).andExpect(jsonPath("$.email").doesNotExist());
	}

	@Test
	void 탈퇴하면_로그인_정보가_지워지고_같은_이메일로_다시_가입_가능() throws Exception {
		String access = signUp("w@habit.kr");
		as(access, put("/me/device-token").contentType(MediaType.APPLICATION_JSON)
			.content("{\"fcmToken\":\"fcm-w\",\"platform\":\"ANDROID\"}")).andExpect(status().isNoContent());

		as(access, delete("/me")).andExpect(status().isNoContent());

		as(access, get("/me")).andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_TOKEN"));
		postJson("/auth/login", "{\"email\":\"w@habit.kr\",\"password\":\"password1\"}")
			.andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_CREDENTIALS"));
		assertThat(jdbc.queryForObject("select count(*) from identity.users where status = 'WITHDRAWN' and email is null",
				Integer.class)).isEqualTo(1);
		assertThat(jdbc.queryForObject("select count(*) from identity.device_token", Integer.class)).isZero();
		assertThat(jdbc.queryForObject("select count(*) from identity.refresh_token", Integer.class)).isZero();

		signUp("w@habit.kr"); // 이메일이 비워져서 다시 가입 가능
	}

	@Test
	void 푸시_토큰_등록_다른_계정으로_옮기기_해제() throws Exception {
		String a = signUp("a@habit.kr");
		String b = signUp("b@habit.kr");
		String req = "{\"fcmToken\":\"fcm-1\",\"platform\":\"android\"}";

		as(a, put("/me/device-token").contentType(MediaType.APPLICATION_JSON).content(req)).andExpect(status().isNoContent());
		as(a, put("/me/device-token").contentType(MediaType.APPLICATION_JSON).content(req)).andExpect(status().isNoContent());
		as(b, put("/me/device-token").contentType(MediaType.APPLICATION_JSON).content(req)).andExpect(status().isNoContent());
		assertThat(jdbc.queryForList("select u.email from identity.device_token d join identity.users u on u.id = d.user_id",
				String.class)).containsExactly("b@habit.kr");

		// 남의 토큰 해제는 아무 일도 안 함, 내 토큰 해제는 지움
		as(a, delete("/me/device-token").contentType(MediaType.APPLICATION_JSON).content(req)).andExpect(status().isNoContent());
		assertThat(jdbc.queryForObject("select count(*) from identity.device_token", Integer.class)).isEqualTo(1);
		as(b, delete("/me/device-token").contentType(MediaType.APPLICATION_JSON).content(req)).andExpect(status().isNoContent());
		assertThat(jdbc.queryForObject("select count(*) from identity.device_token", Integer.class)).isZero();

		as(a, put("/me/device-token").contentType(MediaType.APPLICATION_JSON)
			.content("{\"fcmToken\":\"fcm-2\",\"platform\":\"WINDOWS\"}"))
			.andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("INVALID_REQUEST"));
	}

	@Test
	void 구글은_키_설정_전엔_준비중_애플은_지원_안함() throws Exception {
		postJson("/auth/social/google", "{\"providerToken\":\"x\"}")
			.andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value("SOCIAL_NOT_CONFIGURED"));
		postJson("/auth/social/apple", "{\"providerToken\":\"x\"}")
			.andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("UNSUPPORTED_PROVIDER"));
		given(kakao.verify(anyString())).willThrow(new ApiException(ErrorCode.SOCIAL_NOT_CONFIGURED));
		postJson("/auth/social/kakao", "{\"providerToken\":\"x\"}").andExpect(status().isServiceUnavailable());
	}

	@Test
	void 탈퇴_상태인데_로그인_수단이_남아_있으면_거부() throws Exception {
		signUp("z@habit.kr");
		jdbc.update("update identity.users set status = 'WITHDRAWN', withdrawn_at = now()");
		postJson("/auth/login", "{\"email\":\"z@habit.kr\",\"password\":\"password1\"}")
			.andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("ACCOUNT_WITHDRAWN"));
	}
}
