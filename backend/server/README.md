# 습관 몬스터 서버 (Spring Boot)

Spring Boot 4.1 · Java 21 · PostgreSQL. **인증 + 공통 기반**(오류 형식 · 토큰 만료 구분 · 탈퇴/온보딩 차단 · 중복 방지 키 · 업무 날짜) +
**게임 3-0 ~ 3-3단계**(설정값 · 지갑 · 온보딩 · 출석 · 메인 조회 · 체크인)가 들어 있어요. API 계약은 「습관몬스터 API 명세 v5」(`docs/api/`) + `docs/진행현황-및-계획.md` 1장. **모든 경로는 `/api/v1` 아래**예요.

> **JDK 21 이상**이 필요해요. Gradle은 `JAVA_HOME`의 JDK로 돌아가니, `JAVA_HOME`이 그보다 낮은 버전(예: jdk-20)이면
> `release version 21 not supported` 오류가 나요. `JAVA_HOME`을 jdk-21 이상으로 바꾸거나 IntelliJ에서 Gradle JVM을 21+로 고르세요.

## 바로 띄워 보기 (`local` 프로필 — Docker DB에 붙음)

먼저 아래 "PostgreSQL로 띄우기" 1번처럼 Docker DB를 띄워요 (`backend/`에서 `docker compose up -d`, 이 PC는 포트 5435).
그다음 환경변수 없이:

```bash
./gradlew bootRun --args='--spring.profiles.active=local'
```

`local` 프로필에는 DB 주소(`localhost:5435`, 계정 `habit`/`habit`) · 로컬 전용 JWT 키 · 카카오/구글 공개 값이 들어 있어요 (`application-local.properties`).
`local` 프로필은 **8081 포트**로 떠요 (8080은 이 PC의 다른 프로젝트 서버가 써서). 다른 포트가 필요하면 `--args='--spring.profiles.active=local --server.port=8082'`처럼.
앱은 `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8081/api/v1` (에뮬레이터에서 PC = `10.0.2.2`).
실제 폰(adb 연결)은 `10.0.2.2`가 안 되니 `adb reverse tcp:8081 tcp:8081`(폰의 localhost:8081 → PC)을 건 뒤 `--dart-define=API_BASE_URL=http://localhost:8081/api/v1`. adb가 끊기면 reverse도 풀려서 다시 건다.
`API_BASE_URL` 없이 실행하면 서버 없이 샘플 데이터로 도는 시연 모드다 (가짜 데이터가 보이면 이것).

```bash
curl -X POST localhost:8081/api/v1/auth/signup -H "Content-Type: application/json" -d '{"email":"me@habit.kr","password":"password1"}'
```

### 웹(Chrome)으로 붙여 보기 — 로컬 확인용

`local` 프로필은 `http://localhost:5000`에서 오는 브라우저 요청을 허용해요 (CORS, 결정 D-44). 서버를 위처럼 띄운 뒤 `frontend/`에서:

```bash
flutter run -d chrome --web-port=5000 --dart-define=API_BASE_URL=http://localhost:8081/api/v1
```

- **웹에서는 소셜 로그인(카카오 · 구글)이 안 돼요. 이메일로 가입 · 로그인하세요.**
- 포트를 꼭 `5000`으로 — 다른 포트면 서버가 브라우저 요청을 막아요. 다른 출처를 열려면 `app.cors.allowed-origins`(쉼표로 여러 개, 환경변수 `CORS_ALLOWED_ORIGINS`).
- 기본 설정(프로필 없이)은 CORS가 꺼져 있어요. 앱(Android · iOS)은 브라우저가 아니라 상관없어요.

> 10-19부터 메모리 DB(H2)는 없어요 (결정 D-41). 게임 테이블 · 설정값이 PostgreSQL 전용이라 H2로는 서버가 뜨지 않았어요.

## PostgreSQL로 띄우기

1. **Docker로 DB 띄우기** (권장): `backend/.env.example`을 `backend/.env`로 복사하고 `HM_DB_DIR`에 공식 DB 파일 폴더(`schema.sql` · `seed.sql`, 스키마 v1.7 + 시드 v1.8 — 저장소의 `docs/데이터베이스`) 경로를 적은 뒤
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

