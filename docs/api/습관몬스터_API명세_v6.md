# 습관 몬스터 API 명세

Nov 4, 2026 · @윤서 · v6 (v6 개정분은 Claude가 작성, 윤서 요청 11-02 · 결정 D-62)

API 목록 문서의 요청을 HTTP 메서드, 경로, 요청·응답 필드로 풀어 쓴 명세입니다. 필드 이름과 값은 schema.sql v1.9 기준이며, 이번 변경으로 DB·시드에 반영해야 할 것은 맨 끝에 모았습니다. 검토 후 보류한 항목은 별도 문서 「API 명세 보류 항목」에 정리했습니다.

## 변경 요약 (v1 → v6)

**v6 (Nov 4, 2026) — AI 챗봇 체크인 · 습관 타이머** (결정 D-57 · D-62 · D-63, 근거: `docs/제안/2026-10-30-AI챗봇-API.md` 3차 검토본)
- **대화 해석** `POST /checkins/today/interpret` 추가: 사용자의 말을 AI가 해석해 기록 후보만 돌려주고, 확정은 기존 체크인 제출로. 대화는 저장하지 않음. 하루 호출 한도 (5장)
- **근거(`evidence`)**: 체크인 답에 `SHORT` · `DETAILED`(자기보고), 서버가 타이머 기록을 보고 `VERIFIED`를 붙임
- **점수 상한**: 자기보고는 최대 **20점**(`self_report_max_score`), 확인됨만 25점까지. 상한이 실제로 깎는 것은 시간 · 양 방식뿐 (4-1)
- **카테고리 경험치 계수**: 경험치 = 점수 × 방식 계수(시간 · 양 1.0 / 범위 0.9 / O·X 0.8) × 확인됨이면 1.2, 습관마다 반올림. 골드는 그대로 1점 = 1G (4-1)
- **습관 타이머 API 3개** (9장): 분 단위 시간 습관, 습관마다 하나 · 도는 것은 사람당 하나, 기록은 **끝난 날**(00시에 끊지 않음), 최대 240분(일시정지 뺀 경과), 끝낼 때 앱이 집중 분을 보내면 서버 경과와 작은 값
- 체크인 준비 조회에 `timerMinutes`, 제출 응답 습관마다 `evidence` · `scoreCapped` · `expGained`
- 습관 그만두기 · 기간 끝이면 그 습관 타이머도 끝남 (4장)
- 에러 코드 4개 (`AI_RATE_LIMITED` 429 · `NOT_TIMER_HABIT` · `TIMER_ALREADY_RUNNING` · `TIMER_NOT_RUNNING`), 에러 응답 선택 칸 `timerId` · `endReason`
- 헬스(Health Connect) 운동 시간 올리기는 다음 판 (제안서 5장 `POST /health-records`)


**규칙**
- 업무 날짜 경계를 새벽 4시에서 **00시**로 변경. 주는 월요일 00시, 월은 1일 00시 시작 (목표 기간은 v5 보충 10-28에서 등록한 날부터로 바뀜)
- 습관 점수는 HTML 공식 **0\~25**(1점 = 1G), 전체 성실도는 **목표 달성률 %**
- 골드·카테고리 경험치·기간 보너스 모두 **점수 상위 3개 습관**만 반영
- 기간 보너스는 **골드**로 지급. 기간은 **했다고 제출한 날 수** 기준(연속일 필요 없음)
- 카테고리 최대 레벨 7 → **20**, 종 해금 레벨 분산
- 탐색: 가진 종이 등장하면 볼 없이 골드 지급, 안 가진 종 등장 가중치 상향. 포획률은 **희귀도별**. 꽝 확률 **0.35**
- 첫 제출이 전부 "못했어"인 날은 탐색 1회
- 이메일 하나에 계정 하나. 다른 가입 방법으로 가입된 이메일은 자동 병합하지 않고 안내
- Apple 로그인 제외

**API**
- 습관 API 4개(목록·추가·연장·그만두기), 남은 등장 조회 1개 추가 → 44개
- 쓰기 요청에 `businessDate`를 넣어 날짜가 바뀐 뒤 들어온 요청을 거절
- 중복 요청 방지 키 규칙과 요청 검사 순서 명시, 목표 완료·카테고리 열기에 키 추가
- 에러 응답에 선택 필드 `errors`, 에러 코드 전체 목록 추가
- PATCH 규칙: 필드를 안 보내면 변경 없음, `null`이면 삭제

**v4 수정**
- 요청 검사 순서에 온보딩 여부 검사(②) 추가
- 달성률은 반올림한 점수로 계산함을 명시
- 통계 예시의 카테고리 경험치를 체크인 예시와 맞춤
- `explore_miss_rate` 0.35로 확정(베타에서 튜닝)

**v5 수정 — 도감 "본 종"**
- 안 가진 종이 등장(`ENCOUNTER`)하면 잡지 못해도 도감에 **본 종(`SEEN`)**으로 등록. 볼 부족·그만·다시 탐색·포획 실패 모두 같은 규칙
- 도감 종 상태를 `OWNED`(가짐) / `SEEN`(봄) / `UNKNOWN`(못 봄) 3단계로 변경. 본 종은 이미지를 그대로, 못 본 종은 실루엣으로 표시
- 카테고리 열기 진행바(`dexCount`)는 계속 **가진 종**만 셈
- 본 종은 탐색에서 여전히 "안 가진 종"으로 취급(`ENCOUNTER`, 가중치 배수 적용)

**v5 보충 (Oct 23, 2026) — 습관 하한**
- 습관은 `ACTIVE` + `ENDED`를 합쳐 **1개 이상** 남김. 마지막 1개를 그만두면 422 `LAST_HABIT` (4-2 · 그만두기 · 에러 코드 목록)

**v5 보충 (Oct 28, 2026) — 목표 기간**
- 목표 기간은 달력 주 · 달이 아니라 **등록한 날부터** 주간 7일 · 월간 30일 (설정 `weekly_goal_days` · `monthly_goal_days`). 일요일에 세운 주간 목표도 완료할 수 있게
- 칸은 **기간이 남은 목표**(진행 중 · 완료)가 차지. 기간이 끝나거나 삭제하면 빔 (완료 즉시 비우면 "등록 → 다음 날 완료" 반복으로 골드를 계속 벌 수 있음)
- 등록한 날에는 완료할 수 없음: 409 `GOAL_TOO_EARLY` (8장 · 에러 코드 목록)
- `GET /goals`의 기간은 목표마다 `periodStart` · `periodEnd` (8장)

## 공통 규칙

- **기본 경로**: `/api/v1`. 아래 경로는 모두 이 뒤에 붙습니다.
- **인증**: `/auth/*`를 뺀 모든 요청은 헤더 `Authorization: Bearer {accessToken}`이 필요합니다.
  - 토큰이 없거나 형식이 틀리거나 폐기되었으면 401 `INVALID_TOKEN`, 만료되었으면 401 `TOKEN_EXPIRED`. 앱은 `TOKEN_EXPIRED`일 때만 재발급을 시도합니다.
  - **재발급은 앱 전체에서 한 번에 하나만** 진행합니다. 요청 여러 개가 동시에 `TOKEN_EXPIRED`를 받으면, 첫 요청만 `/auth/refresh`를 부르고 나머지는 그 결과를 기다렸다가 새 토큰으로 다시 보냅니다. 리프레시 토큰은 매번 교체되므로, 동시에 재발급하면 두 번째 요청이 폐기된 토큰을 쓰게 되어 로그아웃됩니다.
  - 온보딩을 마치지 않은 사용자가 온보딩 관련 요청(`/categories`, `/measure-types`, `/onboarding`) 외의 요청을 하면 403 `ONBOARDING_REQUIRED`.
- **날짜**: 업무 날짜는 `"2026-10-12"` 형식이며 **00시(Asia/Seoul) 경계**로 서버가 계산합니다. 시각은 `"2026-10-12T14:35:00+09:00"` 형식입니다.
- **업무 날짜 검사**: 체크인 제출·수정, 대화 해석, 탐색, 포획, 타이머 시작 요청은 본문에 `businessDate`(앱이 화면을 연 날짜)를 담습니다. 서버의 오늘 날짜와 다르면 409 `BUSINESS_DATE_CHANGED`를 돌려주고, 앱은 화면을 새로 불러옵니다.
- **중복 요청 방지 키**: 헤더 `Idempotency-Key: {UUID}`. 클라이언트가 버튼을 누를 때 새로 만들고, 재전송할 때는 같은 값을 보냅니다.
  - 필요한 요청: 아이템 구매, 간식 주기, 체크인 제출·수정, 탐색, 포획, 목표 완료, 카테고리 열기, 타이머 시작 · 일시정지 · 이어서 · 끝내기 (v6). 대화 해석은 아무것도 바꾸지 않아 필요 없습니다.
  - 키는 **사용자 + 메서드 + 경로** 단위로 구분하며 24시간 보관합니다.
  - 같은 키, 같은 본문이면 처음 결과(상태 코드 포함)를 그대로 돌려줍니다.
  - 같은 키, 다른 본문이면 422 `IDEMPOTENCY_KEY_REUSED`.
  - 같은 키의 첫 요청이 아직 처리 중이면 409 `REQUEST_IN_PROGRESS`. 앱은 잠시 뒤 같은 키로 다시 보냅니다.
- **요청 검사 순서**: ① 인증 → ② 온보딩 여부 → ③ 중복 요청 방지 키 조회(저장된 결과가 있으면 여기서 반환) → ④ 소유권 → ⑤ 업무 날짜 → ⑥ 값 형식 → ⑦ 비즈니스 규칙. 예를 들어 23:59에 보낸 요청이 타임아웃되어 00:01에 같은 키로 재전송되면, ③에서 처음 결과가 나가고 날짜 검사까지 가지 않습니다.
- **동시 차감**: 골드·볼·물약 차감은 조건부 갱신(`... WHERE gold >= ?`)이나 행 잠금으로 처리합니다. 키가 다른 요청 두 건이 동시에 들어와도 잔액이 음수가 되지 않으며, 부족하면 422를 돌려줍니다.
- **점수**
  - 습관 점수(`score`)는 0\~25 정수(반올림)이며 **1점 = 1G**입니다. 자기보고는 최대 20점, 타이머로 확인된 기록만 25점까지입니다 (v6). 공식은 아래 "4-1. 점수 공식"을 봅니다.
  - 성실도(`...Rate`)는 0\~100 정수(%)입니다.
- **필드 이름**: JSON은 camelCase, 코드값은 DB 값을 그대로 씁니다 (예: `"WEEKLY"`, `"FIELD"`, `"D30"`).
- **PATCH 규칙**: 보내지 않은 필드는 바꾸지 않고, `null`을 보낸 필드는 지웁니다. 지울 수 없는 필드(필수 값)에 `null`을 보내면 400.
- **성공 응답**: 본문을 그대로 돌려줍니다. 돌려줄 것이 없으면 `204 No Content`.
- **에러 응답**: 아래 형식으로 통일합니다. 코드 전체 목록은 문서 끝의 "에러 코드 목록"을 봅니다.

