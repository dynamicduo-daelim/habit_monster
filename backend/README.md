# backend

서버는 **Spring Boot**로 만들어요 (DB: PostgreSQL, 스키마는 공유 폴더의 `schema.sql` v1.6 — 메모는 `backend/db/README.md`).

## API 초안

| 메서드 | 경로 | 설명 |
| --- | --- | --- |
| POST | /auth/… | 회원가입 · 로그인 · 소셜 로그인 · 토큰 갱신 · 로그아웃 (아래 "인증 API") |
| GET | /me | 골드 · 성실볼 · 탐색 남은 횟수 · 연속 출석 |
| GET/POST/PATCH/DELETE | /habits | 습관 CRUD (카테고리, 측정 방식, 목표량, 기간) |
| POST | /checkins | 오늘 습관 기록 → 성실도·골드·카테고리 레벨 계산 결과 반환. 같은 날 다시 보내면 기록만 고침 (보상은 첫 확정 그대로) |
| POST | /explore | 탐색 1회 → 몬스터 등장 (`ENCOUNTER`, 아직 안 잡음) / 아무도 없음 (`MISS`, 40%) |
| POST | /explore/throw | 나타난 몬스터에게 성실볼 1개 → 잡음(새 몬스터) / 잡음(이미 가진 종 → +15G) / 놓침(도망). 잡힐 확률은 희귀도별 80 · 60 · 40% |
| POST | /explore/skip | 던지지 않고 넘기기 (보상 없음) |
| GET | /monsters | 내 몬스터 목록 (레벨 · EXP · 호감도 · 필드/가방) |
| POST | /monsters/{id}/pet, /play | 하루 1회 교감 → 호감도 |
| POST | /monsters/{id}/feed | 물약 사용 → EXP · 레벨업 · 진화 |
| PATCH | /monsters/{id} | 필드 ↔ 가방 이동 (필드 최대 5) |
| POST | /shop/buy | 물약 · 성실볼 구매 (개수 `count` 포함, 합계 골드는 서버가 계산) |
| GET/POST/PATCH/DELETE | /goals | 주간(3) · 월간(1) 목표, 달성 체크 시 골드 |
| GET | /stats | 최근 7일 성실도, 카테고리별 레벨, 출석 |

## 인증 API (Spring Boot)

앱은 `frontend/lib/core/auth/auth_service.dart`의 `AuthService` 인터페이스만 써요.
지금은 `FakeAuthService`(앱 안에서만 동작)이고, 서버가 생기면 아래 API를 부르는 `HttpAuthService`로 바꾸면 돼요.
화면(로그인 · 이메일 가입 · 설정의 로그아웃)은 그대로예요.

### 흐름

1. 앱 시작 → 저장된 refresh 토큰이 있으면 `POST /auth/refresh` (자동 로그인), 없으면 로그인 화면
2. 로그인 성공 → `onboardingDone`이 false면 온보딩, true면 홈
3. 온보딩 끝 → `PATCH /me/onboarding` (다음 로그인부터 바로 홈)
4. 설정 → 로그아웃 → `POST /auth/logout` → 로그인 화면

### 엔드포인트

| 메서드 | 경로 | 요청 | 설명 |
| --- | --- | --- | --- |
| POST | /auth/signup | `{email, password}` | 이메일 가입. `EMAIL` 자격 생성 (`users.onboarded_at`은 비어 있음) |
| POST | /auth/login | `{email, password}` | 이메일 로그인 |
| POST | /auth/social/{kakao\|google} | `{token}` | 소셜 로그인. 처음이면 자동 가입 |
| POST | /auth/refresh | `{refreshToken}` | access 재발급 + refresh 교체(rotation) |
| POST | /auth/logout | `{refreshToken}` | 그 refresh 토큰 폐기 (`revoked_at`) |
| GET | /me | (Bearer) | 위 공통 응답의 `user` + 게임 요약 |
| PATCH | /me/onboarding | (본문 없음) | 온보딩 완료 → `users.onboarded_at` 기록 (DB v1.5: 단계 없이 마지막에 한 번) |

로그인 계열 응답 (앱의 `AuthSession`과 같은 모양):

```json
{
  "accessToken": "eyJ...",
  "refreshToken": "랜덤 64바이트 base64url",
  "user": { "id": "123", "provider": "KAKAO", "email": "a@b.com", "nickname": null, "onboardingDone": false }
}
```

오류 응답은 `{ "code": "...", "message": "화면에 보여줄 문구" }` — 코드는 앱과 같아요.

| code | HTTP | 언제 |
| --- | --- | --- |
| INVALID_EMAIL | 400 | 이메일 형식 오류 |
| WEAK_PASSWORD | 400 | 비밀번호 8자 미만 (`AuthRules.minPasswordLength`) |
| EMAIL_TAKEN | 409 | 이미 가입된 이메일 |
| INVALID_CREDENTIALS | 401 | 이메일/비밀번호 불일치 (어느 쪽이 틀렸는지 알려주지 않음) |
| INVALID_TOKEN | 401 | 소셜 토큰 검증 실패 · refresh 만료/폐기 |

### 서버가 지킬 것 (DB `identity` 스키마)

