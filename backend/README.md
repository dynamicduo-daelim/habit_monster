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

## 게임 API — 3-1 ~ 3-3단계 (10-18 ~ 10-19)

모두 Bearer 필요, 온보딩 전엔 `/categories` · `/measure-types` · `/onboarding`만 (그 밖은 403 `ONBOARDING_REQUIRED`). 응답 모양은 API 명세 v5 그대로이고, 다른 점만 적는다.

| 메서드 | 경로 | 응답 · 설명 |
| --- | --- | --- |
| GET | /categories | 6개, `opened`(내가 열었는지) + `starter{speciesId, name, imageKey}` — 이미지 URL 대신 `imageKey`(D1) |
| GET | /measure-types?categories=ex,st | 카테고리 순서로 `{categoryCode, measureTypes[], presets[]}`. 생략하면 전체, 모르는 코드면 400. RANGE(수면)만 `rangeBelow` · `rangeAbove` (D-28) |
| POST | /onboarding | **Idempotency-Key 필수**(A3). 201 `{starters[{userMonsterId, speciesId, categoryCode, name, imageKey, location}], partnerMonsterId, habitIds, goalIds}`. 선택 필드 `partnerCategory`(D-36). 틀리면 400 + `errors` 전부, 이미 끝냈으면 409 `ALREADY_ONBOARDED`. 시작 골드 · 볼 0 (D-35) |
| POST | /me/attendance | `{date, alreadyAttended, currentStreak, longestStreak}`. 하루 여러 번 불러도 1행 |
| GET | /me/status | `{businessDate, dayCount, currentStreak, gold, ballCount, checkedInToday, exploreRemaining, exploreTotal, endedHabitCount}` — `dayCount`는 더한 값 (D-37) |
| GET | /me/today | `{businessDate, checkedIn, goldEarned, overallRate, habits[]}`. 체크인 전이면 보상 필드 null, 습관은 오늘 체크인 대상 |
| GET | /monsters?location=FIELD\|BAG | 생략하면 전체. `imageKey` · `stage` · `isPartner` |
| GET | /monsters/{id} | `expToNextLevel` 대신 `expRequired`(B2), `todayActions{pet, play}`. 남의 몬스터 · 없는 몬스터는 404 (C3) |
| GET | /shop/items | `{gold, items[]}` |
| GET | /inventory | `{items[{itemCode, name, quantity}]}` — 0개는 뺌 (D-39) |
| POST | /shop/purchases | **Idempotency-Key 필수**. 201 `{purchaseId, totalPrice, gold, itemCode, quantity}` (`quantity` = 산 뒤 가방 개수). 가격은 서버의 상점 가격. 400 수량 1 ~ 99 밖 · 없는 아이템, 422 `NOT_ENOUGH_GOLD` (아무것도 안 남음) |
| POST | /monsters/{id}/feed | **Idempotency-Key 필수**. 200 `{expGained, levelBefore, levelAfter, stageBefore, stageAfter, evolved, remainingQuantity}`. 400 물약이 아닌 코드, 404 남의 몬스터, 422 `MAX_LEVEL` · `NO_ITEM` |
| POST | /monsters/{id}/affection | `{action: PET \| PLAY}` → 200 `{gain, affection, affectionTier}` (최대면 gain 0). 하루 1번씩 — 409 `ALREADY_DONE_TODAY`. 키 없음(명세). DRAG는 400 (D-46) |
| GET | /monsters/{id}/line | `{affectionTier, line}` — 호감도 단계 대사 중 하나 |
| PATCH | /monsters/{id}/location | `{location: FIELD \| BAG}` → `{userMonsterId, location, fieldCount}`. 422 `FIELD_LIMIT` (필드 1마리 넣기 · 5마리 꺼내기) |
| PUT | /me/partner | `{userMonsterId}` → `{partnerMonsterId}`. 가방에 있어도 됨 |
| GET | /habits?status=ACTIVE,ENDED | 생략하면 ACTIVE · ENDED. 기간 값은 마지막 기간 기준 |
| POST | /habits | **Idempotency-Key 필수**. `{categoryCode, measureTypeId, name, dailyTarget, periodCode}` → 201 (`GET /habits`의 한 줄). 시작일 = 오늘 체크인 전이면 오늘, 후면 내일. 400 값 형식, 422 `CATEGORY_LOCKED` · `HABIT_LIMIT`(진행 중 + 기간 완료 5개) (10-23, D-47) |
| POST | /habits/{id}/renew | **Idempotency-Key 필수**. `{periodCode, dailyTarget?}` → 200 (새 기간, `filledDays` 0). 404 남의 습관, 400, 409 `HABIT_NOT_ENDED` (10-23) |
| POST | /habits/{id}/stop | 키 없음. 200 `{habitId, status: STOPPED}`. 404, 409 `HABIT_ALREADY_STOPPED`, 422 `LAST_HABIT`(마지막 1개) (10-23) |
| GET | /goals | `{weekly, monthly}` 각각 `{slotsTotal, slotsUsed, rewardGold, goals[{goalId, goalType, periodStart, periodEnd, title, detail, status}]}` — 기간이 남은 목표만 (등록한 날부터 7 · 30일, 명세 v5 보충 10-28, D-48) |
| POST | /goals | **Idempotency-Key 필수**. `{goalType, title, detail?}` → 201 (목록의 한 줄). 400 값 형식, 422 `GOAL_SLOT_FULL` (기간이 남은 목표 = 진행 중 + 완료) (10-28) |
| PATCH | /goals/{id} | 보낸 필드만. `detail: null` = 지우기, `title: null` · `goalType` = 400. 404 · 409 `GOAL_COMPLETED` · `GOAL_PERIOD_ENDED` (10-28) |
| DELETE | /goals/{id} | 204. 404 · 409 `GOAL_COMPLETED` · `GOAL_PERIOD_ENDED` (10-28) |
| GET | /dex | `{slot{dexCount, nextMilestone, availableTickets}, categories[{code, name, opened, ownedCount, seenCount, totalCount}]}` (10-28, 4-3) |
| GET | /dex/categories/{code} | `{code, ownedCount, seenCount, totalCount, monsters[]}` — OWNED `{dexNo, status, speciesId, name, imageKey, level}` · SEEN(레벨 없음) · UNKNOWN `{dexNo, status, imageKey, unlockLevel, unlocked}`(이름 · 번호 없음, D6). 없는 코드 404 |
| GET | /dex/species/{id} | `{dexNo, status, name, imageKey, element, rarity, level, stage, description}` (본 종은 level · stage null). 본 적 없으면 404 `NOT_DISCOVERED` |
| GET | /stats | `{attendance{currentStreak, longestStreak, last14Days[{date, attended}]}, sincerity{last7Days[{date, dayOfWeek, rate}], averageRate}, categories[]}` — `rate`는 그날 최신 점수의 달성률 %(안 한 날 null), 연 카테고리 `{code, name, opened, level, maxLevel, expInLevel, expRequired, levelUpGold}`(B2, 최대 레벨이면 `expRequired` null) · 잠긴 카테고리 `{code, name, opened}` (10-28, D-50) |
| POST | /categories/{code}/unlock | **Idempotency-Key 필수**. 201 `{categoryCode, starter{userMonsterId, name, imageKey, location}, availableTickets}`. 404 없는 코드, 409 `ALREADY_OPENED`, 422 `NO_TICKET` (D-49) |
| POST | /goals/{id}/complete | **Idempotency-Key 필수**. 200 `{goalId, status, goldAwarded, gold}` (원장 `GOAL_WEEKLY` · `GOAL_MONTHLY`). 404 · 409 `GOAL_COMPLETED` · `GOAL_PERIOD_ENDED` · `GOAL_TOO_EARLY`(등록한 날) (10-28) |
| GET | /checkins/today | `{businessDate, submitted, revision, partner{userMonsterId, name, imageKey, affectionTier}, tabs[{categoryCode, categoryName, habits[{habitId, name, unit, scoringMode, options, previousValue, filledDays, periodDays}]}]}`. 제출 전엔 오늘 대상 습관, 제출 후엔 제출에 들어간 습관(`previousValue` = 최신 값). `options`는 서버가 만든 선택지 (B3, 수면은 범위 ± 2칸 — D-42) |
| POST | /checkins/today | **Idempotency-Key 필수**. 201, 명세 예시 그대로 + `categoryExp[]`의 `expInLevel` · `expRequired`(더한 값, D-43). 409 `BUSINESS_DATE_CHANGED` · `ALREADY_SUBMITTED` · `NO_ACTIVE_HABIT`, 400 빠진 · 남의 습관 · 선택지 밖 값 (`errors` 전부) |
| POST | /checkins/today/interpret | **(제안 · 10-30)** 대화 해석 — `{businessDate, message(1~300자), history[{role BOT·USER, text}] ≤10, draft[{habitId, done, value}], askingHabitId}` → `{reply, answers[{habitId, done, value, evidence SHORT·DETAILED, confidence}], askAgain{habitId, question}, remainingHabitIds, safety, source LLM·TEMPLATE}`. **확정하지 않는다** (키 없음). 서버가 Gemini(`ai/GeminiClient`, 키 `GEMINI_API_KEY`)를 부르고 답을 다시 검사(오늘 습관 · 상한 · 선택지 맞추기 · 확신 0.6). 실패 · 3초 초과면 TEMPLATE. 400 빈 · 긴 말, 409 날짜 · `NO_ACTIVE_HABIT`, 429 `AI_RATE_LIMITED`(하루 60). 프롬프트: `docs/AI-프롬프트.md` |
| POST | /timers | **(v6 9장, 11-05)** **Idempotency-Key 필수**. `{businessDate, habitId}` → 201 `{timerId, habitId, status RUNNING, startedAt, elapsedSeconds, todayMinutes, endReason}`. 분 단위 시간 습관(진행 중)만 — 아니면 422 `NOT_TIMER_HABIT`. 같은 습관에 끝나지 않은 타이머 · 다른 습관 타이머가 도는 중이면 409 `TIMER_ALREADY_RUNNING` + `timerId`. 404 남의 · 없는 습관, 409 날짜 |
| PATCH | /timers/{timerId} | **Idempotency-Key 필수**. `{action PAUSE · RESUME · STOP, focusMinutes?}` → 200 (위와 같은 모양). STOP의 기록 분 = min(서버 경과(일시정지 뺌, 최대 240), `focusMinutes`). 기록되는 날 = 끝난 날 (00시에 끊지 않음). 끝난 타이머 409 `TIMER_NOT_RUNNING` + `endReason`, 400 모르는 action · 음수 · STOP 아닌데 `focusMinutes` |
| GET | /timers/today | `{active[TimerView], habits[{habitId, todayMinutes, sessions}]}` — 끝나지 않은 타이머 전부 + 오늘 기록된 합. 240분에 닿은 타이머는 이때(다음 요청 때) 그 시각으로 끝낸다 (`MAX_DURATION`) |
| PUT | /checkins/today | **Idempotency-Key 필수**. 200 `{revision, habits[{habitId, value, score}], overallRate}` — 최신 값 · 점수만 바뀌고 보상은 그대로. 오늘 제출이 없으면 404 `CHECKIN_NOT_FOUND` |
| POST | /explores | **Idempotency-Key 필수**. 201 `{exploreId, result(MISS · DUPLICATE · ENCOUNTER), species{speciesId, name, imageKey, categoryCode, rarity, captureRate}, newlySeen, goldAwarded, gold, skippedExploreId, exploreRemaining}` (명세 그대로, `imageUrl` 대신 `imageKey`). 409 `BUSINESS_DATE_CHANGED` · `CHECKIN_REQUIRED`, 422 `NO_EXPLORE_LEFT` (D-45) |
| GET | /explores/pending | 오늘 처리하지 않은 등장 200 (위와 같은 모양, `newlySeen` false) 또는 204 |
| POST | /explores/{exploreId}/capture | **Idempotency-Key 필수**. 200 `{outcome(CAPTURED · ESCAPED), monster{userMonsterId, name, imageKey, location}, ballCount, dex{dexCount, newSlotAvailable}}`. 남의 탐색 **404**(C3, 명세는 403), 409 `ENCOUNTER_CLOSED` · `BUSINESS_DATE_CHANGED`, 422 `NO_BALL` |

