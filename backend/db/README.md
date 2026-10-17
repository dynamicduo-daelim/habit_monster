# DB 공식 설계 메모 — 앱 · 서버에 맞추기

## v1.7 (2026-10-15) — 지금 기준

원본은 저장소 밖 `D:/teamProject/docs/데이터베이스/` (`schema.sql` · `seed.sql` · `schema_later.sql` · `verify.sql` · `verify_later.sql`).
로컬 DB는 `backend/docker-compose.yml`이 이 폴더(`backend/.env`의 `HM_DB_DIR`)의 `schema.sql` → `seed.sql`을 자동 적용해요.
> Docker Desktop은 `C:\Desktop`처럼 공유 범위 밖 폴더를 빈 폴더로 보여요. D: 드라이브나 `C:\Users` 아래에 두세요.

**검증**: 임시 PostgreSQL 16에서 `schema → seed → schema_later → verify → verify_later` **173개 모두 통과** (기본 158 + 나중 블록 15).

**v1.7에서 바뀐 것 (API 명세 v4 반영)**: 업무 날짜 00시 · 이메일은 계정당 하나(`users.email`, `auth_credential.email` 삭제) · 애플 제외 ·
출석 테이블(`habit.attendance`) · 습관 상태 ACTIVE/ENDED/STOPPED + 기간 테이블(`habit.habit_period`, 채운 날 수 기준) ·
탐색 결과 MISS/DUPLICATE/ENCOUNTER + CAPTURED/ESCAPED/SKIPPED/EXPIRED · 체크인 대사(`ai.checkin_dialogue`) ·
**중복 요청 방지 키(`api.idempotency_record`)** · 카테고리 최대 레벨 20 · 꽝 0.35 · 탐색 가중치.

**서버 반영 (10-15)**
- 중복 방지 키를 공식 `api.idempotency_record`로 옮기고, 우리 쪽 제안이던 `server_additions.sql`(`identity.idempotency_record`)은 지웠어요 (D-27).
- 로그인: `users.email` 사용, `auth_credential.email` 제거 (1단계 인증).

**DB에 더할 것 (다음 판에서 결정 — DB · API 명세는 윤서 작성)**
- 도감 "본 종"(API 명세 v5): `monster.dex_entry`에 처음 본 시각 (지금은 잡은 시각만)
- 몬스터 종이 5마리뿐 — 운동 · 식습관 · 수면은 시작 몬스터 1종이라 탐색하면 "가진 종 → 15G"만 나옴 (결정 B5는 아트가 나와야 가능)

---

## v1.5 → v1.6 (10-10, 이전 기록)

공식 스키마(윤서 작성) 기준 메모예요. 원본 파일은 저장소에 넣지 않고 공유 폴더(OneDrive `카카오톡 받은 파일/`)에 둬요.

- 2026-10-08 작성본 **v1.5**: `habit_monster_erd.md`, `seed.sql`, `verify.sql`, `verify_later.sql` (`schema_erd/`)
- 2026-10-10 작성본 **v1.6**: `schema.sql` — 아래 "요청" 두 가지가 반영된 판

## 검증 결과 (2026-10-10, 임시 PostgreSQL 18.4)

| 실행 | 결과 |
|---|---|
| `schema.sql`(v1.6) → `seed.sql`(v1.5) | 오류 없이 적용 |
| → `verify.sql`(v1.5) | **104개 통과, 2개 실패** — 실패한 둘은 v1.6에서 일부러 뒤집은 규칙을 v1.5 기준으로 검사하는 항목 |
| → [`v1.6_extra_verify.sql`](v1.6_extra_verify.sql) (우리가 쓴 추가 검사) | **15개 모두 통과** — 종당 1마리, 중복 포획 = 볼 + 골드 15 + 원장 `DUPLICATE`, 넘기기 = 볼 · 골드 없이 마감, `CONVERTED` · `EXPLORE_GOLD` 없음 |
| `schema.sql` → `seed.sql` → `schema_later.sql`(v1.4 때 받은 것) | 오류 없이 적용 |

실패한 `verify.sql` 두 항목 (스키마 문제가 아니라 검사 쪽이 옛 판):
- "v1.5 같은 종 중복 보유 가능 (BR-54 폐지)" — v1.6은 `uq_user_species`로 막는 게 맞음
- "골드 전환 = 볼 없이 골드 + 원장 EXPLORE_GOLD" — v1.6은 골드 전환이 없음

→ DB 담당에게 **`verify.sql` · `seed.sql` · ERD의 v1.6 판**을 받아야 해요. 그 전까지 `verify.sql`은 2개 실패가 정상이에요.

```
psql -v ON_ERROR_STOP=1 -f schema.sql -f seed.sql -f verify.sql
psql -v ON_ERROR_STOP=1 -f schema.sql -f seed.sql -f backend/db/v1.6_extra_verify.sql
```

