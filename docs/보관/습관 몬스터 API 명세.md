# 습관 몬스터 API 명세

Oct 12, 2026 · @윤서

API 목록 문서의 39개 요청을 HTTP 메서드, 경로, 요청·응답 필드로 풀어 쓴 명세입니다. 필드 이름과 값은 schema.sql v1.6 기준입니다.

## 공통 규칙

- **기본 경로**: `/api/v1`. 아래 경로는 모두 이 뒤에 붙습니다.
- **인증**: `/auth/*`를 뺀 모든 요청은 헤더 `Authorization: Bearer {accessToken}`이 필요합니다. 온보딩을 마치지 않은 사용자는 `/onboarding` 관련 요청만 쓸 수 있습니다.
- **중복 요청 방지 키**: 헤더 `Idempotency-Key: {UUID}`. 클라이언트가 버튼을 누를 때 새로 만들고, 재전송할 때는 같은 값을 보냅니다. 같은 키면 서버는 처음 결과를 그대로 돌려줍니다. 필요한 요청: 아이템 구매, 간식 주기, 체크인 제출·수정, 탐색, 포획.
- **날짜**: 업무 날짜는 `"2026-10-12"` 형식이며 새벽 4시(Asia/Seoul) 경계로 서버가 계산합니다. 시각은 `"2026-10-12T14:35:00+09:00"` 형식입니다.
- **필드 이름**: JSON은 camelCase, 코드값은 DB 값을 그대로 씁니다 (예: `"WEEKLY"`, `"FIELD"`, `"D30"`).
- **성공 응답**: 본문을 그대로 돌려줍니다. 돌려줄 것이 없으면 `204 No Content`.
- **에러 응답**: 아래 형식으로 통일합니다.

```json
{ "code": "NOT_ENOUGH_GOLD", "message": "골드가 부족합니다." }
```

| 상태 코드 | 쓰는 경우 |
| --- | --- |
| 400 | 값 형식·범위가 틀림 (빈 이름, 목표값 0 등) |
| 401 | 토큰 없음·만료 |
| 403 | 본인 데이터가 아님 |
| 404 | 대상 없음 |
| 409 | 현재 상태에서 할 수 없음 (이미 완료한 목표, 오늘 이미 제출 등) |
| 422 | 규칙 위반 (골드 부족, 슬롯 초과, 탐색 기회 없음 등) |

## 한눈에 보기 (39개)

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
| 챗봇 | GET | /checkins/today | 체크인 준비 조회 |
| 챗봇 | POST | /checkins/today | 체크인 제출 (첫 제출) |
| 챗봇 | PUT | /checkins/today | 체크인 수정 (다시 체크) |
| 챗봇 | POST | /checkins/today/dialogue | 체크인 대사 요청 |
| 챗봇 | POST | /explores | 탐색하기·다시 탐색 |
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

API 목록 문서는 40개였는데, 대화 상대 변경이 메인과 챗봇에 두 번 들어가 있어 하나로 합쳤습니다.

## 1. 회원·설정

### POST /auth/signup — 이메일 회원가입

```json
// 요청
{ "email": "user@example.com", "password": "********" }
// 응답 201
{ "accessToken": "eyJ...", "refreshToken": "eyJ...", "onboarded": false }
```

이메일은 소문자로 통일해 중복을 검사합니다. 이미 있으면 409 `EMAIL_TAKEN`.

### POST /auth/login — 이메일 로그인

```json
// 요청
{ "email": "user@example.com", "password": "********" }
// 응답 200
{ "accessToken": "eyJ...", "refreshToken": "eyJ...", "onboarded": true }
```

`onboarded`가 false면 앱은 화면 1로 보냅니다.

### POST /auth/social/{provider} — 소셜 로그인

`provider`: `kakao` | `google` | `apple`

```json
// 요청
{ "providerToken": "제공자가 준 인증 토큰" }
// 응답 200
{ "accessToken": "eyJ...", "refreshToken": "eyJ...", "isNewUser": true, "onboarded": false }
```

### POST /auth/refresh — 토큰 재발급

```json
// 요청
{ "refreshToken": "eyJ..." }
// 응답 200 (리프레시 토큰도 새로 발급하고 이전 것은 폐기)
{ "accessToken": "eyJ...", "refreshToken": "eyJ..." }
```

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

