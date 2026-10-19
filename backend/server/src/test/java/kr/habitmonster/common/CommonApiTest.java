package kr.habitmonster.common;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import com.jayway.jsonpath.JsonPath;

import kr.habitmonster.idempotency.Idempotent;
import kr.habitmonster.idempotency.IdempotencyFilter;
import kr.habitmonster.support.PostgresTest;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** 0단계 공통 기반: 토큰 만료 구분 · 탈퇴/온보딩 차단 · 중복 방지 키 · /api/v1 경로. */
@Import(CommonApiTest.TestApi.class)
class CommonApiTest extends PostgresTest {

	/** 중복 방지 키를 검사하려고 테스트에서만 쓰는 API. 닉네임을 바꾸고, 몇 번 실행됐는지 센다. */
	@RestController
	static class TestApi {

		static final AtomicInteger runs = new AtomicInteger();
		static volatile CountDownLatch entered = new CountDownLatch(1);
		static volatile CountDownLatch release = new CountDownLatch(0);

		private final JdbcTemplate jdbc;

		TestApi(JdbcTemplate jdbc) {
			this.jdbc = jdbc;
		}

		record NickRequest(String nickname, String fail) {
		}

		@Idempotent
		@PostMapping("/test/nick")
		@ResponseStatus(HttpStatus.CREATED)
		Map<String, Object> nick(@AuthenticationPrincipal Jwt jwt, @RequestBody NickRequest req) throws InterruptedException {
			int run = runs.incrementAndGet();
			jdbc.update("update identity.users set nickname = ? where id = ?", req.nickname(), Long.valueOf(jwt.getSubject()));
			entered.countDown();
			release.await(5, TimeUnit.SECONDS);
			if ("4xx".equals(req.fail())) {
				throw new ApiException(ErrorCode.INVALID_REQUEST);
			}
			if ("5xx".equals(req.fail())) {
				throw new IllegalStateException("서버 오류 흉내");
			}
			return Map.of("run", run, "nickname", req.nickname());
		}

		@GetMapping("/test/ping")
		String ping() {
			return "pong";
		}
	}

	@Autowired
	JwtEncoder jwtEncoder;

	@BeforeEach
	void resetTestApi() {
		TestApi.runs.set(0);
		TestApi.entered = new CountDownLatch(1);
		TestApi.release = new CountDownLatch(0);
	}

	String signUp(String email, boolean onboarded) throws Exception {
		return onboarded ? onboardedUser(email) : signUp(email);
	}

	ResultActions nick(String access, UUID key, String nickname, String fail) throws Exception {
		var req = post("/test/nick").header("Authorization", "Bearer " + access).contentType(MediaType.APPLICATION_JSON)
			.content("{\"nickname\":\"" + nickname + "\",\"fail\":\"" + fail + "\"}");
		if (key != null) {
			req.header(IdempotencyFilter.HEADER, key.toString());
		}
		return mvc.perform(req);
	}

	String nicknameOf(String email) {
		return jdbc.queryForObject("""
			select u.nickname from identity.users u join identity.auth_credential c on c.user_id = u.id
			 where c.provider_subject = ?""", String.class, email);
	}

	// ---------- ① 토큰 ----------