DB 담당에게 요청할 것 (2026-10-10 추가):
- **출석 기준이 "앱에 들어온 날"로 바뀌었어요** (결정 D-15). DB의 연속 출석(`habit.habit_user.current_streak` · `longest_streak` · `last_checkin_date`)은 체크인 기준이라, 접속 기준 연속 출석을 저장할 곳이 필요해요. `identity.users.last_active_date`는 마지막 접속일만 있어요. 날짜별 출석 기록(출석부 달력용)도 지금은 없어요.
- **몬스터 종이 5종 → 28종으로 바뀌었어요** (2026-10-15, 결정 D-16). 시드의 종 목록(`monster.species`)을 앱 `frontend/lib/data/catalog.dart`의 `Catalog.species`에 맞춰 주세요 — 종 id · 카테고리 · 희귀도 · 출현 레벨 · 첫 파트너(카테고리마다 1종, 이제 명상 · 절약도 있음). 4종(불씨 원숭이 · 횃불 닭 · 천둥 백조 · 물방울 코알라)은 1차 진화(Lv.10)부터 그림이 바뀌어요. 그림 경로를 DB에 둘지는 함께 정해요. 아래 `v1.6_extra_verify.sql`의 X-9 이름표 "번쩍 병아리"는 옛 종 이름이에요 (species_id 3).
- **도감 등록 시점이 "잡았을 때" → "만났을 때"로 바뀌었어요** (2026-10-15, 결정 D-17). API 명세 v5의 "사용자별 종 도감 기록"(처음 본 시각 · 처음 잡은 시각, `OWNED`/`SEEN`/`UNKNOWN`)과 같은 규칙이에요. 앱은 v5대로 카테고리 칸을 가진 종만으로 세요.
- **API 명세 v4 · v5에 맞춘 것** (D-19): 가진 종은 볼 없이 15G, 꽝 0.35, 전부 "못 했어"면 탐색 1회, 카테고리 최대 Lv.20, 출현 레벨 1/3/6/9/12/15/18 순서. 단, 앱의 종은 카테고리마다 4~6종이라 출현 레벨은 앞에서부터 종 수만큼 썼어요 — 시드도 같게 맞춰 주세요 (`Catalog.species`의 `unlockLevel`). 탐색 가중치 값이 정해지면 알려 주세요.
- **호감도에 "끌어 옮기기"가 생겼어요** (2026-10-15, D-20). 홈 필드에서 몬스터를 끌어 옮기면 몬스터마다 하루 1번 호감도 +1이에요. `POST /monsters/{id}/affection`의 종류에 끌기(예: `DRAG`)를 추가하고, 쓰다듬기 · 놀아주기처럼 "오늘 했는지"를 기록해 주세요. 위치는 저장하지 않아요.

확인할 것:
- v1.6 `schema.sql`의 로그인 제공자 시드에 `APPLE`이 다시 들어 있어요. 앱 · 서버는 애플 로그인을 지원하지 않아요 (결정 D-02). 행이 있어도 서버 동작에는 영향이 없지만, 뺄지 DB 담당과 맞춰요.
- 중복 포획 골드의 원장 사유가 `EXPLORE_GOLD` → `DUPLICATE`로 바뀌었어요. 설정 키 이름은 아직 `convert_gold`예요 (시드가 v1.5).

이 폴더에 있던 변경안(`v1.5_ball_catch.sql`, `v1.5_verify.sql`)은 **지웠어요**. v1.4 위에 덮어 쓰는 우리 쪽 제안이었는데,
공식 v1.5가 "던져서 잡는 볼"을 다른 모양으로 넣어서 더는 맞지 않아요 (git 기록에는 남아 있어요).

## v1.4 → v1.5 무엇이 바뀌었나

| 영역 | v1.4 | v1.5 |
|---|---|---|
| 온보딩 | `users.onboarding_step` (INTRO…DONE) | `users.onboarded_at` 하나. 온보딩 결과는 **마지막에 한 번** 저장 |
| 성실볼 | 탐색 +1회 (`EXPLORE_TICKET`, 하루 2개) | 포획용 (`CAPTURE`). 하루 상한 없음, 탐색 횟수는 늘리지 않음 |
| 탐색 1회 | 바로 결과 `MISS` / `NEW` / `DUPLICATE` | `result` = `MISS`(꽝) / `ENCOUNTER`(등장) → 등장하면 `outcome`을 한 번 정함 |
| 등장 뒤 선택 | — | `CAPTURED`(볼 1개, 개체 생김) · `ESCAPED`(볼 1개, 놓침) · `CONVERTED`(볼 없이 골드 +15) |
| 포획 확률 | — | 희귀도별 `capture_rate` = 1: 0.8 · 2: 0.6 · 3: 0.4 (임시값) |
| 같은 종 | 종당 1마리, 중복은 골드 | **여러 마리 보유 가능** (BR-54 폐지). 골드는 `CONVERTED`를 골랐을 때만 |
| 초기 몬스터 | 1마리 | **연 카테고리마다 1마리** (`starter_grant`), 대화 상대는 1마리 |
| 체크인 | 하루 1번 확정, 수정 불가 | 하루 1행 + **다시 제출 가능** (`checkin_submission`, `revision`). 최신 값만 바뀌고 골드 · 반영 습관은 **첫 확정 값 그대로** |
| 볼 사용 기록 | `monster.ball_use` | 삭제 → `explore_log.consumption_id` |
| 설정 | `duplicate_gold`, `ball_daily_max` | `convert_gold`, `capture_rate` (`ball_daily_max` 삭제) |