```json
{ "code": "INVALID_REQUEST", "message": "입력값을 확인해 주세요.",
  "errors": [ { "field": "habits[0].dailyTarget", "reason": "0보다 커야 합니다." } ] }
```

`errors`는 선택 필드이며, 여러 필드가 동시에 틀릴 수 있는 400 응답(온보딩 일괄 제출 등)에서 씁니다.
타이머 오류(9장)에는 선택 필드 `timerId` · `endReason`이 붙습니다 (값이 있을 때만, v6).

| 상태 코드 | 쓰는 경우 |
| --- | --- |
| 400 | 값 형식·범위가 틀림 (빈 이름, 목표값 0 등) |
| 401 | 토큰 없음·만료, 로그인 실패 |
| 403 | 본인 데이터가 아님, 온보딩 전 |
| 404 | 대상 없음 |
| 409 | 현재 상태에서 할 수 없음 (이미 완료한 목표, 오늘 이미 제출, 날짜 바뀜 등) |
| 422 | 규칙 위반 (골드 부족, 슬롯 초과, 탐색 기회 없음 등) |
| 429 | 하루 AI 호출 한도 초과 (v6) |

## 한눈에 보기 (48개)

| 영역 | 메서드 | 경로 | 요청 이름 |
| --- | --- | --- | --- |
| 회원 | POST | /auth/signup | 이메일 회원가입 |
| 회원 | POST | /auth/login | 이메일 로그인 |
| 회원 | POST | /auth/social/{provider} | 소셜 로그인 |
| 회원 | POST | /auth/refresh | 토큰 재발급 |
| 회원 | POST | /auth/logout | 로그아웃 |
| 회원 | PUT | /me/device-token | 푸시 토큰 등록 |
| 회원 | POST | /me/attendance | 출석체크 (앱 접속 시 자동) |
| 회원 | DELETE | /me | 회원 탈퇴 |
| 온보딩 | GET | /categories | 카테고리 목록 조회 |
| 온보딩 | GET | /measure-types | 측정 단위·추천 습관 조회 |
| 온보딩 | POST | /onboarding | 온보딩 완료 (일괄 제출) |
| 메인 | GET | /me/status | 상단 바 조회 |
| 메인 | GET | /me/today | 오늘 요약 조회 (스크롤탭) |
| 메인 | GET | /monsters | 내 몬스터 목록 (필드·가방) |
| 메인 | GET | /monsters/{id} | 몬스터 상세 (팝업) |
| 메인 | POST | /monsters/{id}/affection | 쓰다듬기·놀아주기 |
| 메인 | POST | /monsters/{id}/feed | 간식 주기 |
| 메인 | GET | /monsters/{id}/line | 말걸기 |
| 메인 | PATCH | /monsters/{id}/location | 가방에 넣기·꺼내기 |
| 메인 | PUT | /me/partner | 대화 상대 변경 |
| 메인 | GET | /shop/items | 상점 목록 |
| 메인 | POST | /shop/purchases | 아이템 구매 (볼 사기 포함) |
| 메인 | GET | /inventory | 가방 아이템 조회 |
| 습관 | GET | /habits | 습관 목록 **(신규)** |
| 습관 | POST | /habits | 습관 추가 **(신규)** |
| 습관 | POST | /habits/{habitId}/renew | 기간 연장 **(신규)** |
| 습관 | POST | /habits/{habitId}/stop | 습관 그만두기 **(신규)** |
| 챗봇 | GET | /checkins/today | 체크인 준비 조회 |
| 챗봇 | POST | /checkins/today | 체크인 제출 (첫 제출) |
| 챗봇 | PUT | /checkins/today | 체크인 수정 (다시 체크) |
| 챗봇 | POST | /checkins/today/dialogue | 체크인 대사 요청 |
| 챗봇 | POST | /checkins/today/interpret | 대화 해석 **(v6)** |
| 챗봇 | POST | /explores | 탐색하기·다시 탐색 |
| 챗봇 | GET | /explores/pending | 남은 등장 조회 **(신규)** |
| 챗봇 | POST | /explores/{exploreId}/capture | 볼 던지기 |
| 통계 | GET | /stats | 통계 조회 |
| 도감 | GET | /dex | 도감 요약 |
| 도감 | GET | /dex/categories/{code} | 카테고리 몬스터 목록 |
| 도감 | GET | /dex/species/{speciesId} | 도감 몬스터 상세 |
| 도감 | POST | /categories/{code}/unlock | 카테고리 열기 |
| 목표 | GET | /goals | 목표 목록 |
| 목표 | POST | /goals | 목표 등록 |
| 목표 | PATCH | /goals/{goalId} | 목표 수정 |
| 목표 | DELETE | /goals/{goalId} | 목표 삭제 |
| 목표 | POST | /goals/{goalId}/complete | 목표 완료 |
| 타이머 | POST | /timers | 습관 타이머 시작 **(v6)** |
| 타이머 | PATCH | /timers/{timerId} | 일시정지 · 이어서 · 끝내기 **(v6)** |
| 타이머 | GET | /timers/today | 오늘 타이머 기록 · 끝나지 않은 타이머 **(v6)** |

## 1. 회원·설정

**계정 규칙**: 이메일 하나에 계정 하나입니다. 이메일 가입과 소셜 가입이 같은 이메일을 쓰더라도 자동으로 합치지 않습니다. 이메일 가입에 인증 절차가 없어서, 자동으로 합치면 남의 이메일로 먼저 가입해 두는 방식의 계정 탈취가 가능하기 때문입니다. 다른 방법으로 이미 가입된 이메일이면 409 `EMAIL_REGISTERED_WITH_OTHER_METHOD`와 함께 기존 가입 방법을 알려주고, 사용자는 그 방법으로 로그인합니다. 로그인한 상태에서 계정을 연결하는 기능은 확장 단계입니다.

```json
// 409 응답 예시
{ "code": "EMAIL_REGISTERED_WITH_OTHER_METHOD", "message": "카카오로 가입된 이메일입니다.", "provider": "kakao" }
```

### POST /auth/signup — 이메일 회원가입

```json
// 요청
{ "email": "user@example.com", "password": "********" }
// 응답 201
{ "accessToken": "eyJ...", "refreshToken": "eyJ...", "onboarded": false }
```

이메일은 소문자로 통일해 중복을 검사합니다. 이메일 가입으로 이미 있으면 409 `EMAIL_TAKEN`, 소셜로 가입된 이메일이면 409 `EMAIL_REGISTERED_WITH_OTHER_METHOD`.

### POST /auth/login — 이메일 로그인

```json
// 요청
{ "email": "user@example.com", "password": "********" }
// 응답 200
{ "accessToken": "eyJ...", "refreshToken": "eyJ...", "onboarded": true }
```

이메일이나 비밀번호가 틀리면 401 `INVALID_CREDENTIALS`. `onboarded`가 false면 앱은 화면 1로 보냅니다.

### POST /auth/social/{provider} — 소셜 로그인

`provider`: `kakao` | `google` (Apple 로그인은 이번 범위에서 제외)

```json
// 요청
{ "providerToken": "제공자가 준 인증 토큰" }
// 응답 200
{ "accessToken": "eyJ...", "refreshToken": "eyJ...", "isNewUser": true, "onboarded": false }
```

- 제공자 토큰 검증에 실패하면 401 `INVALID_PROVIDER_TOKEN`.
- 처음 로그인하는 사용자인데 제공자가 준 이메일이 다른 방법으로 이미 가입되어 있으면 409 `EMAIL_REGISTERED_WITH_OTHER_METHOD`.
- 카카오는 이메일 제공이 사용자 선택이므로, 이메일 없이도 가입됩니다.

### POST /auth/refresh — 토큰 재발급

```json
// 요청
{ "refreshToken": "eyJ..." }
// 응답 200 (리프레시 토큰도 새로 발급하고 이전 것은 폐기)
{ "accessToken": "eyJ...", "refreshToken": "eyJ..." }
```

리프레시 토큰이 만료·폐기되었으면 401 `INVALID_TOKEN`. 앱은 로그인 화면으로 보냅니다.

### POST /auth/logout — 로그아웃

```json
// 요청
{ "refreshToken": "eyJ..." }
// 응답 204
```

### PUT /me/device-token — 푸시 토큰 등록

```json
// 요청
{ "fcmToken": "...", "platform": "ANDROID" }
// 응답 204
```

같은 토큰이 다른 계정에 있으면 현재 계정으로 옮깁니다.

### POST /me/attendance — 출석체크

앱이 실행되거나 백그라운드에서 돌아올 때 자동으로 부릅니다. 하루에 여러 번 불러도 됩니다.

```json
// 응답 200
{ "date": "2026-10-12", "alreadyAttended": false, "currentStreak": 5, "longestStreak": 12 }
```

### DELETE /me — 회원 탈퇴

```json
// 응답 204
```

인증 정보·토큰·AI 대화를 지우고 습관명·목표 텍스트를 비웁니다. 탈퇴하면 토큰이 지워지므로, 이후 요청은 401 `INVALID_TOKEN`에서 막힙니다.

## 2. 온보딩

### GET /categories — 카테고리 목록 조회

화면 2와 통계·도감의 카테고리 표시에 같이 씁니다.

```json
// 응답 200
[
  {
    "code": "ex", "name": "운동", "shortName": "운동", "element": "불꽃",
    "glyph": "🔥", "color": "#E8553D", "sortOrder": 1,
    "opened": false,
    "starter": { "speciesId": 1, "name": "몬스터 이름", "imageUrl": "https://..." }
  }
]
```

### GET /measure-types?categories=ex,st — 측정 단위·추천 습관 조회

화면 3에서 고른 카테고리만 넘깁니다. 온보딩 이후 습관을 추가할 때도 씁니다.

```json
// 응답 200
[
  {
    "categoryCode": "ex",
    "measureTypes": [
      { "id": 1, "name": "운동 시간", "unit": "분", "scoringMode": "TARGET_RATIO",
        "defaultTarget": 30, "step": 5, "maxValue": 600 }
    ],
    "presets": [
      { "id": 1, "name": "아침 러닝", "measureTypeId": 1, "defaultTarget": 30 }
    ]
  }
]
```

기간 선택지(`D7`, `D30`, `D100`)는 고정값이라 앱에 둡니다.

### POST /onboarding — 온보딩 완료 (일괄 제출)

화면 4의 시작 버튼에서 한 번만 부릅니다. 하나라도 틀리면 아무것도 저장하지 않고, 틀린 항목을 `errors`에 모두 담아 돌려줍니다.

```json
// 요청
{
  "categories": ["ex", "st"],
  "habits": [
    { "categoryCode": "ex", "measureTypeId": 1, "name": "걷기", "dailyTarget": 30, "periodCode": "D30" }
  ],
  "goals": [
    { "goalType": "WEEKLY", "title": "헬스장 3번 가기" }
  ]
}
// 응답 201
{
  "starters": [
    { "userMonsterId": 10, "speciesId": 1, "categoryCode": "ex", "name": "몬스터 이름",
      "imageUrl": "https://...", "location": "FIELD" }
  ],
  "partnerMonsterId": 10,
  "habitIds": [100],
  "goalIds": [200]
}
```

