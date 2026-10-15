# backend

서버는 **Spring Boot**로 만들어요 (DB: PostgreSQL, 스키마는 공유 폴더의 `schema.sql` v1.6 — 메모는 `backend/db/README.md`).

## API 초안

| 메서드 | 경로 | 설명 |
| --- | --- | --- |
| POST | /auth/… | 회원가입 · 로그인 · 소셜 로그인 · 토큰 갱신 · 로그아웃 (아래 "인증 API"). 경로는 모두 `/api/v1` 뒤 |
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

계약 기준은 「습관몬스터 API 명세 v5」 "1. 회원 · 설정"(저장소 밖 `D:/teamProject/docs/api/`) + `docs/진행현황-및-계획.md`의 구현 결정. 경로는 모두 **`/api/v1`** 뒤예요.
앱은 `frontend/lib/core/auth/auth_service.dart`의 `AuthService` 인터페이스만 써요 (`HttpAuthService` = 진짜 서버, `FakeAuthService` = 앱 안에서만).

### 흐름

1. 앱 시작 → 저장된 refresh 토큰이 있으면 `POST /auth/refresh` → `GET /me` (자동 로그인), 없으면 로그인 화면
2. 로그인 성공 → 토큰 저장 → `GET /me`로 계정 정보 → `onboarded`가 false면 온보딩, true면 홈
3. 온보딩 끝 → `PATCH /me/onboarding` (3단계에서 `POST /onboarding` 일괄 제출로 바뀜)
4. 설정 → 로그아웃 → `POST /auth/logout` (+ 푸시를 붙이면 `DELETE /me/device-token`) → 로그인 화면
5. 다른 요청이 401 `TOKEN_EXPIRED`면 재발급을 **한 번만** 하고 다시 보냄. `INVALID_TOKEN`이면 로그인 화면

### 엔드포인트

| 메서드 | 경로 | 요청 | 응답 · 설명 |
| --- | --- | --- | --- |
| POST | /auth/signup | `{email, password}` | 201 `{accessToken, refreshToken, onboarded}` |
| POST | /auth/login | `{email, password}` | 200 같은 모양 |
| POST | /auth/social/{kakao\|google} | `{providerToken}` | 200 `{accessToken, refreshToken, isNewUser, onboarded}`. 처음이면 자동 가입 |
| POST | /auth/refresh | `{refreshToken}` | 200 `{accessToken, refreshToken}` — refresh도 교체(rotation) |
| POST | /auth/logout | `{refreshToken}` | 204. 그 refresh 폐기 |
| GET | /me | (Bearer) | `{userId, email, provider, onboarded}` — 명세에 없어서 더함 (결정 D4) |
| DELETE | /me | (Bearer) | 204 탈퇴 |
| PUT | /me/device-token | `{fcmToken, platform}` | 204. 같은 토큰이 다른 계정에 있으면 이 계정으로 옮김 |
| DELETE | /me/device-token | `{fcmToken}` | 204. 로그아웃 때 해제 — 명세에 없어서 더함 (결정 A5) |
| PATCH | /me/onboarding | (본문 없음) | 임시. 3단계에서 지움 |

오류 응답은 `{ "code": "...", "message": "화면에 보여줄 문구" }` (+ 경우에 따라 `errors`, `provider`).

| code | HTTP | 언제 |
| --- | --- | --- |
| INVALID_EMAIL · WEAK_PASSWORD | 400 | 이메일 형식 · 비밀번호 8자 미만 |
| INVALID_CREDENTIALS | 401 | 이메일/비밀번호 불일치 (어느 쪽이 틀렸는지 알려주지 않음) |
| INVALID_PROVIDER_TOKEN | 401 | 카카오 · 구글 토큰 검증 실패 |
| INVALID_TOKEN / TOKEN_EXPIRED | 401 | 토큰 없음 · 위조 · 폐기 / access 만료 |
| EMAIL_TAKEN | 409 | 같은 방법(이메일)으로 이미 가입된 이메일 |
| EMAIL_REGISTERED_WITH_OTHER_METHOD | 409 | 다른 방법으로 가입된 이메일. `provider`(kakao · google · email)로 원래 방법을 알려 줌 |

### 서버가 지키는 것 (DB v1.7 `identity` 스키마)

- **이메일 하나에 계정 하나**: `users.email`(소문자, 유일). 이메일 가입과 소셜 가입이 같은 이메일이어도 **자동으로 합치지 않고** 409로 원래 가입 방법을 알려 준다.
  이메일 가입은 인증 메일이 없어서, 자동으로 합치면 남의 이메일로 먼저 가입해 두는 방식으로 계정을 빼앗을 수 있기 때문.
- **소셜 이메일은 제공자가 검증한 것만** 계정 이메일로 쓴다 (구글 `email_verified`, 카카오 `is_email_valid` · `is_email_verified` — 결정 C4). 검증 안 됐으면 이메일 없이 가입.
- **소셜 토큰은 서버가 직접 검증**하고 그 결과의 사용자 ID만 믿는다. 앱이 보낸 이메일 · ID는 믿지 않는다.
  - 카카오: access token → `/v1/user/access_token_info`(우리 앱 ID인지) → `/v2/user/me`
  - 구글: ID token → 구글 공개키로 서명 · `aud`(우리 클라이언트 ID) · 만료 검증 → `sub`
  - 애플: 유료 개발자 계정(연 $99)이 필요해 지원하지 않음 (`/auth/social/apple` → 404)
- **비밀번호**는 BCrypt(`auth_credential.password_hash`), 원문 저장 · 로그 금지.
- **토큰**: access는 JWT 30분 (`sub` = users.id). refresh는 랜덤 문자열, DB엔 SHA-256 hex만, 30일.
  쓸 때마다 새것으로 바꾸고, 이미 폐기된 refresh가 다시 오면 그 사용자의 refresh를 전부 폐기 (탈취 의심).
- **탈퇴**: `users`는 지우지 않고 `WITHDRAWN` + 이메일 비우기(같은 이메일로 재가입 가능). 로그인 수단 · refresh · 푸시 토큰 삭제,
  다른 모듈 데이터는 각 모듈의 `WithdrawalStep`이 정리 (지금은 중복 방지 키 기록). 남아 있는 access 토큰은 `UserGateFilter`가 막는다.

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