## EC2 배포 서버 (systemd, 11-11부터 — 결정 D-65)

EC2(Ubuntu, 사용자 `ubuntu`)에서 서버는 **systemd 서비스 `habit-monster`**로 돈다. 서버가 죽거나 EC2가 재부팅돼도 저절로 다시 뜬다.

| 무엇 | 어디 |
| --- | --- |
| 실행할 jar | `/home/ubuntu/app-new.jar` |
| 비밀값 (환경 변수) | `/etc/habit-monster/app.env` — root만 읽기(600), 한 줄에 `이름='값'`. **저장소 · 메신저에 올리지 않는다** |
| 서비스 정의 | `/etc/systemd/system/habit-monster.service` — `java -Xmx256m -jar …`, `Restart=on-failure` |
| 로그 | `journalctl -u habit-monster` (옛 `~/app-new.log`는 11-11 전까지) |
| 포트 | 8080 (프로필 없음 = 기본값) |

```bash
ssh -i <pem 경로> ubuntu@<EC2 IP>
sudo systemctl restart habit-monster      # 다시 띄우기
sudo systemctl status habit-monster       # 상태
journalctl -u habit-monster -f            # 로그 실시간
sudoedit /etc/habit-monster/app.env       # 비밀값 바꾸기 → restart
```

새 코드 배포: PC(`backend/server`)에서 `./gradlew bootJar` → `scp -i <pem> build/libs/<jar>.jar ubuntu@<EC2 IP>:~/app-new.jar` → `sudo systemctl restart habit-monster`. DB 계약이 바뀐 jar면 **Supabase에 SQL을 먼저** 적용한다.

- `-Xmx256m`: EC2 메모리가 908MB · 스왑 없음. 11-06에 기본 설정 서버가 메모리 부족으로 강제 종료됐다(`Out of memory: Killed process … (java)`).
- 11-11 `app.env`에 든 이름 (7개): `SPRING_DATASOURCE_URL` · `SPRING_DATASOURCE_USERNAME` · `SPRING_DATASOURCE_PASSWORD` · `JWT_SECRET` · `GEMINI_API_KEY` · `KAKAO_APP_ID` · `GOOGLE_CLIENT_IDS`. 옛 이름 `SPRING_DATASOURCE_*`는 `DB_*`보다 우선한다. 카카오 · 구글 값은 공개 값이라 `application-local.properties`와 같다.

## 테스트

```bash
./gradlew test
```

**Docker가 켜져 있어야 해요.** 테스트가 `postgres:16` 컨테이너를 스스로 띄우고(Testcontainers) 저장소의 `docs/데이터베이스/schema.sql` → `seed.sql`을 적용한 뒤,
모든 테스트가 그 실제 PostgreSQL에서 돌아요 (결정 D-33). 로컬 개발 DB(5435)는 건드리지 않아요. 다른 폴더의 SQL로 돌리려면 환경변수 `HM_DB_DIR`.
컨테이너는 한 번만 띄워 모든 테스트 클래스가 같이 쓰고, 테스트마다 `truncate identity.users cascade`로 사용자 데이터만 비워요 (마스터 · 설정은 남음).
공통 바닥은 `support/PostgresTest` (가입 · 기본 온보딩 도우미 포함).

