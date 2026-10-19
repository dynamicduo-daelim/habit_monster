package kr.habitmonster.support;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;

import com.jayway.jsonpath.JsonPath;

import kr.habitmonster.idempotency.IdempotencyFilter;

import org.junit.jupiter.api.BeforeEach;
import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.utility.MountableFile;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

/**
 * 서버 테스트의 공통 바닥 — **실제 PostgreSQL 16**에 공식 {@code schema.sql} → {@code seed.sql}을 적용하고 그 위에서 돈다 (결정 D-33).
 *
 * <p>왜: 게임 테이블은 PostgreSQL 전용 제약 · 트리거 · 시드(카테고리 · 몬스터 · 설정값)에 기댄다. 예전처럼 H2(메모리 DB)에
 * JPA가 만든 테이블로 검사하면, H2에선 통과하고 PostgreSQL에서만 나는 버그를 못 잡는다 (0단계에서 실제로 있었다).
 *
 * <p>컨테이너는 테스트 실행(JVM) 한 번에 하나만 띄워 모든 테스트 클래스가 같이 쓴다 (Testcontainers "싱글턴 컨테이너").
 * 테스트끼리는 {@link #cleanUserData()}가 사용자 데이터만 지워서 서로 영향을 주지 않는다. 마스터 데이터 · 설정값은 남는다.
 * Docker가 켜져 있어야 한다.
 */
@SpringBootTest(properties = {
	"app.auth.jwt-secret=test-secret-0123456789abcdef-0123456789",
	// 소셜 키는 비워서 "설정 전" 상태로 (실제 카카오 · 구글에 접속하지 않게)
	"app.auth.google.client-ids=", "app.auth.kakao.app-id=" })
@AutoConfigureMockMvc
public abstract class PostgresTest {

	/** 공식 DB 설계 폴더. 기본은 저장소의 {@code docs/데이터베이스} (테스트는 {@code backend/server}에서 실행된다). */
	static final Path DB_DIR = Path.of(System.getenv().getOrDefault("HM_DB_DIR", "../../docs/데이터베이스"));

	static final PostgreSQLContainer POSTGRES = new PostgreSQLContainer("postgres:16")
		.withEnv("TZ", "Asia/Seoul")
		// 이미지가 처음 뜰 때 이 폴더의 .sql을 이름 순서대로 적용한다 (오류가 나면 컨테이너가 실패)
		.withCopyFileToContainer(sql("schema.sql"), "/docker-entrypoint-initdb.d/10-schema.sql")
		.withCopyFileToContainer(sql("seed.sql"), "/docker-entrypoint-initdb.d/20-seed.sql");

	static {
		POSTGRES.start();
	}

	private static MountableFile sql(String name) {
		Path file = DB_DIR.resolve(name);
		if (!Files.exists(file)) {
			throw new IllegalStateException("공식 SQL이 없어요: " + file.toAbsolutePath() + " (HM_DB_DIR로 폴더를 지정할 수 있어요)");
		}
		return MountableFile.forHostPath(file);
	}

	@DynamicPropertySource
	static void database(DynamicPropertyRegistry r) {
		r.add("spring.datasource.url", POSTGRES::getJdbcUrl);
		r.add("spring.datasource.username", POSTGRES::getUsername);
		r.add("spring.datasource.password", POSTGRES::getPassword);
	}

	@Autowired
	protected MockMvc mvc;

	@Autowired
	protected JdbcTemplate jdbc;

	/**
	 * 테스트마다 사용자 데이터를 비운다. {@code identity.users}를 참조하는 테이블(습관 · 지갑 · 몬스터 · 중복 방지 키 …)이
	 * CASCADE로 모두 비워지고, 사용자를 참조하지 않는 마스터 데이터(카테고리 · 종 · 상점 · 설정)는 그대로 남는다.
	 */
	@BeforeEach
	protected void cleanUserData() {
		jdbc.execute("truncate identity.users cascade");
	}

	/** 기본 온보딩: 운동 · 공부, 습관 1개(아침 러닝 30분 · 30일), 주간 목표 1개. */
	protected static final String DEFAULT_ONBOARDING = """
		{"categories": ["ex", "st"],
		 "habits": [{"categoryCode": "ex", "measureTypeId": 1, "name": "아침 러닝", "dailyTarget": 30, "periodCode": "D30"}],
		 "goals": [{"goalType": "WEEKLY", "title": "헬스장 3번 가기"}]}""";

	/** 이메일로 가입하고 access 토큰을 돌려준다 (온보딩 전). */
	protected String signUp(String email) throws Exception {
		String res = mvc.perform(post("/auth/signup").contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"" + email + "\",\"password\":\"password1\"}"))
			.andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
		return JsonPath.read(res, "$.accessToken");
	}

	/** 온보딩 요청 (새 중복 방지 키). */
	protected ResultActions onboard(String access, String body) throws Exception {
		return mvc.perform(post("/onboarding").header("Authorization", "Bearer " + access)
			.header(IdempotencyFilter.HEADER, UUID.randomUUID().toString())
			.contentType(MediaType.APPLICATION_JSON).content(body));
	}

	/** 가입 + 기본 온보딩까지 끝낸 사용자의 access 토큰. */
	protected String onboardedUser(String email) throws Exception {
		String access = signUp(email);
		onboard(access, DEFAULT_ONBOARDING).andExpect(status().isCreated());
		return access;
	}

	protected long userIdOf(String email) {
		return jdbc.queryForObject("select id from identity.users where email = ?", Long.class, email);
	}
}
