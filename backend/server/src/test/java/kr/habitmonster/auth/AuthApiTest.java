package kr.habitmonster.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
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
		jdbc.update("delete from identity.refresh_token");
		jdbc.update("delete from identity.auth_credential");
		jdbc.update("delete from identity.users");
		given(kakao.provider()).willReturn(AuthProvider.KAKAO);
	}

	ResultActions postJson(String url, String json) throws Exception {
		return mvc.perform(post(url).contentType(MediaType.APPLICATION_JSON).content(json));
	}

	String body(ResultActions r) throws Exception {
		return r.andReturn().getResponse().getContentAsString();
	}

	@Test
	void 이메일_가입_로그인_내정보_온보딩() throws Exception {
		String signUp = body(postJson("/auth/signup", "{\"email\":\" Me@Habit.kr \",\"password\":\"password1\"}")
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.user.email").value("me@habit.kr"))
			.andExpect(jsonPath("$.user.provider").value("EMAIL"))
			.andExpect(jsonPath("$.user.onboardingDone").value(false)));
		String access = JsonPath.read(signUp, "$.accessToken");

		postJson("/auth/signup", "{\"email\":\"me@habit.kr\",\"password\":\"password2\"}")
			.andExpect(status().isConflict())
			.andExpect(jsonPath("$.code").value("EMAIL_TAKEN"))
			.andExpect(jsonPath("$.message").value("이미 가입된 이메일이에요"));

		mvc.perform(patch("/me/onboarding").header("Authorization", "Bearer " + access))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.onboardingDone").value(true));
		// 다시 불러도 그대로 완료 (예전 앱이 보내던 본문이 있어도 됨)
		mvc.perform(patch("/me/onboarding").header("Authorization", "Bearer " + access)
			.contentType(MediaType.APPLICATION_JSON).content("{\"step\":\"DONE\"}"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.onboardingDone").value(true));

		postJson("/auth/login", "{\"email\":\"me@habit.kr\",\"password\":\"wrong-pass\"}")
			.andExpect(status().isUnauthorized())
			.andExpect(jsonPath("$.code").value("INVALID_CREDENTIALS"));
		postJson("/auth/login", "{\"email\":\"nobody@habit.kr\",\"password\":\"password1\"}")
			.andExpect(status().isUnauthorized())
			.andExpect(jsonPath("$.code").value("INVALID_CREDENTIALS"));

		String login = body(postJson("/auth/login", "{\"email\":\"ME@habit.kr\",\"password\":\"password1\"}")
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.user.onboardingDone").value(true)));
		mvc.perform(get("/me").header("Authorization", "Bearer " + JsonPath.read(login, "$.accessToken")))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.email").value("me@habit.kr"));
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
			.andExpect(jsonPath("$.code").value("BAD_REQUEST"));
	}

	@Test
	void 토큰_없거나_가짜면_401() throws Exception {
		mvc.perform(get("/me")).andExpect(status().isUnauthorized())
			.andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
		mvc.perform(get("/me").header("Authorization", "Bearer abc.def.ghi")).andExpect(status().isUnauthorized())
			.andExpect(jsonPath("$.code").value("INVALID_TOKEN"));
	}

	@Test
	void refresh_교체_재사용하면_전부_폐기() throws Exception {
		String r0 = JsonPath.read(body(postJson("/auth/signup", "{\"email\":\"r@habit.kr\",\"password\":\"password1\"}")),
				"$.refreshToken");

		String res1 = body(postJson("/auth/refresh", "{\"refreshToken\":\"" + r0 + "\"}")
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.user.provider").value("EMAIL")));
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
	void 카카오_처음이면_가입_다음엔_같은_계정_같은_이메일이어도_합치지_않음() throws Exception {
		given(kakao.verify("kakao-token")).willReturn(new SocialIdentity("12345", "me@habit.kr"));
		given(kakao.verify(eq("bad"))).willThrow(new ApiException(ErrorCode.INVALID_TOKEN));

		postJson("/auth/signup", "{\"email\":\"me@habit.kr\",\"password\":\"password1\"}").andExpect(status().isCreated());

		String first = body(postJson("/auth/social/kakao", "{\"token\":\"kakao-token\"}")
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.user.provider").value("KAKAO"))
			.andExpect(jsonPath("$.user.onboardingDone").value(false)));
		String second = body(postJson("/auth/social/kakao", "{\"token\":\"kakao-token\"}").andExpect(status().isOk()));
		String emailUser = JsonPath.read(body(postJson("/auth/login",
				"{\"email\":\"me@habit.kr\",\"password\":\"password1\"}")), "$.user.id");

		String kakaoUser = JsonPath.read(first, "$.user.id");
		assertThat((String) JsonPath.read(second, "$.user.id")).isEqualTo(kakaoUser);
		assertThat(kakaoUser).isNotEqualTo(emailUser); // Q-20

		postJson("/auth/social/kakao", "{\"token\":\"bad\"}")
			.andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_TOKEN"));
		postJson("/auth/social/naver", "{\"token\":\"x\"}")
			.andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("UNSUPPORTED_PROVIDER"));
		postJson("/auth/social/email", "{\"token\":\"x\"}")
			.andExpect(status().isNotFound());
	}

	@Test
	void 구글은_키_설정_전엔_준비중_애플은_지원_안함() throws Exception {
		postJson("/auth/social/google", "{\"token\":\"x\"}")
			.andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value("SOCIAL_NOT_CONFIGURED"));
		postJson("/auth/social/apple", "{\"token\":\"x\"}")
			.andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("UNSUPPORTED_PROVIDER"));
		given(kakao.verify(anyString())).willThrow(new ApiException(ErrorCode.SOCIAL_NOT_CONFIGURED));
		postJson("/auth/social/kakao", "{\"token\":\"x\"}").andExpect(status().isServiceUnavailable());
	}

	@Test
	void 탈퇴한_계정은_로그인_거부() throws Exception {
		postJson("/auth/signup", "{\"email\":\"w@habit.kr\",\"password\":\"password1\"}");
		jdbc.update("update identity.users set status = 'WITHDRAWN', withdrawn_at = now()");
		postJson("/auth/login", "{\"email\":\"w@habit.kr\",\"password\":\"password1\"}")
			.andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("ACCOUNT_WITHDRAWN"));
	}
}