`PATCH /me/onboarding`(예전 임시 API)은 지웠다 — `POST /onboarding`이 완료 시각까지 찍는다.

## 서버가 꼭 검증해야 하는 것

골드·EXP·호감도는 앱에서 계산해 보내지 말고 서버가 계산해요 (조작 방지).
하루 제한(습관 3개 반영, 탐색 3회, 쓰다듬기·놀아주기 1회)은 서버 날짜 기준으로 초기화해요.
수치는 `docs/economy-v1.md`와 `frontend/lib/core/constants/economy.dart`를 같이 맞춰요.

## 프론트 연동 지점 (2단계, 10-15)

화면은 게임 상태를 **바꿀 때** `GameRepository`(`frontend/lib/core/state/game_repository.dart`)만 부른다. 읽기는 지금처럼 `GameState`.

```
화면 ──▶ runGameAction(context, (repo) => repo.buy(item))      ← 실패하면 토스트
            └▶ GameRepository
                 ├ LocalGameRepository ──▶ GameState 규칙      (지금 · 서버 없이)
                 └ HttpGameRepository  ──▶ ApiClient ──▶ 서버   (3단계부터 API마다)
```

| `GameRepository` 메서드 | 서버 API (명세 v5) | 돌려주는 모양 |
| --- | --- | --- |
| `load` | `GET /me/status` · `/me/today` · `/categories` · `/monsters`(+ 마리마다 `/monsters/{id}`) · `/inventory` · `/habits` · `/goals` · `/checkins/today`(10-19) | — (GameState를 채움) — **10-18 연결** |
| `attend` | `POST /me/attendance` | 처음 출석이면 true — **10-18 연결** |
| `completeOnboarding` | `POST /onboarding` (측정 항목은 `GET /measure-types`로 id 변환) | — **10-18 연결** |
| `confirmCheckin` · `resubmitCheckin` | `POST` · `PUT /checkins/today` | `DailyCheckinResult` (`lib/data/results.dart`) — **10-19 연결** |
| `interpret` | `POST /checkins/today/interpret` | `InterpretResult` — **10-30 연결** (시연 모드는 null → 앱이 숫자만 읽음) |
| `explore` · `throwBall` · `pendingEncounter` | `POST /explores` · `/explores/{id}/capture` · `GET /explores/pending` | `EncounterResult` · `CatchResult` — **10-20 연결** |
| `buy` | `POST /shop/purchases` (코드는 `Catalog.serverCodeOf`) | 성공 여부 — **10-21 연결** |
| `pet` · `play` · `feed` · `moveMonster` · `setPartner` · `talk` | `/monsters/{id}/affection` · `feed` · `location` · `PUT /me/partner` · `GET /monsters/{id}/line` | — **10-21 연결**. `dragMonster`는 서버 모드에서 0 (D-46) |
| `loadStats` | `GET /stats` | `StatsData` — **10-28 연결** (통계 탭을 열 때마다) |
| `openCategory` · (`load`의 도감) | `POST /categories/{code}/unlock` · `GET /dex` · `/dex/categories/{code}` | 성공 여부 — **10-28 연결** |
| `addHabit` · `removeHabit` | `POST /habits` · `/habits/{id}/stop` | |
| `addGoal` · `updateGoal` · `deleteGoal` · `completeGoal` | `POST /goals` · `PATCH` · `DELETE /goals/{id}` · `POST /goals/{id}/complete` | — **10-28 연결** |

- `ApiClient`(`lib/core/api/`)가 공통 규칙을 맡는다: Bearer 토큰, `Idempotency-Key`(다시 보낼 땐 같은 키), `TOKEN_EXPIRED`면 재발급 1번(로그인과 공유),
  연결 끊김 · `REQUEST_IN_PROGRESS`면 같은 키로 재시도, `BUSINESS_DATE_CHANGED`면 화면 새로 불러오기 알림.
- 탐색의 랜덤은 로컬 모드에서만 `GameState(random: …)`로 주입한다 (테스트용). 서버 모드에선 서버가 뽑는다.

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