| 테스트 | 검사하는 것 |
| --- | --- |
| `AuthApiTest` · `CommonApiTest` · `BusinessDatesTest` | 회원 · 토큰 · 탈퇴/온보딩 차단 · 중복 방지 키(재전송 · 다른 본문 · 4xx · 5xx · 동시) · 업무 날짜 |
| `BalanceConfigTest` | 시드 수치를 타입대로 읽음, 시드의 모든 키가 "읽음/안 씀" 목록에 있음, 필요한 키가 없으면 시작 실패 |
| `WalletServiceTest` | 적립 · 차감 = 잔액 + 원장, 0원은 원장 없음, 같은 (사유, ref) 한 번, 잔액 부족 422, 동시 차감에도 음수 없음 |
| `ArchitectureTest` | 모듈 규칙: 저장소는 자기 모듈 안에서만, 엔티티 `@Table(schema)` = 패키지, SQL 문자열의 `스키마.테이블` = 자기 스키마 |
| `OnboardingApiTest` | 온보딩 전 허용/차단, 모든 모듈 행 생성, 대화 상대 규칙, 여러 오류 400 + 아무것도 안 남음, 409 · 같은 키 재전송, 출석 연속 일수, 탈퇴 정리 |
| `MainQueryApiTest` | 상단 바 · 오늘 요약(체크인 전/후) · 몬스터 목록/상세 · 남의 몬스터 404 · 상점 · 가방 · 습관 · 목표, 온보딩 전 403 |
| `CheckinApiTest` | 명세 예시 그대로(353G · 88% · Lv.3 → 4 · 기간 보너스 280G · 원장 3줄), 새로 나오는 종, 동점은 등록 순서 · 상위 3만, 전부 못했어 → 탐색 1, 반영 안 된 습관도 기간 보너스(B1), 조회 제출 전/후, 다시 체크(보상 그대로 · 같은 키 같은 응답), 404 · 409 셋 · 400, 같은 날 동시 제출 → 하나만 |
| `CorsTest` | 허용 출처(localhost:5000)의 사전 요청은 토큰 없이 통과 · 다른 출처 · 허용 안 한 헤더는 403 · 오류 응답에도 허용 헤더, 기본 설정은 꺼짐 |
| `ExploreApiTest` | (랜덤 고정) 꽝 · 가진 종 15G(원장) · 안 가진 종 등장(처음만 `newlySeen`) · 다시 탐색 → SKIPPED · 남은 등장 200/204, 잡기(필드 · 볼 −1 · 소모 기록) · 놓침 → 다시 던지기 409 · 볼 0 → 422(등장 남음) · 꽝/가진 종에 던지기 409 · 남의 탐색 404, 다음 날: 어제 등장 409 · EXPIRED, 기회 다 쓰면 422 · 체크인 전 409 · 날짜 409 · 같은 키 재전송, 같은 등장에 동시에 두 번 → 볼 1개, 5마리째 해금권 한 번 · 필드 5마리면 가방 |
| `PurchaseApiTest` | 구매 = 골드 − · 가방 + · 원장 한 줄(가격 스냅샷), 골드 부족 422(아무것도 안 남음), 수량 1 ~ 99 · 없는 아이템 400, 같은 키 재전송 → 골드 한 번, 다른 키 동시 두 건 → 잔액 음수 없음 |
| `StatsApiTest` | 첫날(오늘만 · 평균 없음), 14일 · 7일 범위와 순서, 다시 체크한 최신 값, 평균은 한 날만, 카테고리(연 것 레벨 · 최대 레벨 필요량 null · 잠긴 것 레벨 없음) (10-28) |
| `DexApiTest` | 요약(가진 · 본 · 전체 수 · 해금권), 카테고리 목록 세 상태 · 모르는 종은 이름 · 번호 없음, 상세 404 `NOT_DISCOVERED`, 남의 도감 안 섞임, 열기(Lv.1 · 시작 몬스터 · 해금권 사용 · 422 · 409 · 404), 필드 꽉 차면 가방, 시작 몬스터로 기준값 → 해금권, 같은 키 → 한 번 (10-28) |
| `GoalApiTest` | 등록(기간 = 오늘 ~ +6 · +29, 빈 상세 → 없음) · 값 400 · 칸 422, 완료해도 기간 끝까지 칸 차지 · 기간이 끝나거나 지우면 빔, 수정(안 보냄 / null 구분 · `goalType` 400), 완료 골드 · 원장, 등록한 날 409, 완료 · 기간 끝 409, 남의 목표 404, 같은 키 → 한 번, 동시 완료 → 한 번 (10-28) |
| `GrowthApiTest` | 물약(레벨업 · Lv.10 진화 · 최대 레벨 422 · 물약 없음 422 · 물약 아닌 코드 400 · 같은 키 → 물약 1개), 교감(하루 1번씩 · 다음 날 다시 · 최대면 gain 0 · DRAG 400 · 동시 두 번 → 한 번), 말 걸기(단계 대사, 랜덤 고정), 필드 1마리 · 5마리 제한, 대화 상대(가방에 있어도 · 1마리), 남의 몬스터 404 |
| `ScoringTest` | 점수 공식(미달 · 달성 · 초과 최대 25 · O/X · 수면 범위 경계), 달성률 · 전체 성실도, 선택지(B3 · 수면 ± 2칸), 선택지 밖 값 거절 |

