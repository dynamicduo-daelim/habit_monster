# 루틴몬 서버 · DB — Claude 작업 안내

루트 `CLAUDE.md`(원칙 · 기록 · 변경 통제)를 따르고, 서버(`backend/`)를 고칠 때는 이것도 지킨다.
계약의 기준: **API 명세 v5** `docs/api/습관몬스터_API명세_v5.md` · **DB 설계** `docs/데이터베이스/` (스키마 v1.7 + 시드 v1.8).
둘 다 **사용자(윤서)가 직접 썼다** — DB · 명세 파일은 Claude가 고치지 않고, 바꿔야 하면 사용자에게 제안한다.
명세와 다르게 구현하기로 한 것은 `docs/진행현황-및-계획.md` 1장 (A1 ~ D6) · `docs/결정-기록.md` D-23 ~ D-44. 남은 단계 지시서는 `docs/handoff/`.

## 이미 있는 기반 — 새로 만들지 말고 쓴다 (`server/src/main/java/kr/habitmonster/`)
| 무엇 | 쓰는 법 |
| --- | --- |
| 경로 `/api/v1` | `server.servlet.context-path`. 컨트롤러는 `/auth/login`처럼 접두사 없이 매핑 |
| 오류 `common/ApiException` · `ErrorCode` | `throw new ApiException(ErrorCode.X)` → `{code, message, errors?, provider?}`. 새 코드는 `ErrorCode`에 (명세 "에러 코드 목록"의 이름 · 상태 그대로) |
| 업무 날짜 `common/BusinessDates` | `today()` · `weekStart()` · `monthStart()` · `requireToday(businessDate)`(다르면 409). **`LocalDate.now()` 금지** |
| 중복 방지 키 `idempotency/@Idempotent` | 컨트롤러 메서드에 붙이면 `Idempotency-Key` 필수 · 같은 키 재전송은 첫 결과 · 요청 전체가 트랜잭션 하나 (D-25 · D-27). 명세의 대상 + 온보딩 · 습관 추가 · 목표 등록 · 기간 연장(A3) |
| 사용자 검사 `config/UserGateFilter` | 탈퇴 401, 온보딩 전엔 `BEFORE_ONBOARDING` 경로만 |
| 탈퇴 정리 `auth/WithdrawalStep` | 새 모듈은 이걸 구현한 `@Component`로 자기 데이터 정리 |
| 사용자 id | `@AuthenticationPrincipal Jwt jwt` → `Long.valueOf(jwt.getSubject())` |

요청 검사 순서: ① 토큰 → ② `UserGateFilter` → ③ `IdempotencyFilter` → 컨트롤러 ④ 소유권(남의 것은 **404**, C3) → ⑤ 업무 날짜 → ⑥ 값 형식 → ⑦ 규칙.

## DB 설계 원칙 (`schema.sql` 머리말 요약 — 꼭 원문도 읽기)
- **모듈 = 스키마** (`identity` · `habit` · `goal` · `wallet` · `shop` · `monster` · `config` · `ai` · `api`). 서버 패키지도 같은 이름으로 나누고, **각 모듈의 저장소는 자기 스키마 테이블만** 다룬다. 다른 모듈 데이터는 그 모듈 서비스를 부른다. 한 요청 = 트랜잭션 하나.
- 사용자 잠금 순서 고정: `habit_user → goal_user → monster_user → inventory → wallet` (`FOR NO KEY UPDATE`).
- 골드 · 볼 · 물약 차감은 조건부 UPDATE(`… WHERE balance >= ?`), `CHECK(>= 0)` 위반은 422. 골드는 잔액 + 원장(`UNIQUE(reason_code, ref_id)`), 금액 0이면 원장에 안 씀.
- **수치는 `config.balance_config`에서** (하드코딩 금지). 행은 지우지 않는다(상태값). 보상 기준값 · 완료 목표 · 끝난 탐색은 트리거가 수정을 막는다.
- JPA는 테이블을 만들지 않는다 (`ddl-auto=none`) — 엔티티 컬럼은 `schema.sql`과 정확히 같게.
- **앱 `frontend/lib/data/catalog.dart`의 코드(카테고리 · 몬스터 종 · 측정 항목 순서)는 DB 시드와 같아야 한다.** (시드 v1.8 = 앱의 28종, id는 카테고리 순서 · 스타터 1/6/10/15/19/23 — 종을 바꾸면 앱 · 시드 · `verify.sql`을 같이)

## 실행 · 테스트
- 로컬 DB: `backend/`에서 `docker compose up -d` — `backend/.env`(커밋 금지, `.env.example` 참고)의 `HM_DB_DIR`가 공식 SQL 폴더(`…/docs/데이터베이스`), 이 PC는 `DB_PORT=5435`. 다시 적용: `docker compose down -v && docker compose up -d`
- 테스트: `server/`에서 PowerShell로 `.\gradlew.bat test` — **Docker가 켜져 있어야 한다.** 테스트가 postgres:16 컨테이너를 스스로 띄우고 `docs/데이터베이스/schema.sql` · `seed.sql`을 적용해 그 위에서 돈다 (Testcontainers, D-33). 새 테스트는 `support/PostgresTest`를 상속 (가입 · 기본 온보딩 도우미, 테스트마다 사용자 데이터 비움). H2는 없다 (D-41)
- 게임 모듈 저장소는 `JdbcClient` SQL, package-private (D-34). 여러 모듈을 모으는 일은 테이블 없는 조율 서비스(`onboarding/` · `home/` · `checkin/`)가 각 모듈 서비스를 부른다. 수치는 `config/BalanceConfig`, 골드는 `wallet/WalletService`로만. 규칙은 `ArchitectureTest`가 검사
- 실행 (간단히): Docker DB를 띄운 뒤 `.\gradlew.bat bootRun --args='--spring.profiles.active=local'` — `local` 프로필 = 5435 DB + **8081 포트** + 로컬 JWT 키 + 카카오 · 구글 공개 값 (D-41)
- 실행 (환경변수로): `$env:DB_URL='jdbc:postgresql://localhost:5435/habit_monster'; $env:DB_USER='habit'; $env:DB_PASSWORD='habit'; $env:JWT_SECRET='local-dev-secret-change-me-0123456789abcdef'; .\gradlew.bat bootRun --args='--server.port=8081'` (8080은 다른 서버가 떠 있을 수 있음)
- 실제 DB 테스트의 정리는 `PostgresTest`가 `truncate identity.users cascade` 한 줄로 한다 (외래키를 따라 사용자 데이터만 비움, 마스터 · 설정은 남음)
- 새 API를 만들면 `backend/README.md`의 API 표를 갱신한다