| 검사 | 실패 시 |
| --- | --- |
| 이미 온보딩 완료 | 409 `ALREADY_ONBOARDED` |
| 카테고리 1\~3개, 중복 없음 | 400 |
| 습관 1\~5개, 각 습관의 카테고리가 고른 카테고리 안에 있음, 측정 단위가 그 카테고리 것 | 400 |
| 습관 이름 1\~30자, 목표값 > 0 그리고 입력 상한 이하 | 400 |
| 목표: 주간 0\~3개, 월간 0\~1개, 제목 1\~50자 | 400 |

온보딩에서 등록한 습관은 오늘부터 시작합니다. 대화 상대는 운동 카테고리 몬스터, 운동을 고르지 않았으면 고른 카테고리 중 순서가 가장 앞선 카테고리의 몬스터입니다.

## 3. 상단 바·메인 화면

### GET /me/status — 상단 바 조회

```json
// 응답 200
{
  "businessDate": "2026-10-12",
  "currentStreak": 5,
  "gold": 340,
  "ballCount": 2,
  "checkedInToday": true,
  "exploreRemaining": 1,
  "exploreTotal": 3,
  "endedHabitCount": 0
}
```

- 체크인 전에는 `exploreRemaining`, `exploreTotal`이 0입니다.
- `endedHabitCount`는 기간을 채워 연장·그만두기 선택을 기다리는 습관 수입니다. 1 이상이면 앱이 선택을 안내합니다.

### GET /me/today — 오늘 요약 조회 (스크롤탭)

오늘의 점수·성실도·골드는 보상 기준(첫 제출 값)입니다.

```json
// 응답 200
{
  "businessDate": "2026-10-12",
  "checkedIn": true,
  "goldEarned": 353,
  "overallRate": 88,
  "habits": [
    { "habitId": 100, "name": "걷기", "categoryCode": "ex", "unit": "분",
      "dailyTarget": 30, "rewardedValue": 20, "rewardedScore": 13, "counted": true,
      "filledDays": 4, "periodDays": 30 }
  ]
}
```

체크인 전이면 `goldEarned`, `overallRate`, `rewardedValue`, `rewardedScore`, `counted`가 null입니다.

### GET /monsters?location=FIELD — 내 몬스터 목록

`location`: `FIELD`(메인 필드) | `BAG`(가방 몬스터 탭) | 생략하면 전체(챗봇 대화 상대 선택).

```json
// 응답 200
[
  { "userMonsterId": 10, "speciesId": 1, "name": "몬스터 이름", "categoryCode": "ex",
    "level": 7, "stage": 0, "imageUrl": "https://...", "displayHeight": 72,
    "facing": "FRONT", "location": "FIELD", "isPartner": true }
]
```

대화 상대는 가방에 있을 수 있습니다. 필드 표시와 챗봇 대화 상대는 별개입니다.

### GET /monsters/{id} — 몬스터 상세 (팝업)

```json
// 응답 200
{
  "userMonsterId": 10, "name": "몬스터 이름", "imageUrl": "https://...",
  "categoryCode": "ex", "stage": 0, "rarity": 2,
  "level": 7, "expInLevel": 40, "expToNextLevel": 125,
  "nextEvolutionLevel": 10,
  "affection": 6, "affectionMax": 10, "affectionTier": "MID",
  "todayActions": { "pet": true, "play": false },
  "location": "FIELD", "isPartner": true
}
```

최종 진화 단계면 `nextEvolutionLevel`은 null입니다.

### POST /monsters/{id}/affection — 쓰다듬기·놀아주기

```json
// 요청
{ "action": "PET" }   // PET 쓰다듬기 | PLAY 놀아주기
// 응답 200
{ "gain": 2, "affection": 8, "affectionTier": "HIGH" }
```

오늘 같은 행동을 이미 했으면 409 `ALREADY_DONE_TODAY`. 호감도가 최대면 `gain`은 0입니다.

### POST /monsters/{id}/feed — 간식 주기

헤더 `Idempotency-Key` 필요.

```json
// 요청
{ "itemCode": "POTION_M" }   // POTION_S | POTION_M | POTION_L
// 응답 200
{
  "expGained": 100, "levelBefore": 7, "levelAfter": 8,
  "stageBefore": 0, "stageAfter": 0, "evolved": false,
  "remainingQuantity": 2
}
```

물약이 없으면 422 `NO_ITEM`, 최대 레벨이면 422 `MAX_LEVEL`.

### GET /monsters/{id}/line — 말걸기

```json
// 응답 200
{ "affectionTier": "MID", "line": "오늘도 뛸 거지? 따라갈게." }
```

### PATCH /monsters/{id}/location — 가방에 넣기·꺼내기

```json
// 요청
{ "location": "BAG" }   // BAG 가방에 넣기 | FIELD 꺼내기
// 응답 200
{ "userMonsterId": 10, "location": "BAG", "fieldCount": 3 }
```

필드가 1마리일 때 넣기, 5마리일 때 꺼내기는 422 `FIELD_LIMIT`. 대화 상대도 가방에 넣을 수 있습니다.

### PUT /me/partner — 대화 상대 변경

메인 팝업의 "대화 상대로"와 챗봇 상단 선택이 같이 씁니다.

```json
// 요청
{ "userMonsterId": 12 }
// 응답 200
{ "partnerMonsterId": 12 }
```

### GET /shop/items — 상점 목록

```json
// 응답 200
{
  "gold": 340,
  "items": [
    { "code": "POTION_S", "name": "하급 경험치 물약", "shortName": "하급", "price": 20,
      "effectType": "MONSTER_EXP", "effectValue": 20 },
    { "code": "BALL", "name": "성실볼", "shortName": "성실볼", "price": 50,
      "effectType": "CAPTURE", "effectValue": 1 }
  ]
}
```

가격·효과 값은 shop\_item 시드를 따릅니다.

### POST /shop/purchases — 아이템 구매

헤더 `Idempotency-Key` 필요. 챗봇의 "볼 사기"도 이 요청을 씁니다.

```json
// 요청
{ "itemCode": "BALL", "quantity": 1 }
// 응답 201
{ "purchaseId": 300, "totalPrice": 50, "gold": 290, "itemCode": "BALL", "quantity": 3 }
```

- 응답의 `quantity`는 구매 후 가방에 있는 개수입니다.
- 요청 `quantity`는 1\~99. 범위를 벗어나면 400.
- 골드가 부족하면 422 `NOT_ENOUGH_GOLD`.

### GET /inventory — 가방 아이템 조회

가방의 몬스터 탭은 `GET /monsters`를 씁니다.

```json
// 응답 200
{
  "items": [
    { "itemCode": "POTION_S", "name": "하급 경험치 물약", "quantity": 2 },
    { "itemCode": "BALL", "name": "성실볼", "quantity": 3 }
  ]
}
```

## 4. 습관 (신규)

### 4-1. 점수 공식

| 측정 방식 | 점수 | 예시 (목표 30분) |
| --- | --- | --- |
| 목표 미달 | 20 × (기록 ÷ 목표) | 20분 → 13 |
| 목표 달성 | 20 | 30분 → 20 |
| 목표 초과 | 20 + 10 × (기록 ÷ 목표 − 1), 최대 25 | 45분 이상 → 25 |
| O/X | 했으면 20, 못했으면 0 | |
| 범위(수면 시간) | 목표 범위 안이면 20, 밖이면 0 | |

- 점수는 반올림한 정수이며, 공식의 수치는 `config.balance_config`(`score_*`)를 따릅니다.
- **달성률**(성실도 계산용) = min(점수 ÷ 20, 1) × 100. **반올림한 점수로 계산**합니다. 예: 13점 → 65%.
- **전체 성실도(`overallRate`)** = 점수 상위 3개 습관의 달성률 평균(반올림). 습관이 3개 미만이면 있는 습관만으로 평균을 냅니다.

**자기보고 상한 (v6, D-62)** — 위 공식으로 계산한 뒤:
- 근거가 자기보고(`SHORT` · `DETAILED`)면 최대 `self_report_max_score`(20). 목표를 넘긴 몫(21\~25점)은 받지 못합니다.
- 확인됨(`VERIFIED`, 9장 타이머)이면 최대 25점 (위 공식 그대로).
- 상한이 실제로 깎는 것은 **시간 · 양** 방식뿐입니다. O/X와 범위는 원래 최대 20점입니다.

**카테고리 경험치 (v6, D-62)** — 반영 습관마다 `점수 × 방식 계수 × (확인됨이면 exp_coef_verified)`를 **습관마다 반올림**하고, 카테고리 경험치는 그 합입니다. 골드는 그대로 1점 = 1G입니다.

| 측정 방식 | 설정 키 | 값 |
| --- | --- | --- |
| 시간 · 양 (`TARGET_RATIO`) | `exp_coef_ratio` | 1.0 |
| 범위 (`RANGE`, 수면) | `exp_coef_range` | 0.9 |
| O/X (`BINARY`) | `exp_coef_binary` | 0.8 |
| 확인된 기록 (곱하기) | `exp_coef_verified` | 1.2 |

예: O/X 20점 → 경험치 16, 수면 범위 안 20점 → 18, 공부 45분 타이머(목표 30분) 25점 → 25 × 1.0 × 1.2 = 30.

### 4-2. 습관 상태와 기간

| 상태 | 뜻 | 체크인 대상 |
| --- | --- | --- |
| `ACTIVE` | 기간 진행 중 | O (시작일 ≤ 오늘) |
| `ENDED` | 기간을 채워 연장·그만두기 선택을 기다림 | X (다음 날부터) |
| `STOPPED` | 그만둠. 통계·기록용으로만 남음 | X (다음 날부터) |

- **기간은 채운 날 수 기준**입니다. D7은 7일, D30은 30일, D100은 100일을 채우면 끝나며, 연속일 필요는 없습니다.
- **채운 날은 첫 제출에서 그 습관을 했다고(`done: true`) 제출한 날**입니다. "못했어"로 제출한 날과 체크인을 빠뜨린 날은 세지 않을 뿐, 기간이 끝나지는 않습니다. 오래 접속하지 않아도 채운 날은 사라지지 않습니다.
- 다시 체크(PUT)로 바꾼 값은 채운 날 수에 영향을 주지 않습니다.
- `filledDays`는 지금까지 채운 날 수, `periodDays`는 채워야 할 날 수(7/30/100)입니다. 종료일은 없습니다.
- 첫 제출로 `filledDays`가 `periodDays`에 닿으면 그 제출에서 기간 보너스를 주고 `ENDED`로 바뀝니다.
- 진행 중인 습관의 목표값은 바꿀 수 없습니다. 바꾸려면 기간을 채운 뒤 연장할 때 바꿉니다.
- 습관 개수 상한은 `ACTIVE` + `ENDED`를 합쳐 5개입니다. 기간 완료(`ENDED`)도 칸을 차지하므로, 꽉 찼으면 연장하거나 그만둬야 새로 추가할 수 있습니다.
- 습관 개수 하한은 `ACTIVE` + `ENDED`를 합쳐 1개입니다. 체크할 습관이 하나도 없으면 체크인 · 탐색 흐름이 끊기기 때문입니다.
- **시작일 규칙**: 습관을 추가하거나 연장하면, 오늘 체크인을 아직 제출하지 않았으면 오늘부터, 이미 제출했으면 내일부터 시작합니다. 제출한 체크인에 습관이 새로 끼어드는 일을 막기 위해서입니다.