인증 정보·토큰·AI 대화를 지우고 습관명·목표 텍스트를 비웁니다. 이미 탈퇴한 계정이면 409.

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

화면 3에서 고른 카테고리만 넘깁니다.

```json
// 응답 200
[
  {
    "categoryCode": "ex",
    "measureTypes": [
      { "id": 1, "name": "운동 시간", "unit": "분", "scoringMode": "TARGET_RATIO",
        "defaultTarget": 30, "step": 10, "maxValue": 300 }
    ],
    "presets": [
      { "id": 1, "name": "걷기", "measureTypeId": 1, "defaultTarget": 30 }
    ]
  }
]
```

기간 선택지(`D7`, `D30`, `D100`)는 고정값이라 앱에 둡니다.

### POST /onboarding — 온보딩 완료 (일괄 제출)

화면 4의 시작 버튼에서 한 번만 부릅니다. 하나라도 틀리면 아무것도 저장하지 않습니다.

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

대화 상대는 운동 카테고리 몬스터, 운동을 고르지 않았으면 고른 카테고리 중 순서가 가장 앞선 카테고리의 몬스터입니다.

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
  "exploreTotal": 3
}
```

체크인 전에는 `exploreRemaining`, `exploreTotal`이 0입니다.

### GET /me/today — 오늘 요약 조회 (스크롤탭)

오늘의 성실도는 보상 기준(첫 제출 값)입니다.

```json
// 응답 200
{
  "businessDate": "2026-10-12",
  "checkedIn": true,
  "goldEarned": 72,
  "overallRate": 0.8,
  "habits": [
    { "habitId": 100, "name": "걷기", "categoryCode": "ex", "unit": "분",
      "dailyTarget": 30, "rewardedValue": 20, "rewardedScore": 67,
      "dayIndex": 4, "periodDays": 30 }
  ]
}
```

체크인 전이면 `rewardedValue`, `rewardedScore`가 null입니다.

### GET /monsters?location=FIELD — 내 몬스터 목록

`location`: `FIELD`(메인 필드) | `BAG`(가방 몬스터 탭) | 생략하면 전체(챗봇 대화 상대 선택).

```json
// 응답 200
[
  { "userMonsterId": 10, "speciesId": 1, "name": "몬스터 이름", "categoryCode": "ex",
    "level": 7, "stage": 1, "imageUrl": "https://...", "displayHeight": 72,
    "facing": "FRONT", "location": "FIELD", "isPartner": true }
]
```

### GET /monsters/{id} — 몬스터 상세 (팝업)

```json
// 응답 200
{
  "userMonsterId": 10, "name": "몬스터 이름", "imageUrl": "https://...",
  "categoryCode": "ex", "stage": 1, "rarity": 2,
  "level": 7, "expInLevel": 40, "expToNextLevel": 125,
  "nextEvolutionLevel": 15,
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
{ "gain": 1, "affection": 7, "affectionTier": "MID" }
```

오늘 같은 행동을 이미 했으면 409 `ALREADY_DONE_TODAY`. 호감도가 최대면 `gain`은 0입니다.

### POST /monsters/{id}/feed — 간식 주기

헤더 `Idempotency-Key` 필요.

```json
// 요청
{ "itemCode": "POTION_S" }   // POTION_S | POTION_M | POTION_L
// 응답 200
{
  "expGained": 50, "levelBefore": 7, "levelAfter": 8,
  "stageBefore": 1, "stageAfter": 1, "evolved": false,
  "remainingQuantity": 2
}
```

물약이 없으면 422 `NO_ITEM`, 최대 레벨이면 422 `MAX_LEVEL`.

### GET /monsters/{id}/line — 말걸기

```json
// 응답 200
{ "affectionTier": "MID", "line": "오늘도 같이 걸을까?" }
```

### PATCH /monsters/{id}/location — 가방에 넣기·꺼내기

```json
// 요청
{ "location": "BAG" }   // BAG 가방에 넣기 | FIELD 꺼내기
// 응답 200
{ "userMonsterId": 10, "location": "BAG", "fieldCount": 3 }
```

필드가 1마리일 때 넣기, 5마리일 때 꺼내기는 422 `FIELD_LIMIT`. 대화 상대를 가방에 넣을 수 있는지는 아래 "발견한 것" 참고.

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
    { "code": "POTION_S", "name": "하급 물약", "shortName": "하급", "price": 30,
      "effectType": "MONSTER_EXP", "effectValue": 50 },
    { "code": "BALL", "name": "성실볼", "shortName": "볼", "price": 50,
      "effectType": "CAPTURE", "effectValue": 1 }
  ]
}
```

가격·효과 값은 예시이며 실제 값은 shop\_item 시드를 따릅니다.

### POST /shop/purchases — 아이템 구매

헤더 `Idempotency-Key` 필요. 챗봇의 "볼 사기"도 이 요청을 씁니다.

```json
// 요청
{ "itemCode": "BALL", "quantity": 1 }
// 응답 201
{ "purchaseId": 300, "totalPrice": 50, "gold": 290, "itemCode": "BALL", "quantity": 3 }
```

응답의 `quantity`는 구매 후 가방에 있는 개수입니다. 골드가 부족하면 422 `NOT_ENOUGH_GOLD`.

### GET /inventory — 가방 아이템 조회

가방의 몬스터 탭은 `GET /monsters`를 씁니다.

```json
// 응답 200
{
  "items": [
    { "itemCode": "POTION_S", "name": "하급 물약", "quantity": 2 },
    { "itemCode": "BALL", "name": "성실볼", "quantity": 3 }
  ]
}
```

## 4. 챗봇 — 체크인·탐색·포획

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
          "options": [10, 20, 30, 40, 60], "previousValue": null }
      ]
    }
  ]
}
```

`options`는 등록한 단위에서 고를 수 있는 값입니다. O·X 습관은 `[1]`(O)이며 "못했어"가 X입니다. 이미 제출했으면 `previousValue`에 마지막 값이 들어 있어 다시 체크할 때 미리 채웁니다.

### POST /checkins/today — 체크인 제출 (첫 제출)

헤더 `Idempotency-Key` 필요.

```json
// 요청: 카테고리 탭의 모든 습관을 한 번에
{
  "answers": [
    { "habitId": 100, "done": true, "value": 20 },
    { "habitId": 101, "done": false }
  ]
}
// 응답 201
{
  "revision": 1,
  "habits": [
    { "habitId": 100, "score": 67, "counted": true },
    { "habitId": 101, "score": 0, "counted": false }
  ],
  "goldEarned": 67,
  "categoryExp": [
    { "categoryCode": "ex", "expGained": 67, "levelBefore": 3, "levelAfter": 4, "levelUpGold": 30 }
  ],
  "periodBonuses": [ { "habitId": 102, "bonus": 120 } ],
  "exploreTotal": 3,
  "gold": 467
}
```

| 검사 | 실패 시 |
| --- | --- |
| 오늘 이미 제출 | 409 `ALREADY_SUBMITTED` (수정은 PUT) |
| 진행 중인 습관을 모두 빠짐없이 보냈는지, 본인 습관인지 | 400 |
| `done: true`면 `value`가 그 습관의 선택지 중 하나 | 400 |

`done: false`는 값 0으로 저장합니다. 반영은 점수 상위 3개(`counted`)입니다.

### PUT /checkins/today — 체크인 수정 (다시 체크)

헤더 `Idempotency-Key` 필요. 요청 본문은 POST와 같습니다.

```json
// 응답 200: 보상은 변하지 않음
{
  "revision": 2,
  "habits": [ { "habitId": 100, "value": 40, "score": 100 } ],
  "totalScore": 100
}
```

오늘 제출이 없으면 404. 어제 이전 기록은 고칠 수 없습니다.

### POST /checkins/today/dialogue — 체크인 대사 요청

제출 응답을 받은 뒤 부릅니다. 대사가 늦어도 제출 결과에는 영향이 없습니다.

```json
// 응답 200
{ "line": "오늘 20분이나 걸었구나!", "source": "LLM" }   // source: LLM | TEMPLATE
```

AI가 실패하거나 3초를 넘기면 템플릿 대사를 `source: "TEMPLATE"`로 돌려줍니다.

### POST /explores — 탐색하기·다시 탐색

헤더 `Idempotency-Key` 필요.

```json
// 응답 201: 등장
{
  "exploreId": 500,
  "result": "ENCOUNTER",
  "species": { "speciesId": 7, "name": "몬스터 이름", "imageUrl": "https://...",
               "categoryCode": "st", "rarity": 2, "owned": false },
  "skippedExploreId": null,
  "exploreRemaining": 2
}
// 응답 201: 꽝
{ "exploreId": 501, "result": "MISS", "species": null, "skippedExploreId": null, "exploreRemaining": 1 }
```

`owned: true`면 이미 가진 종이라 던지면 15G를 받습니다. 직전 등장을 잡지 않고 다시 탐색하면 그 등장은 사라지고 `skippedExploreId`에 번호가 담깁니다.

| 검사 | 실패 시 |
| --- | --- |
| 오늘 체크인 제출 전 | 409 `CHECKIN_REQUIRED` |
| 남은 기회 0 | 422 `NO_EXPLORE_LEFT` |

### POST /explores/{exploreId}/capture — 볼 던지기

헤더 `Idempotency-Key` 필요.

```json
// 응답 200: 새로 잡음
{
  "outcome": "CAPTURED",
  "monster": { "userMonsterId": 15, "name": "몬스터 이름", "imageUrl": "https://...", "location": "FIELD" },
  "goldAwarded": 0,
  "ballCount": 1,
  "gold": 467,
  "dex": { "dexCount": 5, "newSlotAvailable": true }
}
// 응답 200: 이미 가진 종
{ "outcome": "DUPLICATE", "monster": null, "goldAwarded": 15, "ballCount": 1, "gold": 482, "dex": { "dexCount": 5, "newSlotAvailable": false } }
```

필드가 5마리면 새 몬스터는 가방(`BAG`)으로 갑니다. `newSlotAvailable`이 true면 도감 슬롯 진행바가 차서 카테고리를 열 수 있습니다.

| 검사 | 실패 시 |
| --- | --- |
| 본인의 탐색이 아님 | 403 |
| 이미 처리됐거나 다시 탐색으로 사라진 등장 | 409 `ENCOUNTER_CLOSED` |
| 성실볼 0개 | 422 `NO_BALL` (앱은 볼 사기 버튼을 보여줌) |

"그만" 버튼은 서버를 부르지 않습니다.

## 5. 통계

### GET /stats — 통계 조회

```json
// 응답 200
{
  "attendance": {
    "currentStreak": 5, "longestStreak": 12,
    "last14Days": [ { "date": "2026-09-29", "attended": true } ]
  },
  "sincerity": {
    "last7Days": [ { "date": "2026-10-06", "dayOfWeek": "MON", "score": 80 } ],
    "average": 72
  },
  "categories": [
    { "code": "ex", "name": "운동", "opened": true, "level": 4,
      "expInLevel": 40, "expToNextLevel": 125, "levelUpGold": 30 },
    { "code": "md", "name": "마음", "opened": false }
  ]
}
```

- `last14Days`는 오래된 날부터 14개, `last7Days`는 7개입니다.
- 성실도 그래프의 `score`는 다시 체크한 최신 값(`total_score`)입니다. 체크인하지 않은 날은 null.
- 카테고리 레벨은 보상 기준이라 다시 체크해도 바뀌지 않습니다. 잠긴 카테고리는 레벨 필드가 없습니다.

## 6. 도감

### GET /dex — 도감 요약

```json
// 응답 200
{
  "slot": { "dexCount": 7, "nextMilestone": 10, "availableTickets": 1 },
  "categories": [
    { "code": "ex", "name": "운동", "opened": true, "ownedCount": 4, "totalCount": 20 }
  ]
}
```

슬롯 진행바는 `dexCount / nextMilestone`입니다. `availableTickets`가 1 이상이면 열 수 있는 카테고리가 있습니다.

### GET /dex/categories/{code} — 카테고리 몬스터 목록

```json
// 응답 200
{
  "code": "ex", "ownedCount": 4, "totalCount": 20,
  "monsters": [
    { "dexNo": 1, "owned": true, "speciesId": 1, "name": "몬스터 이름",
      "imageUrl": "https://...", "level": 7 },
    { "dexNo": 2, "owned": false }
  ]
}
```

가지지 않은 종은 번호만 보내 "?"로 표시합니다.

### GET /dex/species/{speciesId} — 도감 몬스터 상세

```json
// 응답 200
{
  "dexNo": 1, "name": "몬스터 이름", "imageUrl": "https://...",
  "element": "불꽃", "rarity": 2, "owned": true,
  "level": 7, "stage": 1, "description": "설명 문구"
}
```

가지지 않은 종이면 404 `NOT_DISCOVERED`. `element`는 카테고리 속성이며, "타입"으로 표시합니다.

### POST /categories/{code}/unlock — 카테고리 열기

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

새 카테고리의 초기 몬스터는 필드가 5마리면 가방으로 갑니다.

## 7. 목표

### GET /goals — 목표 목록

```json
// 응답 200
{
  "weekly": {
    "periodStart": "2026-10-12", "slotsTotal": 3, "slotsUsed": 1, "rewardGold": 40,
    "goals": [ { "goalId": 200, "title": "헬스장 3번 가기", "detail": null, "status": "ACTIVE" } ]
  },
  "monthly": {
    "periodStart": "2026-10-01", "slotsTotal": 1, "slotsUsed": 0, "rewardGold": 150,
    "goals": []
  }
}
```

이번 주(월요일 시작)와 이번 달의 목표만 돌려줍니다. 삭제한 목표는 빠지고 완료한 목표는 `COMPLETED`로 남습니다.

### POST /goals — 목표 등록

```json
// 요청
{ "goalType": "WEEKLY", "title": "헬스장 3번 가기", "detail": "월·수·금" }
// 응답 201
{ "goalId": 201, "goalType": "WEEKLY", "periodStart": "2026-10-12",
  "title": "헬스장 3번 가기", "detail": "월·수·금", "status": "ACTIVE" }