그대로인 것: 처리 전 등장은 사용자당 1건(다음 탐색 전에 처리), 체크인을 확정해야 탐색 횟수가 생김, 탐색 풀 = 그날 체크인한 카테고리,
볼 · 물약 소모 멱등 키는 `shop.item_consumption.consumer_key` 한 곳, 완료한 목표는 되돌리거나 지울 수 없음.

## 서버에 반영한 것

- `identity.User`: `onboarding_step` → `onboarded_at`. `PATCH /me/onboarding`은 본문 없이 완료 시각만 찍어요 (여러 번 불러도 처음 시각 유지).
- 로그인 응답의 `onboardingDone`은 그대로라 앱 화면은 바뀌지 않아요.

## 앱과 DB 규칙 맞추기 (2026-10-10 결정)

앱은 서버 없이 `GameState`가 규칙을 계산해요. v1.5와 달랐던 여섯 가지를 이렇게 정했어요.

| | 정한 규칙 | 맞춘 쪽 |
|---|---|---|
| 탐색 | 40% 확률로 아무도 안 나옴 (`explore_miss_rate`, 횟수는 씀) | **앱을 DB에** — 반영함 |
| 볼 던지기 | 희귀도별 포획 확률 0.8 / 0.6 / 0.4 (`capture_rate`) | **앱을 DB에** — 반영함 |
| 체크인 | 확정 뒤에도 다시 제출 가능. 기록만 바뀌고 보상은 첫 확정 그대로 | **앱을 DB에** — 반영함 (챗봇 "다시 체크") |
| 초기 몬스터 | 연 카테고리마다 1마리 (그림 없는 명상 · 절약은 아직 없음) | **앱을 DB에** — 반영함 |
| 이미 가진 종을 잡으면 | 볼은 쓰고, 몬스터는 늘지 않고 골드 +15 (종당 1마리) | **DB를 앱에** — v1.6에 반영됨 (`DUPLICATE`, `uq_user_species`) |
| 던지지 않을 때 | 보상 없이 넘김 ("다시 탐색" · "그만") | **DB를 앱에** — v1.6에 반영됨 (`SKIPPED`, `CONVERTED` 삭제) |

앱 코드: `Economy.exploreMissRate` · `Economy.captureRate`, `GameState.explore / throwBall / resubmitCheckin / grantStarter`.

## DB 담당에게 요청했던 변경 — v1.6에 반영됨 (2026-10-10)

아래 두 가지는 앱 규칙을 유지하기로 해서 스키마가 바뀌어야 했어요. **v1.6 `schema.sql`에 그대로 들어왔고**, 위 검증 결과의 추가 검사 15개로 확인했어요. 요청 내용은 기록으로 남겨 둬요.

1. **같은 종은 1마리** (BR-54 되살리기)
   - `monster.user_monster`에 사용자 × 종 유일 제약. `verify.sql`의 "v1.5 같은 종 중복 보유 가능"은 반대로 (막혀야 통과).
2. **`monster.explore_log.outcome` 값 바꾸기**: `CAPTURED` · `ESCAPED` · `CONVERTED` → `CAPTURED` · `ESCAPED` · `DUPLICATE` · `SKIPPED`

   | outcome | 뜻 | 볼(`consumption_id`) | 개체(`user_monster_id`) | 골드(`gold_awarded`) |
   |---|---|---|---|---|
   | `CAPTURED` | 던져서 잡음 (처음 얻는 종) | ○ | ○ | 0 |
   | `ESCAPED` | 던졌는데 도망 | ○ | ✗ | 0 |
   | `DUPLICATE` | 던져서 잡았는데 이미 가진 종 → 골드 | ○ | ✗ | > 0 (`convert_gold` 15) |
   | `SKIPPED` | 던지지 않고 넘김 | ✗ | ✗ | 0 |

   - `CONVERTED`(볼 없이 골드로 전환)는 없애요. 골드는 `DUPLICATE`일 때만 나오고 원장 사유는 지금의 `EXPLORE_GOLD`를 그대로 써요.
   - "처리 전 등장은 1건"은 그대로 두고, 다음 탐색을 시작하거나 탐색을 그만둘 때 남아 있는 등장을 `SKIPPED`로 마감해요.
   - `verify.sql`: "골드 전환 = 볼 없이 골드 + 원장" → "중복 포획 = 볼 소모 + 골드 + 원장", "골드 전환인데 골드 0 불가" → `DUPLICATE` 기준으로, `SKIPPED` 검사 추가.
3. (확인만) `explore_miss_rate` 0.40은 시드에 "확인 필요"로 적혀 있는데, 앱도 0.40으로 맞췄어요. 바뀌면 `Economy.exploreMissRate`도 같이 바꿔요.