### GET /habits — 습관 목록

`status`: `ACTIVE` | `ENDED` | `STOPPED`, 쉼표로 여러 개. 생략하면 `ACTIVE,ENDED`.

```json
// 응답 200
[
  { "habitId": 100, "categoryCode": "ex", "name": "걷기", "measureTypeId": 1, "unit": "분",
    "dailyTarget": 30, "periodCode": "D30", "startDate": "2026-10-09",
    "filledDays": 4, "periodDays": 30, "status": "ACTIVE" }
]
```

### POST /habits — 습관 추가

온보딩 이후 습관을 추가하거나, 카테고리를 새로 연 뒤 그 카테고리의 습관을 등록할 때 씁니다.

```json
// 요청
{ "categoryCode": "md", "measureTypeId": 12, "name": "10분 명상", "dailyTarget": 10, "periodCode": "D7" }
// 응답 201: GET /habits의 항목과 같은 모양
```

| 검사 | 실패 시 |
| --- | --- |
| 이름 1\~30자, 목표값 > 0 그리고 입력 상한 이하, 측정 단위가 그 카테고리 것 | 400 |
| 열지 않은 카테고리 | 422 `CATEGORY_LOCKED` |
| `ACTIVE` + `ENDED`가 이미 5개 | 422 `HABIT_LIMIT` |

### POST /habits/{habitId}/renew — 기간 연장

`ENDED` 습관을 새 기간으로 다시 시작합니다. 목표값을 바꿀 수 있습니다.

```json
// 요청: dailyTarget을 생략하면 이전 값 유지
{ "periodCode": "D30", "dailyTarget": 40 }
// 응답 200: GET /habits의 항목과 같은 모양 (status: ACTIVE, filledDays: 0부터 다시 셈)
```

| 검사 | 실패 시 |
| --- | --- |
| `ENDED`가 아님 | 409 `HABIT_NOT_ENDED` |
| 목표값 범위 | 400 |

### POST /habits/{habitId}/stop — 습관 그만두기

```json
// 응답 200
{ "habitId": 100, "status": "STOPPED" }
```

- `ACTIVE`와 `ENDED` 모두 그만둘 수 있습니다. 진행 중에 그만두면 채운 날과 쌓은 보상은 남지만 기간 보너스는 없습니다.
- 이미 그만둔 습관이면 409 `HABIT_ALREADY_STOPPED`.
- `ACTIVE` + `ENDED`가 이 습관 하나뿐이면 그만둘 수 없습니다 → 422 `LAST_HABIT`.
- 오늘 체크인을 제출한 뒤 그만두면, 그날의 다시 체크(PUT)에는 계속 포함되고 다음 날부터 빠집니다.
- 이 습관에 끝나지 않은 타이머가 있으면 같은 처리 안에서 끝냅니다 (`endReason: HABIT_STOPPED`, 9장, v6).
- 앱은 그만두기 전에 확인 창을 띄웁니다.

## 5. 챗봇 — 체크인·탐색·포획

### GET /checkins/today — 체크인 준비 조회

```json
// 응답 200
{
  "businessDate": "2026-10-12",
  "submitted": false,
  "revision": 0,
  "partner": { "userMonsterId": 10, "name": "몬스터 이름", "imageUrl": "https://...", "affectionTier": "MID" },
  "tabs": [
    {
      "categoryCode": "ex", "categoryName": "운동",
      "habits": [
        { "habitId": 100, "name": "걷기", "unit": "분", "scoringMode": "TARGET_RATIO",
          "options": [10, 20, 30, 40, 60], "previousValue": null,
          "filledDays": 4, "periodDays": 30, "timerMinutes": 0 }
      ]
    }
  ]
}
```

- 제출 전: `ACTIVE`이고 시작일 ≤ 오늘인 습관이 들어갑니다. 대상이 없으면 `tabs`는 빈 배열입니다.
- 제출 후: 첫 제출에 들어간 습관이 들어갑니다(다시 체크 대상).
- `options`는 등록한 단위에서 고를 수 있는 값입니다. O·X 습관은 `[1]`(O)이며 "못했어"가 X입니다.
- 이미 제출했으면 `previousValue`에 마지막 값이 들어 있어 다시 체크할 때 미리 채웁니다.
- `timerMinutes` (v6): 오늘 기록된 타이머 합계(오늘 끝난 타이머 — 어제 시작해 오늘 끝낸 것 포함, 정수 분). 타이머를 쓸 수 없는 습관은 `null`, 쓸 수 있는데 기록이 없으면 `0`. 챗봇이 "타이머로 45분 했네! 이대로 적을까?"로 미리 채울 때 씁니다.

### POST /checkins/today — 체크인 제출 (첫 제출)

헤더 `Idempotency-Key` 필요. 탭은 화면 구분일 뿐이며, **오늘 체크인 대상인 습관 전체를 한 번에** 보냅니다.

```json
// 요청
{
  "businessDate": "2026-10-12",
  "answers": [
    { "habitId": 100, "done": true, "value": 20, "evidence": "DETAILED" },
    { "habitId": 101, "done": false },
    { "habitId": 102, "done": true, "value": 60 },
    { "habitId": 103, "done": true, "value": 2 }
  ]
}
// 응답 201
{
  "revision": 1,
  "habits": [
    { "habitId": 100, "score": 13, "counted": true, "evidence": "DETAILED", "scoreCapped": false, "expGained": 13 },
    { "habitId": 101, "score": 0, "counted": false, "evidence": "SHORT", "scoreCapped": false, "expGained": 0 },
    { "habitId": 102, "score": 20, "counted": true, "evidence": "SHORT", "scoreCapped": false, "expGained": 20 },
    { "habitId": 103, "score": 20, "counted": true, "evidence": "SHORT", "scoreCapped": false, "expGained": 20 }
  ],
  "overallRate": 88,
  "goldEarned": 353,
  "goldBreakdown": { "score": 53, "levelUp": 20, "periodBonus": 280 },
  "categoryExp": [
    { "categoryCode": "ex", "expGained": 13, "levelBefore": 3, "levelAfter": 4, "levelUpGold": 20 },
    { "categoryCode": "st", "expGained": 20, "levelBefore": 8, "levelAfter": 8, "levelUpGold": 0 },
    { "categoryCode": "fd", "expGained": 20, "levelBefore": 5, "levelAfter": 5, "levelUpGold": 0 }
  ],
  "periodBonuses": [
    { "habitId": 102, "periodCode": "D30", "multiplier": 1.5, "periodScore": 560, "bonusGold": 280 }
  ],
  "unlockedSpecies": [],
  "exploreTotal": 3,
  "gold": 693
}
```

**근거 (`evidence`, v6)**

- 보낼 수 있는 값: `SHORT` · `DETAILED`. 없으면 `SHORT` (지금 버튼 체크와 같다). `VERIFIED`를 보내면 400.
- **서버가 근거를 정한다** — 그 습관 · 그날의 확인된 기록이 **제출 값 이상**이면 `VERIFIED`. 받은 근거는 저장되고(`habit_checkin.evidence` · 첫 제출은 `rewarded_evidence`), 첫 제출 근거로 경험치 계수를 정합니다:

| 측정 항목 | 확인된 기록 |
| --- | --- |
| 운동 시간(분) · 공부 시간(분) · 명상 시간(분) | 그날 기록된(그날 끝난) 타이머 합계 (9장). 헬스 운동 시간은 다음 판 |
| 그 밖의 항목 | 없음 → 늘 자기보고 |

- 제출할 때 **끝나지 않은 타이머(도는 것 · 일시정지한 것)는 합계에 들어가지 않는다.** 앱은 제출 전에 도는 타이머가 있으면 "타이머를 끝내고 제출할까요?"를 묻는다.
- **타이머 값 맞추기** (D-42의 예외): 확인된 기록이 있는 습관은 "가장 가까운 선택지" 대신 아래로 맞춘다.
  "가장 가까운 값"으로 맞추면 기록보다 큰 선택지가 골라져 VERIFIED를 잃기 때문이다 (예: 목표 30분 → 선택지 7.5 · 15 · 22.5 · 30 · 45 · 60, 타이머 40분 → 가장 가까운 값 45 > 40 → 자기보고 20점).
  - 사용자가 말한(고른) 값이 **확인된 기록 이하**이면 → **확인된 기록 이하인 가장 큰 선택지** (위 예: 40 → 30, VERIFIED)
  - 확인된 기록보다 크면 → 지금처럼 가장 가까운 값 (자기보고로 처리)
  - 확인된 기록이 **가장 작은 선택지보다도 적으면** (예: 5분, 가장 작은 선택지 7.5) → 맞출 선택지가 없으므로 가장 가까운 값 (자기보고로 처리)
  - 앱이 타이머 · 헬스 값을 미리 채울 때도, `interpret`가 값을 맞출 때도 이 규칙을 쓴다.
- 확인된 기록보다 **많이** 적으면 그 습관 전체가 자기보고로 처리됩니다 (확인된 만큼만 따로 인정하지 않음). 앱은 타이머 값을 미리 채우고, 그보다 큰 값을 고르면 "타이머보다 많이 적으면 최대 20점이에요"를 보여 줍니다.
- 응답의 `evidence` · `scoreCapped`는 이번 제출 기준입니다. `scoreCapped`는 공식 점수가 자기보고 상한에 걸려 깎였으면 `true` (앱이 "타이머로 재면 25점까지!" 안내). `expGained`는 그 습관이 준 카테고리 경험치(반영 습관이 아니면 0)이고, `categoryExp[].expGained`는 그 합입니다.

**보상 규칙**

- **점수**: 습관마다 0\~25 (4-1 공식, 자기보고는 최대 20). `done: false`는 값 0, 점수 0으로 저장합니다.
- **반영 습관(`counted`)**: 점수 상위 3개 습관. 골드·카테고리 경험치·기간 보너스는 반영 습관에만 적용합니다. 점수가 같으면 등록 순서가 빠른 습관을 고릅니다.
- **골드**: 반영 습관 점수의 합 (1점 = 1G). 위 예시는 13 + 20 + 20 = 53G.
- **카테고리 경험치**: 반영 습관의 점수 × 방식 계수(× 확인됨 1.2)를 습관마다 반올림한 값이 각 습관의 카테고리 경험치로 들어갑니다 (4-1, v6). 레벨업 필요 경험치는 10 × 현재 레벨, 최대 레벨 20, 레벨업마다 20G. 위 예시의 ex는 Lv.3에서 경험치 20을 가지고 있었고, 13을 받아 33이 되어 30을 쓰고 Lv.4(남은 경험치 3)가 됩니다.
- **종 해금**: 레벨업으로 탐색에 새로 나오게 된 종이 있으면 `unlockedSpecies`에 `{ speciesId, categoryCode }`로 담깁니다.
- **기간 보너스**: 이번 제출로 습관의 `filledDays`가 `periodDays`에 닿으면, 그 기간에 그 습관이 **반영 습관으로 받은 점수의 합**(`periodScore`, 첫 제출 기준)에 `(배수 − 1)`을 곱한 만큼 골드를 줍니다. 배수는 D7 1.2, D30 1.5, D100 2.0입니다. 위 예시는 560 × 0.5 = 280G. 이 습관은 `ENDED`가 됩니다.
- **`goldEarned`** = 점수 골드 + 레벨업 골드 + 기간 보너스 골드. 구성은 `goldBreakdown`에 나눠 담습니다.
- **`overallRate`**: 4-1 공식. 위 예시는 (100 + 100 + 65) ÷ 3 = 88.
- **탐색 횟수**: 첫 제출이 전부 "못했어"(`done: false`)이면 `exploreTotal` 1, 그 외에는 3.
- 보상·경험치·채운 날·탐색 횟수는 모두 첫 제출 기준이며 다시 체크해도 바뀌지 않습니다.