	@Test
	void 만료된_토큰은_TOKEN_EXPIRED_위조는_INVALID_TOKEN() throws Exception {
		String access = signUp("t@habit.kr", true);
		String sub = String.valueOf((Integer) JsonPath.read(mvc.perform(get("/me").header("Authorization", "Bearer " + access))
			.andReturn().getResponse().getContentAsString(), "$.userId"));
		Instant past = Instant.now().minusSeconds(3600);
		String expired = token(sub, "habit-monster", past, past.plusSeconds(60));
		String otherIssuer = token(sub, "someone-else", Instant.now(), Instant.now().plusSeconds(600));

		mvc.perform(get("/me").header("Authorization", "Bearer " + expired))
			.andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("TOKEN_EXPIRED"));
		mvc.perform(get("/me").header("Authorization", "Bearer " + otherIssuer))
			.andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_TOKEN"));
		mvc.perform(get("/me"))
			.andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_TOKEN"));
	}

	String token(String sub, String issuer, Instant issuedAt, Instant expiresAt) {
		JwtClaimsSet claims = JwtClaimsSet.builder().issuer(issuer).subject(sub).issuedAt(issuedAt).expiresAt(expiresAt).build();
		return jwtEncoder.encode(JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS256).build(), claims)).getTokenValue();
	}

	// ---------- ② 사용자 상태 · 온보딩 ----------

	@Test
	void 탈퇴하면_아직_안_끝난_access_토큰도_바로_막힘() throws Exception {
		String access = signUp("w@habit.kr", true);
		mvc.perform(get("/me").header("Authorization", "Bearer " + access)).andExpect(status().isOk());

		jdbc.update("update identity.users set status = 'WITHDRAWN', withdrawn_at = now()");

		mvc.perform(get("/me").header("Authorization", "Bearer " + access))
			.andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_TOKEN"));
	}

	@Test
	void 온보딩_전에는_온보딩_요청만() throws Exception {
		String access = signUp("o@habit.kr", false);
		mvc.perform(get("/test/ping").header("Authorization", "Bearer " + access))
			.andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("ONBOARDING_REQUIRED"));
		// 실제 서버처럼 /api/v1 컨텍스트 경로가 붙어도 같은 판정
		mvc.perform(get("/api/v1/me").contextPath("/api/v1").header("Authorization", "Bearer " + access))
			.andExpect(status().isOk());
		mvc.perform(get("/api/v1/test/ping").contextPath("/api/v1").header("Authorization", "Bearer " + access))
			.andExpect(status().isForbidden());

		onboard(access, DEFAULT_ONBOARDING).andExpect(status().isCreated());
		mvc.perform(get("/test/ping").header("Authorization", "Bearer " + access)).andExpect(status().isOk());
		mvc.perform(get("/no-such-api").header("Authorization", "Bearer " + access))
			.andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("NOT_FOUND"));
	}

	// ---------- ③ 중복 방지 키 ----------

	@Test
	void 같은_키로_다시_보내면_한_번만_실행하고_처음_결과를_그대로() throws Exception {
		String access = signUp("i@habit.kr", true);
		UUID key = UUID.randomUUID();

		String first = nick(access, key, "몽이", "none")
			.andExpect(status().isCreated()).andExpect(jsonPath("$.run").value(1))
			.andReturn().getResponse().getContentAsString();
		nick(access, key, "몽이", "none")
			.andExpect(status().isCreated())
			.andExpect(header().string(IdempotencyFilter.REPLAYED_HEADER, "true"))
			// PostgreSQL은 JSONB로 저장해 키 순서 · 공백이 바뀔 수 있다 → 글자가 아니라 내용을 비교
			.andExpect(jsonPath("$.run").value((Integer) JsonPath.read(first, "$.run")))
			.andExpect(jsonPath("$.nickname").value((String) JsonPath.read(first, "$.nickname")));

		assertThat(TestApi.runs.get()).isEqualTo(1);
		assertThat(nicknameOf("i@habit.kr")).isEqualTo("몽이");

		// 새 키면 새 요청
		nick(access, UUID.randomUUID(), "몽이", "none").andExpect(jsonPath("$.run").value(2));
	}

	@Test
	void 키가_없거나_UUID가_아니면_400_다른_본문이면_422() throws Exception {
		String access = signUp("k@habit.kr", true);
		nick(access, null, "a", "none")
			.andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("INVALID_REQUEST"));
		mvc.perform(post("/test/nick").header("Authorization", "Bearer " + access).header(IdempotencyFilter.HEADER, "abc")
				.contentType(MediaType.APPLICATION_JSON).content("{}"))
			.andExpect(status().isBadRequest());

		UUID key = UUID.randomUUID();
		nick(access, key, "a", "none").andExpect(status().isCreated());
		nick(access, key, "b", "none")
			.andExpect(status().isUnprocessableContent()).andExpect(jsonPath("$.code").value("IDEMPOTENCY_KEY_REUSED"));
		assertThat(TestApi.runs.get()).isEqualTo(1);
		assertThat(nicknameOf("k@habit.kr")).isEqualTo("a");
	}

	@Test
	void 규칙_위반_4xx는_변경을_되돌리고_결과만_저장() throws Exception {
		String access = signUp("f@habit.kr", true);
		UUID key = UUID.randomUUID();

		nick(access, key, "바뀌면안됨", "4xx").andExpect(status().isBadRequest());
		assertThat(nicknameOf("f@habit.kr")).isNull(); // 닉네임 변경이 되돌려짐

		nick(access, key, "바뀌면안됨", "4xx")
			.andExpect(status().isBadRequest()).andExpect(header().string(IdempotencyFilter.REPLAYED_HEADER, "true"));
		assertThat(TestApi.runs.get()).isEqualTo(1);
	}

	@Test
	void 서버_오류_5xx는_저장하지_않아_같은_키로_다시_시도_가능() throws Exception {
		String access = signUp("s@habit.kr", true);
		UUID key = UUID.randomUUID();

		assertThatThrownBy(() -> nick(access, key, "x", "5xx")).hasRootCauseInstanceOf(IllegalStateException.class);
		assertThat(nicknameOf("s@habit.kr")).isNull();

		assertThatThrownBy(() -> nick(access, key, "x", "5xx")).hasRootCauseInstanceOf(IllegalStateException.class);
		assertThat(TestApi.runs.get()).isEqualTo(2); // 저장된 결과가 없어서 다시 실행됨
	}

	@Test
	void 같은_키가_처리_중이면_409_끝나면_처음_결과() throws Exception {
		String access = signUp("c@habit.kr", true);
		UUID key = UUID.randomUUID();
		TestApi.release = new CountDownLatch(1);

		CompletableFuture<Integer> slow = CompletableFuture.supplyAsync(() -> {
			try {
				return nick(access, key, "느림", "none").andReturn().getResponse().getStatus();
			}
			catch (Exception e) {
				throw new IllegalStateException(e);
			}
		});
		assertThat(TestApi.entered.await(5, TimeUnit.SECONDS)).isTrue();

		nick(access, key, "느림", "none")
			.andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("REQUEST_IN_PROGRESS"));

		TestApi.release.countDown();
		assertThat(slow.get(10, TimeUnit.SECONDS)).isEqualTo(201);
		nick(access, key, "느림", "none")
			.andExpect(status().isCreated()).andExpect(header().string(IdempotencyFilter.REPLAYED_HEADER, "true"));
		assertThat(TestApi.runs.get()).isEqualTo(1);
	}
}