- **이메일**: 소문자 + 앞뒤 공백 제거 후 `auth_credential.provider_subject`에 저장. 비밀번호는 **BCrypt**(`password_hash`), 원문 저장·로그 금지.
- **소셜**: 앱이 보낸 토큰을 서버가 **직접 검증**하고 그 결과의 사용자 ID만 믿어요. 앱이 보낸 이메일·ID는 믿지 않아요.
  - 카카오: access token → `GET https://kapi.kakao.com/v2/user/me` → `id`
  - 구글: ID token → 구글 공개키로 서명 · `aud`(우리 클라이언트 ID) · 만료 검증 → `sub`
  - 애플: 유료 개발자 계정(연 $99)이 필요해 **지금은 지원하지 않음** (`/auth/social/apple` → 404 `UNSUPPORTED_PROVIDER`)
  - `provider_subject` = 그 ID. `(provider, provider_subject)`가 없으면 새 `users` + `auth_credential` 생성.
- **계정 합치지 않기 (Q-20)**: 구글 이메일이 이메일 가입 계정과 같아도 **다른 계정**이에요. 소셜 이메일은 표시용(`auth_credential.email`, 유일하지 않음).
- **토큰**: access는 JWT 15~30분 (`sub` = users.id). refresh는 랜덤 문자열, DB엔 **SHA-256 hex만** (`refresh_token.token_hash`), 30일.
  갱신할 때마다 새 refresh를 주고 옛것은 `revoked_at` — 이미 폐기된 refresh가 다시 오면 그 사용자의 refresh를 전부 폐기 (탈취 의심).
- **탈퇴 사용자**(`status='WITHDRAWN'`)는 로그인 거부. 로그인 성공 시 `auth_credential.last_login_at` 갱신.
- Spring Security: `/auth/**`만 열고 나머지는 JWT 필터. 의존성 예: `spring-boot-starter-security`, `spring-boot-starter-oauth2-resource-server`(JWT 검증), `jjwt` 또는 Nimbus(발급), 구글 ID 토큰은 Nimbus `JWKSource`로 검증.

### 앱 쪽 남은 일 (서버 붙일 때)

- `HttpAuthService` 구현 + refresh 토큰을 `flutter_secure_storage`에 저장 (`restore()`에서 읽어 `/auth/refresh`)
- 소셜 SDK로 토큰 받기: `kakao_flutter_sdk_user`, `google_sign_in` — 각 개발자 콘솔의 앱 키 · 패키지명 등록 필요
- 다른 API 요청엔 `Authorization: Bearer <accessToken>`, 401이면 한 번 refresh 후 재시도

## 서버가 꼭 검증해야 하는 것

골드·EXP·호감도는 앱에서 계산해 보내지 말고 서버가 계산해요 (조작 방지).
하루 제한(습관 3개 반영, 탐색 3회, 쓰다듬기·놀아주기 1회)은 서버 날짜 기준으로 초기화해요.
수치는 `docs/economy-v1.md`와 `frontend/lib/core/constants/economy.dart`를 같이 맞춰요.

## 프론트 연동 지점 (지금은 로컬 계산)

서버를 붙일 때 화면 코드는 손대지 않고 아래만 바꾸면 되게 나눠 뒀어요.

| 지금 (Flutter, 로컬) | 바꿀 곳 | 돌려주는 모양 |
| --- | --- | --- |
| `GameState.confirmCheckin(answers)` · `resubmitCheckin(answers)` | `POST /checkins` 호출 (첫 확정 / 다시 제출) → 응답을 `DailyCheckinResult`로 | `lib/data/results.dart` |
| `GameState.explore()` | `POST /explore` 호출 → `EncounterResult` | 〃 |
| `GameState.throwBall(species)` | `POST /explore/throw` 호출 → `CatchResult` | 〃 |
| `GameState.pet / play / feed / buy(item, count:) / toggleGoal / openCategory …` | 각 API 호출 후 응답으로 상태 갱신 | |

- 서버 호출로 바꾸면 이 메서드들은 `Future`가 돼요. 호출하는 곳은 `ChatController`(`lib/features/chat/`)와 각 화면의 버튼 콜백뿐이에요.
- 탐색의 랜덤은 지금 `GameState(random: …)`로 주입해요 (테스트용). 서버에선 서버가 뽑아요.

## AI 챗봇 연결

챗봇은 "무슨 말을 할지"(`ChatBrain`)와 "대화 흐름"(`ChatController`)을 나눠 뒀어요.

- `lib/features/chat/chat_brain.dart`의 `ChatBrain` 인터페이스를 구현한 `AiChatBrain`을 만들고 (DB `ai.chat_message`는 사용자 입력을 위젯 값만 허용 — A-1)
  `ChatScreen(controllerBuilder: (s) => ChatController(state: s, brain: AiChatBrain(...)))`로 넘기면 돼요.
- 모든 대사 메서드가 `Future<String>`이라 LLM 호출을 그대로 넣을 수 있고, 기다리는 동안 화면에 "…" 말풍선이 뜨고 입력이 잠겨요.
- 보상 계산은 계속 `GameState`(나중엔 서버)가 해요. AI는 말만 하고 숫자는 정하지 않게 두는 게 안전해요.
- 자유 입력("30분 뛰었어")을 받으려면 `ChatController`에 문장 → 값 해석 단계를 추가하면 돼요 (지금은 버튼/숫자 입력).

## DB v1.5

공식 스키마 v1.5 · v1.6에서 바뀐 것, 서버 · 앱에 반영한 것, 검증 결과: [`db/README.md`](db/README.md)
(위 API 초안의 탐색 3줄은 2026-10-10에 정한 규칙이고, DB v1.6에 반영돼 있어요.)