**알려진 한계**: 자기보고는 상한(20점)으로 넘긴 몫을 막지만(v6), 목표만큼을 부풀리거나, 가장 작은 값을 "했어"로 내 탐색 3회를 받는 것을 막을 수 없습니다. 다시 체크로 값을 낮춰도 보상이 유지되는 것은 정직한 정정을 벌하지 않기 위한 의도된 선택입니다. 타이머(9장)는 "시간이 흘렀다"만 확인하고 실제로 했는지는 확인하지 못합니다. 그래서 보상 차이도 작게(상한 5점 · 경험치 ×1.2) 둡니다.

| 검사 | 실패 시 |
| --- | --- |
| `businessDate`가 서버 오늘 날짜와 다름 | 409 `BUSINESS_DATE_CHANGED` |
| 오늘 이미 제출 | 409 `ALREADY_SUBMITTED` (수정은 PUT) |
| 오늘 체크인 대상 습관이 없음 | 409 `NO_ACTIVE_HABIT` (앱은 습관 추가·연장을 안내) |
| 대상 습관을 모두 빠짐없이 보냈는지, 본인 습관인지 | 400 |
| `done: true`면 `value`가 그 습관의 선택지 중 하나 | 400 |
| `evidence`가 `SHORT` · `DETAILED`가 아님 (`VERIFIED`를 보냄 등) | 400 |

### PUT /checkins/today — 체크인 수정 (다시 체크)

헤더 `Idempotency-Key` 필요. 요청 본문은 POST와 같으며, 보낼 습관은 **오늘 첫 제출에 들어간 습관 전체**입니다. 첫 제출 뒤에 기간을 채웠거나 그만둔 습관도 포함합니다.

```json
// 응답 200: 보상은 변하지 않음. 습관 전체를 돌려줌
{
  "revision": 2,
  "habits": [
    { "habitId": 100, "value": 40, "score": 23, "evidence": "VERIFIED", "scoreCapped": false },
    { "habitId": 101, "value": 0, "score": 0, "evidence": "SHORT", "scoreCapped": false },
    { "habitId": 102, "value": 60, "score": 20, "evidence": "SHORT", "scoreCapped": false },
    { "habitId": 103, "value": 2, "score": 20, "evidence": "SHORT", "scoreCapped": false }
  ],
  "overallRate": 100
}
```

- 오늘 제출이 없으면 404 `CHECKIN_NOT_FOUND`. 어제 이전 기록은 고칠 수 없습니다.
- 여기의 점수와 `overallRate`는 다시 체크한 최신 값이며, 통계 그래프에 쓰입니다.
- 근거 판정 · 자기보고 상한은 첫 제출과 같습니다. 최신 근거만 바뀌고, 보상(경험치 계수 포함)은 첫 제출 근거 그대로입니다 (v6). 제출 뒤에 잰 타이머는 다시 체크로만 반영됩니다.

### POST /checkins/today/dialogue — 체크인 대사 요청

제출·수정 응답을 받은 뒤 부릅니다. 대사가 늦어도 제출 결과에는 영향이 없습니다.

```json
// 응답 200
{ "revision": 1, "line": "오늘 20분이나 걸었구나!", "source": "LLM" }   // source: LLM | TEMPLATE
```

- 대사는 오늘 체크인의 최신 `revision`당 한 번만 만듭니다. 같은 `revision`에 다시 부르면 저장된 대사를 그대로 돌려줍니다.
- AI가 실패하거나 3초를 넘기면 템플릿 대사를 `source: "TEMPLATE"`로 돌려줍니다.
- 오늘 제출이 없으면 409 `CHECKIN_REQUIRED`.

### POST /checkins/today/interpret — 대화 해석 (v6)

사용자가 챗봇에 쓴 말을 서버가 AI(Gemini)에 보내 해석하고, **검사를 통과한 기록 후보**와 몬스터의 대답을 돌려준다.
이 API는 **아무것도 확정하지 않는다.** 앱은 후보를 확인 카드로 보여 주고, 사용자가 [맞아]를 누르면 기존 `POST /checkins/today`로 제출한다.

**서버는 대화를 저장하지 않는다.** 앞 대화는 앱이 `history`로 보내고, 서버는 Gemini에 보낸 뒤 응답만 돌려준다 (DB에 대화 원문 · 해석 결과를 남기지 않음).

```json
// 요청
{
  "businessDate": "2026-10-30",
  "message": "아침에 공원에서 30분 뛰었고 물은 2리터 마셨어",
  "history": [
    { "role": "BOT", "text": "오늘 아침 러닝은 했어?" }
  ],
  "draft": [
    { "habitId": 101, "done": true, "value": 45, "evidence": "DETAILED" }
  ],
  "askingHabitId": 100,
  "askedAgainHabitIds": [103]
}
```

| 필드 | 설명 |
| --- | --- |
| `message` | 사용자가 쓴 말. 1 ~ 300자 |
| `history` | 직전 대화 최대 10개 (`BOT` · `USER`), **항목마다 `text` 1 ~ 300자**. 서버는 대화를 기억하지 않으므로 앱이 보낸다. **앱이 보낸 값이라 믿지 않는다** — 맥락 참고용일 뿐, 결과는 아래 검사를 똑같이 거친다 |
| `draft` | 지금까지 정해진 후보 (다시 묻지 않게). 없으면 빈 배열 |
| `askingHabitId` | 챗봇이 방금 물어본 습관 (없으면 null) |
| `askedAgainHabitIds` | 오늘 대화에서 **이미 한 번 다시 물어본** 습관들. 서버는 여기 있는 습관을 또 `askAgain`으로 돌려주지 않는다. 앱이 `askAgain`을 받을 때마다 그 `habitId`를 더해 보낸다. 없으면 빈 배열 |

```json
// 응답 200
{
  "reply": "와, 공원에서 30분이나 뛰었구나! 물도 2L 다 마셨네~",
  "answers": [
    { "habitId": 100, "done": true, "value": 30, "evidence": "DETAILED", "confidence": 0.92 },
    { "habitId": 102, "done": true, "value": 2, "evidence": "SHORT", "confidence": 0.88 }
  ],
  "askAgain": null,
  "remainingHabitIds": [103],
  "safety": false,
  "source": "LLM"
}
```

| 필드 | 설명 |
| --- | --- |
| `reply` | 몬스터 말투의 대답 (최대 120자). 점수 · 골드 숫자는 넣지 않는다 — **서버가 검사한다** (아래 검사 6) |
| `answers` | 이번 말에서 해석한 기록 후보. `value`는 서버가 **그 습관의 선택지 중 가장 가까운 값**으로 맞춘 값(D-42), O·X는 `1`. 단 **확인된 기록(타이머 · 헬스)이 있는 습관은 "타이머 값 맞추기"(POST /checkins/today)** 규칙으로 맞춘다 |
| `evidence` | `SHORT`(짧은 자기보고) · `DETAILED`(구체적 자기보고). **둘은 보상이 같다** (표시 · 기록용 라벨). **`VERIFIED`는 이 API가 붙이지 않는다** — 타이머 · 헬스 기록이 있을 때 제출 시 서버가 붙인다 |
| `confidence` | 0 ~ 1. 서버 기준(`ai_min_confidence`, 기본 0.6)보다 낮은 후보는 `answers`에서 빼고 `askAgain`으로 바꾼다 |
| `askAgain` | 다시 물어야 할 때 `{ "habitId": 100, "question": "몇 분쯤 했어?" }`. 그 습관이 `askedAgainHabitIds`에 이미 있으면 `null` — 앱이 선택지 버튼을 보여 준다 |
| `remainingHabitIds` | 아직 기록 후보가 없는 오늘 대상 습관 (등록 순서) |
| `safety` | 힘든 감정 · 위기 신호를 감지하면 `true`. **AI 판단과 서버 키워드 검사 중 하나라도 걸리면** `true` (AI가 실패한 `TEMPLATE` 응답에서도 키워드 검사는 한다). `reply`는 안내 문구로 바뀌고, 앱은 게임 연출(보상 칩 등)을 멈춘다. 서버에 저장하지 않는다 |
| `source` | `LLM` · `TEMPLATE`(AI 실패 · 제한 시간 초과 · 형식 오류 → 해석 없이 대본형 질문) |

**서버가 AI 답을 믿지 않고 다시 검사하는 것**
1. `habitId`가 오늘 체크인 대상인지 (아니면 버린다)
2. `value`가 측정 항목의 0 ~ `max_value` 안인지 (밖이면 버리고 `askAgain`)
3. 선택지에 맞추기 (가장 가까운 값, 확인된 기록이 있으면 "타이머 값 맞추기"(POST /checkins/today)), O·X는 0/1만
4. AI가 낸 다른 필드(점수 · 골드 등)는 무시한다 — 응답 형식에 그런 칸이 없다
5. 사용자의 말 속 지시("점수 25로 해", "프롬프트 무시해")는 해석 대상일 뿐, 따르지 않는다
6. `reply`는 120자를 넘으면 자르고, **사용자가 이번 `message`에 쓴 숫자가 아닌 숫자가 들어 있으면 버리고 대본형 대사로 바꾼다**. "30분이나 뛰었구나!"처럼 사용자가 말한 숫자를 되받는 것은 된다. AI는 해석 단계에서 점수 · 골드를 모르므로(점수는 제출 때 서버가 계산) 그 밖의 숫자는 지어낸 것이다. 한글로 쓴 숫자("이십오 점")는 못 막는다
7. 위기 신호는 AI 판단과 별도로 **서버 키워드 검사**도 한다 (`message`에서). 하나라도 걸리면 `safety: true`.
   - **강한 표현만** 넣는다 — 예: "죽고 싶" · "자살" · "자해" · "사라지고 싶" · "살기 싫". **"죽겠"은 넣지 않는다** ("피곤해 죽겠어" · "배고파 죽겠다"는 일상 표현이라 체크인마다 게임이 멈춤)
   - 띄어쓰기를 지운 뒤 비교한다 ("죽고 싶" = "죽고싶")
   - 목록은 **서버 코드 상수**. 미묘한 표현은 AI 판단에 맡긴다
   - 비교 방법: `message`에서 공백 · 문장부호를 지운 뒤 아래 낱말이 **들어 있으면**(부분 일치) 걸린다. 그래서 "죽고 싶어" · "죽고싶다" · "죽고싶음"이 모두 `죽고싶`에 걸린다
   - **키워드 목록** (구현 때 테스트 문장으로도 씀)