```

제목 1\~50자, 상세 0\~500자. 슬롯이 다 찼으면 422 `GOAL_SLOT_FULL`.

### PATCH /goals/{goalId} — 목표 수정

```json
// 요청: 바꿀 필드만
{ "title": "헬스장 4번 가기" }
// 응답 200: 등록 응답과 같은 모양
```

### DELETE /goals/{goalId} — 목표 삭제

```json
// 응답 204
```

### POST /goals/{goalId}/complete — 목표 완료

```json
// 응답 200
{ "goalId": 200, "status": "COMPLETED", "goldAwarded": 40, "gold": 507 }
```

수정·삭제·완료 모두 완료한 목표에는 409 `GOAL_COMPLETED`를 돌려줍니다. 완료는 되돌릴 수 없습니다.

## 명세 작성 중 발견한 것

**DB와 맞지 않는 부분**

- [ ] **출석 기록 테이블이 없음**: 출석은 앱 접속 시 자동으로 확정됐지만, schema.sql v1.6의 연속 일수(`habit_user.current_streak`)는 아직 체크인 기준이고, `users.last_active_date`는 마지막 날짜 하나만 남깁니다. 통계의 최근 14일 칸을 그리려면 날짜별 출석 기록이 필요합니다.
- [ ] **습관 기간 표기**: 화면은 1주/1개월/3개월, schema.sql v1.4부터는 7일/30일/100일(`D7`/`D30`/`D100`)입니다. 명세는 DB 값을 따랐으니 화면 문구를 맞춰야 합니다.
- [ ] **포획 실패(`ESCAPED`)**: 포획은 100%로 확정됐는데 DB에는 실패 결과가 남아 있습니다. 포획률을 설정값으로 두고 지금은 100%로 쓰면 그대로 둬도 됩니다.

**정해야 할 규칙**

- [ ] **"그만" 뒤에 남은 등장**: 몬스터가 등장한 상태에서 그만을 누르면 등장이 처리 전으로 남습니다. 다시 챗봇에 왔을 때 그 몬스터를 다시 보여줄지, 다음 날이 되면 사라지게 할지 정해야 합니다.
- [ ] **대화 상대를 가방에 넣기**: 허용하면 챗봇에는 가방에 있는 몬스터가 나오게 됩니다. 막을지 정해야 합니다.
- [ ] **전부 "못했어"인 날의 탐색**: 보류 중입니다. 지금 명세는 제출만 하면 탐색 3회를 줍니다.
- [ ] **습관 관리 화면**: 추가 예정이라 명세에 없습니다.