## 구조

```
kr.habitmonster
├─ auth/            AuthController · AuthService · TokenService · AuthRules · AuthDtos
│  └─ social/       KakaoVerifier · GoogleVerifier (토큰을 서버가 직접 검증)
├─ identity/        identity 스키마 엔티티 (User · AuthCredential · RefreshToken) + 저장소
├─ config/          SecurityConfig (/auth/** 만 공개) · CorsConfig(로컬 웹 확인용, 기본 꺼짐) · JwtConfig(만료 구분) · UserGateFilter(탈퇴 · 온보딩 차단) · AuthProperties
│                   · BalanceConfig (config.balance_config 수치, 없는 키면 시작 실패)
├─ idempotency/     @Idempotent · IdempotencyFilter · IdempotencyStore (중복 요청 방지 키)
├─ common/          ErrorCode · ApiException · ApiExceptionHandler ({code, message, errors?}) · ErrorResponses · BusinessDates(업무 날짜) · Decimals
│
│  ── 게임 모듈: 패키지 = DB 스키마. 저장소(SQL, package-private)는 자기 스키마 테이블만 (ArchitectureTest) ──
├─ habit/           카테고리 · 측정 항목 마스터, 습관 · 기간 · 출석 · 체크인(점수 · 상위 3 · 카테고리 경험치 · 기간 보너스) · Scoring(점수 공식 · 선택지) (+ 탈퇴 시 습관 이름 비움)
├─ goal/            목표 (+ 탈퇴 시 제목 비움)
├─ wallet/          WalletService — 골드 증감은 여기로만 (잔액 + 원장, 조건부 차감)
├─ stats/           GET /stats (습관 모듈의 출석 · 체크인 · 카테고리를 모으는 조회, 4-4)
├─ shop/            상점 목록 · 가방 · 구매(서버 가격 · 가방 · 지갑) · 볼 · 물약 1개 쓰기(조건부 차감 + 소모 기록)
├─ monster/         종 마스터 · 스타터 지급 · 내 몬스터 목록/상세 · 오늘 탐색 기회(체크인 때 생성) · 대화 상대 · 레벨업으로 새로 나오는 종
│                   · 탐색 1회(꽝 · 가중치 뽑기) · 남은 등장 · 포획 · Dice(랜덤 한 곳, 테스트가 고정)
│                   · 물약(경험치 · 레벨 · 진화 · 성장 기록) · 교감 · 말 걸기 · 필드/가방 · 대화 상대
│
│  ── 조율 (테이블 없음, 각 모듈 서비스만 부름) ──
├─ onboarding/      GET /categories · POST /onboarding (회원 → 습관 → 목표 → 몬스터 → 지갑 = 잠금 순서)
├─ dex/             GET /dex · /dex/categories/{code} · /dex/species/{id} · POST /categories/{code}/unlock (습관 + 몬스터를 모으는 조율, 4-3)
├─ home/            GET /me/status · /me/today (여러 모듈 값을 모으는 조회)
├─ checkin/         GET · POST · PUT /checkins/today (습관 → 몬스터(탐색 기회) → 지갑(골드) = 잠금 순서)
└─ explore/         POST /explores · GET /explores/pending · POST /explores/{id}/capture (습관(잠금 · 레벨 · 해금권) → 몬스터 → 상점(볼) → 지갑)
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

다음에 붙일 것: AI 대사 · 알림(5), 출시 준비(6) (4단계 API는 모두 됨) — `docs/handoff/` (서버 담당 PC에만 있음 — 원격 저장소에서 뺌, 10-23), 남은 일은 `docs/할-일.md`.