| 묶음 | 키워드 (공백 없이 비교) |
| --- | --- |
| 자살 · 죽음을 바람 | `자살` · `극단적선택` · `극단선택` · `죽고싶` · `죽고시퍼` · `죽고십` · `뒤지고싶` · `디지고싶` · `죽어버리고싶` · `죽어야겠` · `죽는게낫` · `죽는게나을` · `차라리죽` |
| 사라지고 싶음 | `사라지고싶` · `없어지고싶` · `태어나지말` · `안태어났으면` |
| 삶을 거부함 | `살기싫` · `살고싶지않` · `사는게싫` · `살아서뭐해` · `살이유가없` · `살의미가없` |
| 자해 · 방법 | `자해` · `손목긋` · `손목을긋` · `목매달` · `뛰어내리고싶` · `투신` · `약먹고죽` |
| 작별 | `유서` |

   - **넣지 않은 것** (일상 표현이라 오탐): `죽겠`("피곤해 죽겠어") · `죽을뻔` · `죽는줄` · `못살겠`("더워서 못 살겠다") · `미치겠` · `목매`("돈에 목매다" — 그래서 `목매달`만) · `죽을래`(남에게 하는 말)
   - 알고 받아들인 오탐: "자살 예방 영상 봤어"처럼 낱말을 다른 뜻으로 써도 걸린다. 위기 쪽으로 틀리는 편이 낫다고 본다 — 걸리면 게임 연출만 잠시 멈출 뿐 기록 · 보상은 그대로
   - 구현 때 이 목록을 그대로 테스트 문장(걸려야 할 것 · 걸리면 안 되는 것)으로도 쓴다

**호출 한도**: 요청이 형식 검사를 통과하면 Gemini를 부르기 **전에** 오늘 호출 수를 1 올린다 (DB `ai.daily_call_count`). 한도에 이미 닿았으면 올리지 않고 429.

| 검사 | 실패 시 |
| --- | --- |
| `businessDate`가 서버 오늘과 다름 | 409 `BUSINESS_DATE_CHANGED` |
| 오늘 체크인 대상 습관이 없음 | 409 `NO_ACTIVE_HABIT` |
| `message`가 비었거나 300자 초과, `history` 10개 초과 · 항목 `text`가 비었거나 300자 초과 | 400 `INVALID_REQUEST` |
| 하루 AI 호출 한도(`ai_daily_call_limit`, 기본 60) 초과 | 429 `AI_RATE_LIMITED` — 앱은 버튼(대본형)으로 이어 간다 |
| AI 실패 · 제한 시간(기존 설정 `llm_timeout_ms`, 3000) 초과 | 오류가 아니라 200 + `source: "TEMPLATE"`, `answers: []` |

- 이미 오늘 제출했어도 부를 수 있다 (다시 체크 대화). 보상은 첫 제출 기준 그대로다.
- 모델 이름은 기존 설정 `llm_model`을 쓴다.

### POST /explores — 탐색하기·다시 탐색

헤더 `Idempotency-Key` 필요.

**등장 규칙**
- 탐색 결과는 셋입니다: 꽝(`MISS`), 가진 종(`DUPLICATE`), 안 가진 종(`ENCOUNTER`).
- 꽝 확률은 35%이며 설정값(`explore_miss_rate`)입니다.
- 등장 후보는 **연 카테고리의 종 중 해금 레벨 ≤ 카테고리 레벨**인 종입니다.
- 후보마다 가중치 = 희귀도 가중치 × (안 가진 종이면 가중치 배수). 희귀할수록 적게 나오고, 안 가진 종이 더 자주 나옵니다. 가중치는 설정값입니다.
- **가진 종**이 나오면 볼 없이 바로 골드(15G)를 받고 그 탐색은 끝납니다.
- **안 가진 종**이 나오면 볼을 던져 포획을 시도할 수 있습니다. 도감에서 본 종(`SEEN`)도 안 가진 종이므로 `ENCOUNTER`로 나오고 가중치 배수를 받습니다.
- **도감 등록**: `ENCOUNTER`가 나온 순간 그 종을 도감에 본 종으로 등록합니다. 이후 볼이 없거나, "그만"을 누르거나, 다시 탐색으로 사라지거나, 포획에 실패해도 등록은 유지됩니다. 처음 보는 종이면 응답의 `newlySeen`이 true입니다.

```json
// 요청
{ "businessDate": "2026-10-12" }
// 응답 201: 안 가진 종 등장
{
  "exploreId": 500,
  "result": "ENCOUNTER",
  "species": { "speciesId": 7, "name": "몬스터 이름", "imageUrl": "https://...",
               "categoryCode": "st", "rarity": 2, "captureRate": 0.6 },
  "newlySeen": true,
  "goldAwarded": 0,
  "gold": 340,
  "skippedExploreId": null,
  "exploreRemaining": 2
}
// 응답 201: 가진 종 등장 (자동 골드)
{
  "exploreId": 501,
  "result": "DUPLICATE",
  "species": { "speciesId": 1, "name": "몬스터 이름", "imageUrl": "https://...",
               "categoryCode": "ex", "rarity": 3, "captureRate": null },
  "newlySeen": false,
  "goldAwarded": 15,
  "gold": 355,
  "skippedExploreId": null,
  "exploreRemaining": 1
}
// 응답 201: 꽝
{ "exploreId": 502, "result": "MISS", "species": null, "newlySeen": false, "goldAwarded": 0, "gold": 355,
  "skippedExploreId": null, "exploreRemaining": 0 }
```

- 처리하지 않은 등장이 있는 상태에서 다시 탐색하면 그 등장은 사라지고 `skippedExploreId`에 번호가 담깁니다.
- `newlySeen`은 `ENCOUNTER`에서만 true가 될 수 있습니다. 앱은 이 값으로 "도감에 새로 등록" 연출을 합니다.

| 검사 | 실패 시 |
| --- | --- |
| `businessDate`가 서버 오늘 날짜와 다름 | 409 `BUSINESS_DATE_CHANGED` |
| 오늘 체크인 제출 전 | 409 `CHECKIN_REQUIRED` |
| 남은 기회 0 | 422 `NO_EXPLORE_LEFT` |

### GET /explores/pending — 남은 등장 조회 (신규)

챗봇 화면에 들어올 때 부릅니다. "그만"을 눌렀거나 앱이 꺼져서 처리되지 않은 오늘의 등장(`ENCOUNTER`)을 돌려줍니다.

```json
// 응답 200: 남은 등장 있음 (POST /explores의 ENCOUNTER 응답과 같은 모양. 이미 등록된 등장이므로 newlySeen은 false)
// 응답 204: 남은 등장 없음
```

등장은 그날이 끝날 때(다음 날 00시)까지 남고, 그 뒤에는 사라집니다.

### POST /explores/{exploreId}/capture — 볼 던지기

헤더 `Idempotency-Key` 필요. 볼 1개를 쓰고, 종의 희귀도별 포획률로 성공 여부가 정해집니다. **실패하면 몬스터는 도망가고 그 등장은 끝납니다.**

```json
// 요청
{ "businessDate": "2026-10-12" }
// 응답 200: 포획 성공
{
  "outcome": "CAPTURED",
  "monster": { "userMonsterId": 15, "name": "몬스터 이름", "imageUrl": "https://...", "location": "FIELD" },
  "ballCount": 1,
  "dex": { "dexCount": 5, "newSlotAvailable": true }
}
// 응답 200: 포획 실패
{ "outcome": "ESCAPED", "monster": null, "ballCount": 1, "dex": { "dexCount": 4, "newSlotAvailable": false } }
```

- 포획률은 희귀도 1/2/3이 각각 80%/60%/40%이며 설정값입니다. 등장 응답의 `captureRate`로 미리 보여줍니다.
- 필드가 5마리면 새 몬스터는 가방(`BAG`)으로 갑니다.
- `newSlotAvailable`이 true면 도감 슬롯 진행바가 차서 카테고리를 열 수 있습니다.
- `dex.dexCount`는 가진 종 수입니다. 포획에 성공하면 그 종이 도감에서 `SEEN` → `OWNED`가 되고, 실패해도 `SEEN`으로 남습니다.
- "그만" 버튼은 서버를 부르지 않습니다.

| 검사 | 실패 시 |
| --- | --- |
| `businessDate`가 서버 오늘 날짜와 다름 | 409 `BUSINESS_DATE_CHANGED` |
| 본인의 탐색이 아님 | 403 `FORBIDDEN` |
| 등장(`ENCOUNTER`)이 아니거나, 이미 처리됐거나, 다시 탐색·날짜 변경으로 사라진 등장 | 409 `ENCOUNTER_CLOSED` |
| 성실볼 0개 | 422 `NO_BALL` (앱은 볼 사기 버튼을 보여줌) |

## 6. 통계

### GET /stats — 통계 조회

```json
// 응답 200
{
  "attendance": {
    "currentStreak": 5, "longestStreak": 12,
    "last14Days": [ { "date": "2026-09-29", "attended": true } ]
  },
  "sincerity": {
    "last7Days": [ { "date": "2026-10-06", "dayOfWeek": "MON", "rate": 80 } ],
    "averageRate": 72
  },
  "categories": [
    { "code": "ex", "name": "운동", "opened": true, "level": 4, "maxLevel": 20,
      "expInLevel": 3, "expToNextLevel": 40, "levelUpGold": 20 },
    { "code": "md", "name": "명상", "opened": false }
  ]
}
```

- `last14Days`는 오래된 날부터 14개, `last7Days`는 7개입니다.
- 성실도 그래프의 `rate`는 다시 체크한 최신 `overallRate`입니다. 체크인하지 않은 날은 null. `averageRate`는 null을 뺀 날들의 평균입니다.
- 카테고리 레벨은 보상 기준이라 다시 체크해도 바뀌지 않습니다. 최대 레벨이면 `expToNextLevel`은 null입니다. 잠긴 카테고리는 레벨 필드가 없습니다.

## 7. 도감

**종 상태**

| 상태 | 뜻 | 도감 표시 |
| --- | --- | --- |
| `OWNED` | 잡았거나 스타터로 받은 종 | 이미지·이름·레벨 |
| `SEEN` | 탐색에서 등장했지만 아직 잡지 못한 종 | 이미지·이름 (레벨 없음) |
| `UNKNOWN` | 본 적 없는 종 | 실루엣·번호·해금 정보 |

- 본 종은 등장한 순간 등록되며, 한 번 등록되면 사라지지 않습니다(5장 탐색의 "도감 등록" 참고).
- 카테고리 열기 진행바(`dexCount`)는 **가진 종(`OWNED`)만** 셉니다. 본 종은 세지 않습니다.

### GET /dex — 도감 요약

```json
// 응답 200
{
  "slot": { "dexCount": 7, "nextMilestone": 10, "availableTickets": 1 },
  "categories": [
    { "code": "ex", "name": "운동", "opened": true, "ownedCount": 4, "seenCount": 6, "totalCount": 7 }
  ]
}
```

- 슬롯 진행바는 `dexCount / nextMilestone`이며, `dexCount`는 가진 종 수입니다. `availableTickets`가 1 이상이면 열 수 있는 카테고리가 있습니다.
- `seenCount`는 본 종 수이며 가진 종을 포함합니다(`ownedCount ≤ seenCount ≤ totalCount`).

