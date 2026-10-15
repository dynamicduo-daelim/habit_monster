# 습관 몬스터 서버 (Spring Boot)

Spring Boot 4.1 · Java 21 · PostgreSQL. 지금은 **인증 + 공통 기반**(오류 형식 · 토큰 만료 구분 · 탈퇴/온보딩 차단 · 중복 방지 키 · 업무 날짜)이 들어 있어요.
API 계약은 「습관몬스터 API 명세 v4」 + `docs/진행현황-및-계획.md`의 v5 변경. **모든 경로는 `/api/v1` 아래**예요.

> **JDK 21 이상**이 필요해요. Gradle은 `JAVA_HOME`의 JDK로 돌아가니, `JAVA_HOME`이 그보다 낮은 버전(예: jdk-20)이면
> `release version 21 not supported` 오류가 나요. `JAVA_HOME`을 jdk-21 이상으로 바꾸거나 IntelliJ에서 Gradle JVM을 21+로 고르세요.

## 바로 띄워 보기 (DB 없이)

```bash
./gradlew bootRun --args='--spring.profiles.active=local'
```

메모리 DB(H2)라 서버를 끄면 데이터가 사라져요. `http://localhost:8080/api/v1/auth/signup` 등으로 호출해 보면 돼요.
앱은 `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1` (에뮬레이터에서 PC = `10.0.2.2`).

```bash
curl -X POST localhost:8080/api/v1/auth/signup -H "Content-Type: application/json" -d '{"email":"me@habit.kr","password":"password1"}'
```

## PostgreSQL로 띄우기

1. **Docker로 DB 띄우기** (권장): `backend/.env.example`을 `backend/.env`로 복사하고 `HM_DB_DIR`에 공식 DB 파일 폴더(`schema.sql` · `seed.sql`, 지금은 v1.7 — `D:/teamProject/docs/데이터베이스`) 경로를 적은 뒤
   ```bash
   cd backend && docker compose up -d
   ```
   처음 뜰 때 `schema.sql` → `seed.sql` 순서로 자동 적용돼요 (서버가 쓰는 중복 방지 키 테이블도 v1.7부터 공식 스키마에 있음). 다시 적용하려면 `docker compose down -v` 후 다시 `up`.
   이미 PC에 PostgreSQL이 5432를 쓰고 있으면 `.env`의 `DB_PORT`를 5433 등으로 바꾸고 `DB_URL`도 맞춰요.
   (직접 만든 DB를 쓰면 위 세 파일을 같은 순서로 실행)
2. 환경변수를 넣고 실행

| 환경변수 | 설명 |
| --- | --- |
| `DB_URL` | 기본 `jdbc:postgresql://localhost:5432/habit_monster` |
| `DB_USER` / `DB_PASSWORD` | DB 계정 |
| `JWT_SECRET` | access 토큰 서명 키, **32자 이상** 랜덤 문자열 (필수) |
| `KAKAO_APP_ID` | 카카오 개발자 콘솔의 앱 ID (숫자). 없으면 카카오 로그인은 `SOCIAL_NOT_CONFIGURED` |
| `GOOGLE_CLIENT_IDS` | 구글 OAuth 클라이언트 ID들, 쉼표로 (Android · iOS · 웹) |

JPA는 테이블을 만들거나 바꾸지 않아요 (`ddl-auto=none`). 스키마는 SQL 파일이 기준이에요.

## 테스트

```bash
./gradlew test
```

`local` 프로필(H2)로 가입 · 로그인 · refresh 교체/재사용 감지 · 로그아웃 · 소셜(카카오는 가짜로 대체) · 탈퇴 계정을 검사해요.
`CommonApiTest`는 공통 기반(토큰 만료 · 탈퇴 즉시 차단 · 온보딩 차단 · 중복 방지 키의 재전송/다른 본문/4xx/5xx/동시 요청), `BusinessDatesTest`는 업무 날짜 경계를 검사해요.

## 구조

```
kr.habitmonster
├─ auth/            AuthController · AuthService · TokenService · AuthRules · AuthDtos
│  └─ social/       KakaoVerifier · GoogleVerifier (토큰을 서버가 직접 검증)
├─ identity/        identity 스키마 엔티티 (User · AuthCredential · RefreshToken) + 저장소
├─ config/          SecurityConfig (/auth/** 만 공개) · JwtConfig(만료 구분) · UserGateFilter(탈퇴 · 온보딩 차단) · AuthProperties
├─ idempotency/     @Idempotent · IdempotencyFilter · IdempotencyStore (중복 요청 방지 키)
└─ common/          ErrorCode · ApiException · ApiExceptionHandler ({code, message, errors?}) · ErrorResponses · BusinessDates(업무 날짜)
```

### 요청이 지나가는 순서 (API 명세 v4 "요청 검사 순서")

```
요청 ─▶ ① 토큰 검사 (Spring Security)        없음 · 위조 → 401 INVALID_TOKEN / 만료 → 401 TOKEN_EXPIRED
     ─▶ ② UserGateFilter                     탈퇴 · 없는 사용자 → 401 INVALID_TOKEN / 온보딩 전 → 403 ONBOARDING_REQUIRED
     ─▶ ③ IdempotencyFilter (@Idempotent만)  같은 키 → 처음 결과 / 다른 본문 → 422 / 처리 중 → 409
     ─▶ 컨트롤러 → ④ 소유권 → ⑤ 업무 날짜(BusinessDates.requireToday) → ⑥ 값 형식 → ⑦ 규칙
```

- 쓰기 API에 `@Idempotent`를 붙이면 헤더 `Idempotency-Key: <UUID>`가 필수가 되고, 요청 전체가 트랜잭션 하나로 묶여요.
  결과 저장과 비즈니스 변경이 같이 커밋되므로 "골드는 들어갔는데 결과는 저장 안 됨" 같은 반쪽 상태가 없어요.
- 업무 날짜는 `BusinessDates.today()`만 써요 (`LocalDate.now()` 금지 — 서버 시간대와 00시 경계가 달라질 수 있음).

다음에 붙일 것: habits · checkins · explore · monsters · shop · goals (`../README.md` API 초안).