### GET /dex/categories/{code} — 카테고리 몬스터 목록

```json
// 응답 200
{
  "code": "ex", "ownedCount": 4, "seenCount": 6, "totalCount": 7,
  "monsters": [
    { "dexNo": 1, "status": "OWNED", "speciesId": 1, "name": "몬스터 이름",
      "imageUrl": "https://...", "level": 7 },
    { "dexNo": 2, "status": "SEEN", "speciesId": 2, "name": "몬스터 이름",
      "imageUrl": "https://..." },
    { "dexNo": 7, "status": "UNKNOWN", "silhouetteUrl": "https://...",
      "unlockLevel": 18, "unlocked": false }
  ]
}
```

- `OWNED`·`SEEN`은 이미지를 그대로 보여줍니다. `SEEN`에는 레벨이 없습니다.
- `UNKNOWN`은 이름·`speciesId`·원본 이미지를 보내지 않고, 실루엣 이미지(`silhouetteUrl`)와 해금 정보만 보냅니다. 원본 이미지 주소를 응답에 넣으면 앱을 거치지 않고 볼 수 있으므로 실루엣은 서버가 별도 파일로 제공합니다.
- `unlocked`가 false면 앱은 "카테고리 Lv.{unlockLevel}에 등장"을 보여줄 수 있습니다.

### GET /dex/species/{speciesId} — 도감 몬스터 상세

```json
// 응답 200: 가진 종
{
  "dexNo": 1, "status": "OWNED", "name": "몬스터 이름", "imageUrl": "https://...",
  "element": "불꽃", "rarity": 3,
  "level": 7, "stage": 0, "description": "설명 문구"
}
// 응답 200: 본 종
{
  "dexNo": 2, "status": "SEEN", "name": "몬스터 이름", "imageUrl": "https://...",
  "element": "불꽃", "rarity": 1,
  "level": null, "stage": null, "description": "설명 문구"
}
```

- `SEEN`인 종은 레벨·진화 단계가 null입니다.
- 본 적 없는 종이면 404 `NOT_DISCOVERED`. `UNKNOWN` 종은 목록 응답에 `speciesId`가 없으므로 앱이 이 요청을 부를 일은 없습니다.
- `element`는 카테고리 속성이며, "타입"으로 표시합니다.

### POST /categories/{code}/unlock — 카테고리 열기

헤더 `Idempotency-Key` 필요.

```json
// 응답 201
{
  "categoryCode": "md",
  "starter": { "userMonsterId": 20, "name": "몬스터 이름", "imageUrl": "https://...", "location": "BAG" },
  "availableTickets": 0
}
```

| 검사 | 실패 시 |
| --- | --- |
| 열 수 있는 슬롯 없음 | 422 `NO_TICKET` |
| 이미 연 카테고리 | 409 `ALREADY_OPENED` |

새 카테고리는 Lv.1부터 시작하며, 초기 몬스터는 필드가 5마리면 가방으로 갑니다. 카테고리를 연 뒤 앱은 그 카테고리의 습관 추가(`POST /habits`)로 안내합니다.

## 8. 목표

목표 기간은 **등록한 날(업무 날짜)부터** 주간 7일, 월간 30일입니다 (v5 보충 10-28). 예: 10-23에 등록한 주간 목표는 10-23 \~ 10-29, 월간 목표는 10-23 \~ 11-21. 기간 마지막 날의 다음 날부터 "지난 목표"입니다.

칸은 기간이 남은 목표가 차지합니다 (진행 중 · 완료 모두). 기간이 끝나거나 삭제하면 칸이 빕니다.

### GET /goals — 목표 목록

```json
// 응답 200
{
  "weekly": {
    "slotsTotal": 3, "slotsUsed": 1, "rewardGold": 40,
    "goals": [ { "goalId": 200, "title": "헬스장 3번 가기", "detail": null, "status": "ACTIVE",
                 "periodStart": "2026-10-23", "periodEnd": "2026-10-29" } ]
  },
  "monthly": {
    "slotsTotal": 1, "slotsUsed": 0, "rewardGold": 150,
    "goals": []
  }
}
```

기간이 남은 목표만 돌려줍니다 (`periodEnd` ≥ 오늘). 삭제한 목표는 빠지고, 완료한 목표는 기간이 끝날 때까지 `COMPLETED`로 남습니다. `slotsUsed`는 돌려준 목표 수입니다.

### POST /goals — 목표 등록

```json
// 요청
{ "goalType": "WEEKLY", "title": "헬스장 3번 가기", "detail": "월·수·금" }
// 응답 201
{ "goalId": 201, "goalType": "WEEKLY", "periodStart": "2026-10-23", "periodEnd": "2026-10-29",
  "title": "헬스장 3번 가기", "detail": "월·수·금", "status": "ACTIVE" }
```

제목 1\~50자, 상세 0\~500자. 슬롯이 다 찼으면 422 `GOAL_SLOT_FULL`.

### PATCH /goals/{goalId} — 목표 수정

```json
// 요청: 바꿀 필드만. 상세를 지우려면 "detail": null
{ "title": "헬스장 4번 가기", "detail": null }
// 응답 200: 등록 응답과 같은 모양
```

`title`은 지울 수 없으므로 `null`이면 400. `goalType`은 바꿀 수 없습니다.

### DELETE /goals/{goalId} — 목표 삭제

```json
// 응답 204
```

### POST /goals/{goalId}/complete — 목표 완료

헤더 `Idempotency-Key` 필요.

```json
// 응답 200
{ "goalId": 200, "status": "COMPLETED", "goldAwarded": 40, "gold": 507 }
```

- 수정·삭제·완료 모두 완료한 목표에는 409 `GOAL_COMPLETED`. 완료는 되돌릴 수 없습니다.
- 기간이 끝난 목표는 수정·삭제·완료할 수 없으며 409 `GOAL_PERIOD_ENDED`.
- 등록한 날에는 완료할 수 없으며 409 `GOAL_TOO_EARLY` (등록 → 바로 완료로 골드를 버는 것을 막음). 기간 마지막 날까지는 완료할 수 있습니다.

## 9. 습관 타이머 (v6)

시작 · 끝 시각은 **서버 시각**으로 기록한다 (앱 시계를 바꿔도 소용없게). **단위가 '분'인 시간 측정 습관**에 쓸 수 있다 — 지금 시드 기준 운동 시간 · 공부 시간 · 명상 시간 (`measure_type.unit = '분'`이고 `scoring_mode = 'TARGET_RATIO'`인 항목. 새 항목이 생기면 자동으로 포함).

### POST /timers — 시작

헤더 `Idempotency-Key` 필요.
```json
// 요청
{ "businessDate": "2026-10-30", "habitId": 101 }
// 응답 201
{ "timerId": 9, "habitId": 101, "status": "RUNNING", "startedAt": "2026-10-30T19:02:11+09:00", "elapsedSeconds": 0 }
```

### PATCH /timers/{timerId} — 일시정지 · 이어서 · 끝내기

헤더 `Idempotency-Key` 필요.
```json
// 요청
{ "action": "PAUSE" }     // PAUSE | RESUME | STOP
// 응답 200
{ "timerId": 9, "status": "PAUSED", "elapsedSeconds": 1520, "todayMinutes": 25, "endReason": null }
```
- `endReason`: 끝났을 때만 — `USER`(사용자가 끝냄) · `MAX_DURATION`(최대 시간 자동 종료) · `HABIT_STOPPED`(습관을 그만두거나 기간이 끝나서 함께 끝남).
- `STOP`에는 선택 칸 **`focusMinutes`**(0 이상 정수 분)를 보낼 수 있다 — 뽀모도로처럼 앱이 쉬는 시간을 빼고 싶을 때 (D-63). 서버는 **`min(서버가 잰 경과 분, focusMinutes)`**를 기록한다. 없으면 서버 경과 그대로. 앱은 줄이는 쪽으로만 바꿀 수 있으므로 조작으로 얻을 것이 없다. 음수면 400.
  ```json
  { "action": "STOP", "focusMinutes": 50 }
  ```

### GET /timers/today
```json
{
  "active": [
    { "timerId": 9, "habitId": 101, "status": "RUNNING", "startedAt": "2026-10-30T19:02:11+09:00", "elapsedSeconds": 1520 },
    { "timerId": 7, "habitId": 100, "status": "PAUSED", "startedAt": "2026-10-29T22:40:00+09:00", "elapsedSeconds": 600 }
  ],
  "habits": [ { "habitId": 101, "todayMinutes": 70, "sessions": 3 } ]
}
```
- `active`: 끝나지 않은 타이머 전부 (어제 이전에 시작한 것도). RUNNING은 많아야 하나.
- `habits`: 오늘 기록된(오늘 끝난) 타이머의 습관별 합계 · 개수.

**규칙**
- **타이머는 습관마다 하나** (끝나지 않은 것 = RUNNING · PAUSED). 그중 **실제로 도는(RUNNING) 것은 한 사용자에 하나**뿐이다 — 일시정지한 타이머는 여러 습관에 남아 있어도 된다.
  - 같은 습관에 끝나지 않은 타이머가 있으면 새로 시작하지 않고 그 타이머를 이어서 쓴다 → `POST` 409 `TIMER_ALREADY_RUNNING` (추가 칸 `timerId` = 그 습관의 타이머).
  - 다른 습관 타이머가 도는 중에 시작(`POST`)하거나 이어서(`RESUME`) 재면 409 `TIMER_ALREADY_RUNNING` (추가 칸 `timerId` = 도는 타이머). 앱은 "○○ 타이머를 멈추고 시작할까요?"를 묻고, 그 타이머를 `PAUSE`한 뒤 다시 요청한다.
  - 이유: 일시정지하고 잊은 타이머가 다른 습관 타이머를 막지 않게 하고, 두 타이머를 동시에 돌려 같은 시간을 두 습관에 확인받는 것은 막는다.
- 경과 시간 = 끝(또는 지금) − 시작 − 일시정지한 시간. 분은 내림.
- 한 번에 최대 `timer_max_minutes`(기본 240분). **최대 시간은 일시정지를 뺀 경과 시간 기준**이다 — 경과가 240분에 닿으면 자동으로 끝낸 것으로 본다 (켜 두고 자는 것 방지, `endReason: MAX_DURATION`). 일시정지 중에는 경과가 늘지 않으므로 최대 시간에 걸리지 않는다.
- **00시에 끝나지 않는다. 기록은 끝난 날 하나에만 들어간다.** 타이머의 업무 날짜는 끝날 때 정한다 = 끝난 시각(`ended_at`)의 업무 날짜. 00시에서 나누지 않는다.
  - 예: 23:30에 시작 → 00:12에 끝냄 = **42분 전부 다음 날** 기록.
  - 일시정지한 채 날을 넘겨도 같다 — 나중에 끝내면 끝낸 날 기록.
  - 최대 시간 자동 종료가 00시 뒤에 걸리면 (예: 22:00 시작 → 02:00) 그 날(다음 날) 기록.
- **습관을 그만두거나 기간이 끝나면** (`STOPPED` · `ENDED`) 그 습관의 끝나지 않은 타이머도 끝낸다 (`endReason: HABIT_STOPPED`). 그때까지 잰 분은 기록으로만 남는다 (그 습관은 더 체크인 대상이 아님).
  - 그만두기: `POST /habits/{id}/stop` 처리 안에서 그 시각에 끝낸다.
  - 기간 끝: 날이 바뀐 뒤 아래 자동 정리에서 끝낸다. 끝난 시각 = 기간이 끝난 00시.
- 자동 종료는 스케줄러 없이 **다음 요청 때 서버가 처리**한다: 타이머 · 체크인 API가 불리면 먼저 그 사용자의 끝나지 않은 타이머 중 아래에 해당하는 것을 끝낸 뒤 처리한다. 끝난 시각은 처리한 시각이 아니라 **실제로 끝나야 했던 시각**으로 적는다.
  - 경과가 최대 시간에 닿은 것 → `MAX_DURATION`, 끝난 시각 = 시작 + 240분 + 그때까지 일시정지한 시간
  - 습관 기간이 끝난(`ENDED`) 것 → `HABIT_STOPPED`, 끝난 시각 = 기간이 끝난 00시
- 1분 미만은 0분으로 기록된다 (합계에 영향 없음).
- 체크인 제출 뒤에 잰 시간은 그날 "다시 체크"로만 반영된다 (보상은 첫 제출 기준). 그래서 타이머를 먼저 써야 확인 보너스를 받는다 → 앱은 체크인 화면에 "타이머로 재면 경험치 ×1.2 · 최대 25점" 안내를 둔다.
- 습관이 그만둔(`STOPPED`) 상태면 시작할 수 없다 (404와 같은 취급이 아니라 422 `NOT_TIMER_HABIT`).

| 검사 | 실패 시 |
| --- | --- |
| 본인 습관이 아님 · 없는 타이머 | 404 |
| 분 단위 시간 습관이 아님 · 그만둔 습관 | 422 `NOT_TIMER_HABIT` |
| 같은 습관에 끝나지 않은 타이머가 있음 (시작) · 다른 습관 타이머가 도는 중 (시작 · 이어서) | 409 `TIMER_ALREADY_RUNNING` — 오류 응답에 추가 칸 `timerId` (그 타이머) |
| 끝난 타이머에 PAUSE · RESUME · STOP | 409 `TIMER_NOT_RUNNING` — 오류 응답에 추가 칸 `endReason` |
| 시작 때 `businessDate`가 오늘과 다름 | 409 `BUSINESS_DATE_CHANGED` |

> 오류 응답에는 선택 필드 `timerId` · `endReason`이 붙습니다 (값이 있을 때만, 공통 규칙).

## 에러 코드 목록

| 상태 | 코드 | 상황 |
| --- | --- | --- |
| 400 | `INVALID_REQUEST` | 값 형식·범위가 틀림 (필드별 이유는 `errors`) |
| 401 | `INVALID_TOKEN` | 토큰 없음·형식 오류·폐기됨 |
| 401 | `TOKEN_EXPIRED` | 액세스 토큰 만료 (재발급 시도) |
| 401 | `INVALID_CREDENTIALS` | 이메일·비밀번호 불일치 |
| 401 | `INVALID_PROVIDER_TOKEN` | 소셜 제공자 토큰 검증 실패 |
| 403 | `FORBIDDEN` | 본인 데이터가 아님 |
| 403 | `ONBOARDING_REQUIRED` | 온보딩 전 사용자 |
| 404 | `NOT_FOUND` | 대상 없음 (일반) |
| 404 | `NOT_DISCOVERED` | 도감에서 본 적 없는 종 |
| 404 | `CHECKIN_NOT_FOUND` | 오늘 제출 없이 수정 |
| 409 | `EMAIL_TAKEN` | 이메일 가입으로 이미 가입된 이메일 |
| 409 | `EMAIL_REGISTERED_WITH_OTHER_METHOD` | 다른 가입 방법으로 가입된 이메일 (`provider` 포함) |
| 409 | `ALREADY_ONBOARDED` | 이미 온보딩 완료 |
| 409 | `ALREADY_DONE_TODAY` | 오늘 이미 쓰다듬기·놀아주기 |
| 409 | `ALREADY_SUBMITTED` | 오늘 체크인 이미 제출 |
| 409 | `NO_ACTIVE_HABIT` | 체크인 대상 습관 없음 |
| 409 | `CHECKIN_REQUIRED` | 체크인 전 탐색·대사 요청 |
| 409 | `ENCOUNTER_CLOSED` | 포획할 수 없는 등장 |
| 409 | `BUSINESS_DATE_CHANGED` | 요청의 날짜가 서버 오늘과 다름 |
| 409 | `HABIT_NOT_ENDED` | 기간을 채우지 않은 습관 연장 |
| 409 | `HABIT_ALREADY_STOPPED` | 이미 그만둔 습관 |
| 409 | `ALREADY_OPENED` | 이미 연 카테고리 |
| 409 | `GOAL_COMPLETED` | 완료한 목표 변경 |
| 409 | `GOAL_PERIOD_ENDED` | 기간이 끝난 목표 변경 |
| 409 | `GOAL_TOO_EARLY` | 등록한 날 목표 완료 |
| 409 | `REQUEST_IN_PROGRESS` | 같은 중복 방지 키의 요청 처리 중 |
| 409 | `TIMER_ALREADY_RUNNING` | 같은 습관에 끝나지 않은 타이머가 있음 · 다른 습관 타이머가 도는 중 (`timerId`, v6) |
| 409 | `TIMER_NOT_RUNNING` | 이미 끝난 타이머 (`endReason`, v6) |
| 422 | `IDEMPOTENCY_KEY_REUSED` | 같은 키에 다른 본문 |
| 422 | `NOT_ENOUGH_GOLD` | 골드 부족 |
| 422 | `NO_ITEM` | 물약 없음 |
| 422 | `NO_BALL` | 성실볼 없음 |
| 422 | `MAX_LEVEL` | 몬스터 최대 레벨 |
| 422 | `FIELD_LIMIT` | 필드 몬스터 수 제한 |
| 422 | `NO_EXPLORE_LEFT` | 탐색 기회 없음 |
| 422 | `NO_TICKET` | 카테고리 해금권 없음 |
| 422 | `CATEGORY_LOCKED` | 열지 않은 카테고리에 습관 추가 |
| 422 | `HABIT_LIMIT` | 습관 5개 초과 |
| 422 | `LAST_HABIT` | 마지막 남은 습관 그만두기 |
| 422 | `GOAL_SLOT_FULL` | 목표 슬롯 초과 |
| 422 | `NOT_TIMER_HABIT` | 분 단위 시간 습관이 아님 · 그만둔 습관 (v6) |
| 429 | `AI_RATE_LIMITED` | 하루 AI 해석 호출 한도 초과 (v6) |

## DB·시드에 반영할 것

**v6 → 스키마 v1.9 · 시드 v1.9 (반영함, 11-04)**
- [x] `habit.habit_checkin`: `evidence` · `rewarded_evidence`(불변, 수정 금지 트리거) · `score_capped`
- [x] `habit.habit_timer` 새로: 습관마다 끝나지 않은 것 1개 · 도는 것은 사용자당 1개(고유 인덱스 2개), 상태-시각 일치 제약, `end_reason` USER · MAX_DURATION · HABIT_STOPPED
- [x] `ai.daily_call_count` 새로: 사용자 · 날짜 1행
- [x] 설정 키 8개: `self_report_max_score` 20 · `exp_coef_ratio` 1.0 · `exp_coef_range` 0.9 · `exp_coef_binary` 0.8 · `exp_coef_verified` 1.2 · `timer_max_minutes` 240 · `ai_daily_call_limit` 60 · `ai_min_confidence` 0.6
- 이미 만든 DB는 `backend/db/README.md` v1.9의 SQL을 한 번 실행

**v1 → v5**

**설정값 (`config.balance_config`)**
- [ ] `day_boundary_hour`: 4 → **0**
- [ ] `category_max_level`: 7 → **20**
- [ ] `period_completion_rate` **삭제** (채운 날 수 방식으로 대체)
- [ ] `period_reset_days` **삭제** (오래 접속하지 않아도 채운 날 유지)
- [ ] `capture_rate` 유지 (희귀도별 0.8/0.6/0.4)
- [ ] 탐색 가중치 키 추가: 희귀도별 등장 가중치, 안 가진 종 가중치 배수 (시작값은 튜닝 대상)
- [ ] `duplicate_gold`(15) 설명 변경: 가진 종 등장 시 볼 없이 지급
- [ ] `explore_miss_rate`: **0.35** (베타에서 튜닝)

**마스터 데이터**
- [ ] 종 `unlock_level` 분산: 카테고리 7종 기준 1/3/6/9/12/15/18
- [ ] 종마다 실루엣 이미지 주소 추가 (도감 `UNKNOWN` 표시용)

**스키마**
- [ ] **출석 기록 테이블**: 날짜별 출석. 연속 일수(`habit_user.current_streak`)를 체크인 기준에서 출석 기준으로 변경
- [ ] **습관 상태·기간 기록**: `ACTIVE`/`ENDED`/`STOPPED` 상태, 연장마다 기간(시작일·기간 코드·목표값·채운 날 수)과 기간 중 반영 점수 합. 종료일 컬럼은 필요 없음
- [ ] **탐색 결과**: `DUPLICATE` 결과 추가(자동 골드), 포획 결과는 `CAPTURED`/`ESCAPED`
- [ ] **사용자별 종 도감 기록**: 사용자, 종, 처음 본 시각, 처음 잡은 시각(NULL 가능). (사용자, 종) 고유. 처음 잡은 시각이 있으면 `OWNED`, 처음 본 시각만 있으면 `SEEN`, 행이 없으면 `UNKNOWN`
  - `ENCOUNTER` 발생 시 처음 본 시각 기록(이미 있으면 유지)
  - 포획 성공, 스타터 지급(온보딩·카테고리 열기) 시 두 시각을 함께 기록
  - `dexCount`·`ownedCount`는 처음 잡은 시각이 있는 행 수
- [ ] **체크인 대사 저장**: 체크인 `revision`별 대사와 출처(LLM·TEMPLATE)
- [ ] **중복 요청 방지 키 저장**: 사용자, 메서드, 경로, 키, 본문 해시, 처리 상태, 결과(상태 코드·본문), 만료 시각
- [ ] **이메일 고유 제약**: 가입 방법과 관계없이 이메일은 한 계정에만 (소셜 이메일이 없으면 NULL 허용)
- [ ] **차감 처리**: 골드·볼·물약은 조건부 UPDATE 또는 행 잠금. `CHECK(balance >= 0)` 위반은 422로 변환

**화면**
- [ ] 습관 기간 문구를 7일/30일/100일로 맞춤
- [ ] 도감: `OWNED`·`SEEN`은 이미지 그대로, `UNKNOWN`은 실루엣. 본 종과 가진 종을 구분하는 표시(예: 포획 마크) 필요

## 정해야 할 규칙

현재 남은 항목 없음. 탐색 가중치·꽝 확률은 베타에서 튜닝합니다. 검토 후 보류한 항목(이메일 선점, 초반 등장 후보)은 「API 명세 보류 항목」 문서를 봅니다.
