# DB 공식 설계 메모 — 앱 · 서버에 맞추기

## v1.14 (2026-11-26) — 지금 기준 (API 명세 v11 — 월간 배지, D-91)

윤서 요청(11-26)으로 Claude가 썼다. 근거는 `docs/제안/2026-11-26-퀘스트-월간배지.md` · 퀘스트 4단계(`docs/quest/4-월간배지.md`).

**바뀐 것**
- 새 테이블 `quest.user_month`: 사용자 · 월(1일만) 1줄 — `completed_count`(그달 완료 수, 카운터) · `badge_earned_at`(트리거 `tg_user_month_badge_fixed` — NULL → 값 한 번만)
- 선물 출처 `QUEST_MONTHLY` (`source_ref` = `user_month.id`, 성실볼만이라 원장 사유 없음)
- 시드 설정 `quest_monthly_target` 20 · `quest_monthly_ball_reward` 1. 서버는 아직 읽지 않아 `BalanceConfig.NOT_USED_BY_SERVER`에 임시로 (구현 때 `REQUIRED`로)
- `verify.sql` +10 (월간 줄 검사 9 · S-37 설정) · S-1 FK 24쌍 · S-36 출처 3개. `verify_later.sql` L-A5 29쌍

**검증 (11-26)**
- 임시 PostgreSQL 16 새 DB **239개 모두 통과** (229 + 새 10) · v1.13 DB(`HEAD`의 schema · seed)에 `migrate-v1.14.sql` 두 번 → 239개 통과

**이미 만든 DB에 적용** — `backend/db/migrate-v1.14.sql`을 한 번 (v1.13 적용 뒤, 두 번 실행해도 안전). **기존 데이터는 바꾸지 않는다** — 이번 달 줄은 새 서버가 처음 쓸 때 그달 기존 완료 수로 만든다. **새 서버 배포보다 먼저** (새 서버는 새 설정 키가 없으면 뜨지 않음).

## v1.13 (2026-11-26) — (API 명세 v10 — 선물함, D-89)

윤서 요청(11-26)으로 Claude가 썼다. 근거는 `docs/제안/2026-11-26-선물함.md` · 퀘스트 3.5단계(`docs/quest/3.5-선물함.md`).

**바뀐 것** — 시드 변경 없음
- 새 스키마 `gift`: `gift.gift_source`(출처 코드 `QUEST_DAILY` · `QUEST_WEEKLY` — 원장 사유처럼 schema.sql에) · `gift.gift`(선물 1줄 — `UNIQUE(source_code, source_ref)` · 빈 선물 금지 · 아이템 코드와 개수는 같이)
- 트리거 `tg_gift_fixed`: 만든 뒤 내용 수정 금지 · `claimed_at`은 NULL → 값 한 번만
- 원장 `QUEST_*`의 `ref_id` = `gift.gift.id` (전: `user_quest.id`) — 퀘스트 골드는 선물을 받을 때 적립
- 잠금 순서 맨 앞에 gift(받기만), 퀘스트 경로는 gift에 새 행만 (원칙 3-1)
- 권한: app_core 스키마 목록에 `gift`
- `verify.sql`: S-1 FK 23쌍(+ `gift.gift` → `identity.users` · `shop.shop_item`) · S-12 가방 대사에 받은 선물 · v1.11 · v1.12 검사의 "원장 적립"을 선물 검사로 옮김(v1.11 "같은 퀘스트 골드 두 번" 1개 뺌) · 선물 검사 14개 · S-12b · S-33 ~ S-36 (순증 18). `verify_later.sql` L-A5 28쌍

**검증 (11-26)**
- 임시 PostgreSQL 16 새 DB(`schema → seed → schema_later → verify → verify_later`) **229개 모두 통과** (211 + 새 18)
- v1.12 DB(`HEAD`의 schema · seed)에 `migrate-v1.13.sql` **두 번** → `schema_later` → 새 `verify` · `verify_later` 229개 통과
- 막는 확인: v1.12 DB에 옛 방식 `QUEST_DAILY` 원장 줄 1개를 넣고 실행 → "옛 방식 퀘스트 골드 원장 줄 1건"으로 멈추고 아무것도 남지 않음
- 처음 시도에서 S-12b가 FAIL — 볼 선물을 시험했는데, 앞쪽 포획 검사가 산 적 없는 볼 2개를 쓴 기록을 남겨(가방 행이 없어서 S-12가 그동안 안 봤음) 대사가 안 맞았다. 시험 아이템을 물약으로 바꿔 해결 (스키마 문제 아님)
- 서버 테스트 237개 통과 (서버 코드는 그대로, `.\gradlew.bat test --rerun` — DB 파일만 바뀌면 Gradle이 `UP-TO-DATE`로 건너뛰므로 `--rerun` 필요)
- 로컬 Docker DB의 `QUEST_*` 원장 줄 0건 (11-26 확인) → 마이그레이션이 멈추지 않는다. Supabase는 아직 안 셈

**이미 만든 DB에 적용** — `backend/db/migrate-v1.13.sql` (v1.12 적용 뒤, 두 번 실행해도 안전). 끝의 확인 조회는 한 줄. **새 서버 배포 직전에 한 번 더** 실행한다 (아래).

**옛 방식 퀘스트 골드 옮기기 (11-26 고침)**
- 처음 판은 옛 방식 원장 줄(`QUEST_*`, ref = user_quest.id)이 있으면 **멈추기만** 했다. Supabase에서 실행하니 "옛 방식 퀘스트 골드 원장 줄 4건"으로 멈춤 — 배포된 서버(2 · 3단계 코드)가 퀘스트 골드를 4번 지급한 기록. 로컬 DB는 0건이라 몰랐다
- 왜 그대로 두면 안 되나: 새 서버는 선물을 받을 때 `(QUEST_DAILY, 선물 id)` 원장 줄이 이미 있으면 "이미 지급됨"으로 보고 건너뛴다(`WalletRepository.ledgerExists`). 옛 줄 ref "2"(user_quest 2)가 있으면 나중에 생기는 **선물 2번은 골드 없이 받음 처리**된다
- 고친 방법: 옛 줄마다 **이미 받은 선물**을 만들고 **선물 id = 옛 ref_id(user_quest.id)**로 직접 넣는다(`OVERRIDING SYSTEM VALUE`). 원장 · 잔액은 손대지 않고도 "ref_id = 선물 id"가 맞게 된다. 그다음 선물 번호표를 가장 큰 id 뒤로(`setval`). 짝이 안 맞는 줄이 남으면 그때 멈춘다
- 비교한 방법: 원장 ref_id를 새 선물 id로 고쳐 쓰기(원장은 기록이라 고치지 않는 원칙과 맞지 않음) · 옛 줄을 지우고 다시 지급(잔액 · 원장이 바뀜) · 선물 번호를 큰 수(예: 1,000,000)부터 시작(옛 줄은 선물과 짝이 없어 S-34 같은 대사 검사가 깨짐)
- 시험: 옛 방식 줄 4개(일일 3 · 주간 1, 중간에 미완료 퀘스트)를 넣은 v1.12 DB에 두 번 실행 → 선물 4개(id 1 · 2 · 4 · 5, 받음) · 두 번째는 변화 없음 · 다음 새 선물 id 6 · 잔액 = 원장 합 10 그대로. 빈 v1.12 DB 경로도 다시 229개 통과
- **새 서버 배포 직전에 한 번 더** 실행: 그사이 옛 서버가 지급한 줄도 옮겨야 새 선물 번호와 겹치지 않는다

## v1.12 (2026-11-25) — (API 명세 v9 — 주간 퀘스트, D-88)

윤서 요청(11-25)으로 Claude가 썼다. 근거는 `docs/제안/2026-11-25-퀘스트-주간.md` · 퀘스트 3단계.

**바뀐 것** — 테이블 변경 없음
- 원장 사유 `QUEST_WEEKLY` (`ref_id` = `user_quest.id`)
- 시드: 주간 퀘스트 3개 (`WEEKLY_ATTEND` 4일 · `WEEKLY_GOOD_DAYS` 2일 · `WEEKLY_CATEGORIES` 3곳, 각 5G) · 설정 키 `quest_weekly_rate_threshold` 80
- `verify.sql` +2 (주간 행 + `QUEST_WEEKLY` 적립 · S-32 시드 · 설정)

**검증 (11-25)**
- 임시 PostgreSQL 16 새 DB **211개 모두 통과** (209 + 새 2) · v1.11 DB에 `migrate-v1.12.sql` 두 번 → 211개 통과
- 서버 테스트 237개 통과

**이미 만든 DB에 적용** — `backend/db/migrate-v1.12.sql`을 한 번 (v1.11 적용 뒤, 두 번 실행해도 안전). 끝의 확인 조회는 한 줄로 모았다 (Supabase 편집기는 마지막 결과만 보여 줌). **새 서버 배포보다 먼저**.

## v1.11 (2026-11-25) — (API 명세 v8 — 퀘스트 기반 + 일일 퀘스트, D-83 · D-85 · D-87)

윤서 요청(11-25)으로 Claude가 썼다. 근거는 `docs/제안/2026-11-25-퀘스트-기반-일일.md` · 퀘스트 2단계(`docs/quest/2-기반-일일퀘스트.md`).

**바뀐 것**
- `quest` 스키마 새로 (권한 반복문에도 추가): `quest.quest_def`(퀘스트 마스터 — 종류 · 제목 · 목표 횟수 · 보상) · `quest.user_quest`(사용자 · 기간 시작일 · 퀘스트 1행 — 유니크, 진행도 ≤ 목표, `DONE` ↔ 완료 시각). 잠금(시간 습관 없음 등)은 저장하지 않고 조회 때 계산
- 원장 사유 `QUEST_DAILY` (`ref_id` = `user_quest.id`)
- 시드: 일일 퀘스트 4개(`DAILY_CHECKIN` 3G · `DAILY_PET` · `DAILY_TIMER` · `DAILY_TALK` 1G) · 설정 키 `quest_enabled`
- 사용자 잠금 순서 끝에 `quest` — `… → wallet → quest` (D-87)
- `verify.sql` +9 (S-1 허용 FK에 `quest.user_quest → identity.users`, MVP 21쌍) · `verify_later.sql` L-A5 25 → 26쌍

**검증 (11-25)**
- 임시 PostgreSQL 16에서 새 DB `schema → seed → schema_later → verify → verify_later` **209개 모두 통과** (200 + 새 9)
- v1.10 스키마 · 시드(`HEAD`)로 만든 DB에 `migrate-v1.11.sql`을 **두 번** 실행 → `schema_later` → 새 `verify` · `verify_later` 209개 통과
- 서버 테스트 218개 통과 (`quest_enabled`는 구현 전이라 `BalanceConfig.NOT_USED_BY_SERVER`에 둠)

**이미 만든 DB에 적용** — 로컬 Docker DB · Supabase 둘 다 `backend/db/migrate-v1.11.sql`을 한 번 (v1.10 적용 뒤, 두 번 실행해도 안전). **새 서버 배포보다 먼저**. 권한(`app_core`)은 그 역할이 있는 DB에서만 준다.

## v1.10 (2026-11-25) — (API 명세 v7 — 필드 끌기 호감도 DRAG, D-46 · D-86)

윤서 요청(11-25)으로 Claude가 썼다. 근거는 `docs/제안/2026-11-25-DRAG-호감도.md` · 퀘스트 1단계(`docs/quest/1-DRAG.md`).

**바뀐 것**
- `monster.affection_action.action_type`에 `DRAG` (몬스터마다 하루 1회 — 기존 기본 키가 막음). 간식 `FEED`는 이 판에 넣지 않음
- 시드 설정 키 `affection_drag_gain` 1
- `verify.sql` 3개 (DRAG 1회 · 같은 날 2회 불가 · S-29 설정값)

**검증 (11-25)**
- 임시 PostgreSQL 16에서 `schema → seed → schema_later → verify → verify_later` **200개 모두 통과** (197 + 새 3)
- **v1.9 스키마 · 시드로 만든 DB에 `migrate-v1.10.sql`을 두 번 실행** → `schema_later` → 새 `verify` · `verify_later` 200개 통과. (`schema_later`를 마이그레이션보다 먼저 적용하면 L-B1 "도입 시점 값 = 이력 출발점"이 1건 차이로 FAIL — 마이그레이션이 넣은 키가 출발점 이후라서. 실제 DB에는 `schema_later`가 없다)
- 서버 테스트 215개 통과 (새 키는 구현 전이라 `BalanceConfig.NOT_USED_BY_SERVER`에 둠) → 서버 구현(11-25)에서 `REQUIRED`로 옮김, 217개 통과

**이미 만든 DB에 적용** — 로컬 Docker DB, 배포한 Supabase DB 둘 다 `backend/db/migrate-v1.10.sql`을 한 번 실행 (데이터는 그대로, 두 번 실행해도 안전). **서버 배포보다 먼저** (서버 구현 뒤에는 키가 없으면 서버가 뜨지 않는다). 실행 전에 제약 이름이 `affection_action_action_type_check`인지 확인.

## v1.9 (2026-11-04) — (API 명세 v6 — AI 챗봇 체크인 · 습관 타이머, D-62 · D-63)

윤서 요청(11-02)으로 Claude가 썼다. 근거는 `docs/제안/2026-10-30-AI챗봇-DB변경.md` 3차 검토본.

**바뀐 것**
- `habit.habit_checkin`: `evidence`(최신 근거) · `rewarded_evidence`(첫 확정 근거 — 수정 금지 트리거에 추가) · `score_capped`. 기존 행은 `SHORT` · `false` = 지금 보상과 같음
- `habit.habit_timer` 새로: 분 단위 시간 습관의 서버 타이머. 고유 인덱스 2개 — `uq_habit_timer_active (habit_id)` 끝나지 않은 것 · `uq_habit_timer_running (user_id)` 도는 것. `business_date`는 끝날 때 끝난 날로, `end_reason` USER · MAX_DURATION · HABIT_STOPPED (00시에 끊지 않음)
- `ai.daily_call_count` 새로: AI 해석 호출 수 (한 문장으로 올리기 + 한도 검사 — `schema.sql` 주석)
- 시드 설정 키 8개: `self_report_max_score` · `exp_coef_ratio` · `exp_coef_range` · `exp_coef_binary` · `exp_coef_verified` · `timer_max_minutes` · `ai_daily_call_limit` · `ai_min_confidence`
- `verify.sql` 24개 · `verify_later.sql` 스키마 간 FK 수 24 → 25
- 헬스(`habit.health_daily`)는 다음 판

**검증**
- 임시 PostgreSQL 16에서 `schema → seed → schema_later → verify → verify_later` **197개 모두 통과** (173 + 새 24)
- **옛 v1.7 스키마 + v1.8 시드로 만든 DB에 아래 SQL을 두 번 실행**한 뒤 새 `verify.sql` · `verify_later.sql` → 197개 통과 (두 번 돌려도 오류 없음 = 다시 실행해도 안전)
- 서버 테스트(새 schema · seed로 컨테이너): `BalanceConfigTest` · `ServerApplicationTests` 통과 (새 키는 구현 전이라 `BalanceConfig.NOT_USED_BY_SERVER`에 둠)

**이미 만든 DB에 적용** — 로컬 Docker DB, **배포한 Supabase DB 둘 다** `backend/db/migrate-v1.9.sql`(아래와 같은 내용)을 한 번 실행 (데이터는 그대로). 새로 만드는 DB(서버 테스트 · `docker compose down -v` 뒤)는 자동.
> Supabase: SQL 편집기에 아래를 붙여 넣고 실행. `app_core` · `app_ai` 역할이 없으면 5) 두 줄에서 멈추니, 그때는 그 두 줄만 빼고 실행 (지금 서버는 DB 비밀번호 계정으로 접속해서 역할 권한을 쓰지 않음 — 배포 기획서 4장 [확인 필요])

```sql
-- v1.7/v1.8 → v1.9 (이미 만든 DB용, 데이터는 그대로). 한 트랜잭션으로 실행.
BEGIN;

-- 1) 체크인 근거 · 점수 상한 (기존 행은 SHORT · false = 지금 보상과 같음)
ALTER TABLE habit.habit_checkin
  ADD COLUMN IF NOT EXISTS evidence          TEXT    NOT NULL DEFAULT 'SHORT'
      CHECK (evidence IN ('SHORT','DETAILED','VERIFIED')),
  ADD COLUMN IF NOT EXISTS rewarded_evidence TEXT    NOT NULL DEFAULT 'SHORT'
      CHECK (rewarded_evidence IN ('SHORT','DETAILED','VERIFIED')),
  ADD COLUMN IF NOT EXISTS score_capped      BOOLEAN NOT NULL DEFAULT false;

-- 2) 수정 금지 트리거에 rewarded_evidence 추가 (함수만 바꾸면 트리거는 그대로 새 함수를 씀)
CREATE OR REPLACE FUNCTION habit.forbid_reward_change() RETURNS trigger AS $$
BEGIN
  IF TG_TABLE_NAME = 'daily_checkin' THEN
    IF NEW.counted_score IS DISTINCT FROM OLD.counted_score
       OR NEW.confirmed_at IS DISTINCT FROM OLD.confirmed_at
       OR NEW.habit_count IS DISTINCT FROM OLD.habit_count THEN
      RAISE EXCEPTION 'daily_checkin %: reward fields are fixed at first confirmation', OLD.id
        USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    IF NEW.is_counted     IS DISTINCT FROM OLD.is_counted
       OR NEW.is_filled      IS DISTINCT FROM OLD.is_filled
       OR NEW.rewarded_score IS DISTINCT FROM OLD.rewarded_score
       OR NEW.rewarded_value IS DISTINCT FROM OLD.rewarded_value
       OR NEW.period_seq     IS DISTINCT FROM OLD.period_seq
       OR NEW.target_snapshot IS DISTINCT FROM OLD.target_snapshot
       OR NEW.rewarded_evidence IS DISTINCT FROM OLD.rewarded_evidence THEN   -- v1.9
      RAISE EXCEPTION 'habit_checkin (%, %): reward fields are fixed at first confirmation',
        OLD.daily_checkin_id, OLD.habit_id USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

-- 3) 습관 타이머
CREATE TABLE IF NOT EXISTS habit.habit_timer (
  id               BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id          BIGINT       NOT NULL REFERENCES habit.habit_user(user_id),
  habit_id         BIGINT       NOT NULL REFERENCES habit.habit(id),
  business_date    DATE         NOT NULL,
  status           TEXT         NOT NULL CHECK (status IN ('RUNNING','PAUSED','STOPPED')),
  started_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  paused_at        TIMESTAMPTZ  NULL,
  paused_seconds   INTEGER      NOT NULL DEFAULT 0 CHECK (paused_seconds >= 0),
  ended_at         TIMESTAMPTZ  NULL,
  end_reason       TEXT         NULL CHECK (end_reason IN ('USER','MAX_DURATION','HABIT_STOPPED')),
  counted_minutes  SMALLINT     NULL CHECK (counted_minutes BETWEEN 0 AND 1440),
  CONSTRAINT ck_timer_end    CHECK ((status = 'STOPPED') = (ended_at IS NOT NULL)),
  CONSTRAINT ck_timer_result CHECK ((status = 'STOPPED') = (counted_minutes IS NOT NULL AND end_reason IS NOT NULL)),
  CONSTRAINT ck_timer_paused CHECK ((status = 'PAUSED') = (paused_at IS NOT NULL)),
  CONSTRAINT ck_timer_order  CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_habit_timer_active  ON habit.habit_timer (habit_id) WHERE status IN ('RUNNING','PAUSED');
CREATE UNIQUE INDEX IF NOT EXISTS uq_habit_timer_running ON habit.habit_timer (user_id)  WHERE status = 'RUNNING';
CREATE INDEX IF NOT EXISTS ix_habit_timer_day ON habit.habit_timer (user_id, business_date);

-- 4) AI 해석 호출 수
CREATE TABLE IF NOT EXISTS ai.daily_call_count (
  user_id     BIGINT       NOT NULL REFERENCES identity.users(id),
  call_date   DATE         NOT NULL,
  call_count  SMALLINT     NOT NULL DEFAULT 0 CHECK (call_count >= 0),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, call_date)
);

-- 5) 권한: 새 테이블에 역할 권한 (ALTER DEFAULT PRIVILEGES는 그걸 건 역할이 만든 테이블에만 적용되므로 직접 준다)
GRANT SELECT, INSERT, UPDATE, DELETE ON habit.habit_timer TO app_core;
GRANT SELECT, INSERT, UPDATE, DELETE ON ai.daily_call_count TO app_ai;

-- 6) 설정 키 8개
INSERT INTO config.balance_config (key, value, description) VALUES
 ('self_report_max_score', '20',  '자기보고(SHORT·DETAILED) 습관 점수 상한. 확인됨(VERIFIED)은 score_max까지 (v1.9)'),
 ('exp_coef_ratio',        '1.0', '카테고리 경험치 계수 — 시간·양(TARGET_RATIO) (v1.9)'),
 ('exp_coef_range',        '0.9', '카테고리 경험치 계수 — 범위(RANGE, 수면) (v1.9)'),
 ('exp_coef_binary',       '0.8', '카테고리 경험치 계수 — O·X(BINARY) (v1.9)'),
 ('exp_coef_verified',     '1.2', '확인된 기록(타이머) 경험치 배수 — 위 계수에 곱하고 습관마다 반올림 (v1.9)'),
 ('timer_max_minutes',     '240', '습관 타이머 한 번 최대 분 — 일시정지 뺀 경과, 닿으면 자동 종료 (v1.9)'),
 ('ai_daily_call_limit',   '60',  '사용자당 하루 AI 해석 호출 한도 (v1.9, 베타에서 조정)'),
 ('ai_min_confidence',     '0.6', '이보다 확신이 낮은 해석은 다시 묻기 (v1.9, 근거 없는 시작값 — 구현 뒤 조정)')
ON CONFLICT (key) DO NOTHING;

COMMIT;
```

## v1.8 (2026-10-17) — 시드만 바뀜, `schema.sql`은 v1.7 그대로

**몬스터를 앱의 새 픽셀 그림 28종으로** (앱 `frontend/lib/data/catalog.dart`에서 그대로 뽑음 — 결정 D-32):
- `monster_species` 28행. **id = 카테고리 순서**: 운동 1 ~ 5 · 공부 6 ~ 9 · 식습관 10 ~ 14 · 명상 15 ~ 18 · 수면 19 ~ 22 · 절약 23 ~ 28
- **스타터 6종** (카테고리 첫 번호): 1 monkey · 6 mouse · 10 turtle · 15 koala · 19 squirrel · 23 redpanda
- `code` = 앱 종 id = 그림 이름 (서버 응답 `imageKey`, D1). 해금 레벨은 카테고리 안 1/3/6/9/12(/15), 도감 번호 = (카테고리 순서 − 1) × 6 + 순번
- 대사 `species_line` 252줄 (28종 × 호감도 3단계 × 3줄), 진화 단계 `monster_form` 84행 (자동 생성)
- `verify.sql`: 검사가 쓰던 종 번호를 새 번호로 (옛 2 → 6 · 3 → 7 · 4 → 10 · 5 → 19), S-2를 "모든 카테고리에 스타터" 검사로
- **검증**: 임시 PostgreSQL 16에서 `schema → seed → schema_later → verify → verify_later` **173개 모두 통과**

## v1.7 (2026-10-15)

원본 위치: 저장소 `docs/데이터베이스/` (`schema.sql` · `seed.sql` · `schema_later.sql` · `verify.sql` · `verify_later.sql`, 10-16에 저장소 밖에서 옮김).
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

**목표 기간 변경 — 반영함 (2026-10-28, 사용자 요청으로 Claude가 직접, D-48)**: 목표 기간을 달력 주 · 달에서 "등록한 날부터 7일 · 30일"로.
`schema.sql`에서 제약 `ck_goal_period_start`(주간 = 월요일 · 월간 = 1일) 삭제, `seed.sql`에 `weekly_goal_days` 7 · `monthly_goal_days` 30, `verify.sql` 검사 2개.
새로 만드는 DB(서버 테스트 · `docker compose down -v` 뒤)에는 자동으로 들어간다. **이미 있는 로컬 DB**에는 아래를 한 번 실행한다 (데이터는 그대로):
```sql
ALTER TABLE goal.goal DROP CONSTRAINT IF EXISTS ck_goal_period_start;
INSERT INTO config.balance_config (key, value, description) VALUES
 ('weekly_goal_days',  '7',  '주간 목표 기간 (등록한 날부터 일수, v1.8 보충 10-28)'),
 ('monthly_goal_days', '30', '월간 목표 기간 (등록한 날부터 일수, v1.8 보충 10-28)')
ON CONFLICT (key) DO NOTHING;
```
(서버는 두 설정 키가 없으면 시작하지 않는다 — `BalanceConfig.REQUIRED`.)

**DB에 더할 것 (다음 판에서 결정 — DB · API 명세는 윤서 작성)**
- 도감 "본 종"(API 명세 v5): `monster.dex_entry`에 처음 본 시각 (지금은 잡은 시각만)
- (해결 — v1.8) ~~몬스터 종이 5마리뿐~~
- **시작 골드 · 성실볼 (10-18 제안, 결정 D-35)**: 앱은 골드 50 · 볼 3개로 시작(D-05)하지만 DB에는 지급 사유 · 설정 키가 없어 서버 모드는 0으로 시작한다. 주려면 다음 판에:
  ```sql
  -- schema.sql: 원장 사유 (열린 집합 — INSERT 한 줄)
  INSERT INTO wallet.ledger_reason (code, direction, description) VALUES ('STARTER_GOLD','CREDIT','온보딩 시작 골드');
  -- seed.sql: 수치
  INSERT INTO config.balance_config (key, value, description) VALUES
   ('starting_gold',  '50', '온보딩 시작 골드 (원장 STARTER_GOLD, ref_id = user_id)'),
   ('starting_balls', '3',  '온보딩 시작 성실볼 (shop.inventory BALL)');
  ```
  볼까지 주면 `verify.sql` S-12(가방 수량 = 구매 합 − 소모 합)가 깨진다 → 둘 중 하나: (1) S-12를 "구매 + 시작 지급 − 소모"로 바꾸고 시작 지급을 기록할 곳(예: 새 `shop.item_grant` 테이블, 또는 `shop.purchase`에 가격 0 허용)을 둔다 (2) 볼은 주지 않고 골드만(볼 값 50G보다 넉넉히) 준다.
  판이 나오면 서버는 두 키를 `BalanceConfig.REQUIRED`에 넣고 `OnboardingService`에서 지급한다.
- **체크인 선택지 수치 (10-19 제안, D-42)**: 선택지 배수 `{0.25, 0.5, 0.75, 1, 1.5, 2}`(B3)와 수면 범위 바깥 칸 수 `2`가 설정 키가 없어 서버 코드(`habit/Scoring.java`) 상수다. 예: `('checkin_option_ratios', '[0.25,0.5,0.75,1,1.5,2]')` · `('checkin_range_extra_steps', '2')`
- **필드 끌기 호감도 DRAG (10-21 제안, D-46)**: 앱의 끌기 호감도(D-20)를 저장하려면 `affection_action.action_type`에 `DRAG`, 설정 `affection_drag_gain`, 명세 `action: DRAG` · `todayActions.drag`. 고칠 곳 전체 목록은 **`backend/db/제안-필드-끌기-호감도.md`** (서버 담당 PC에만 있음 — 원격 저장소에서 뺌, 10-23). 그때까지 서버 모드에선 끌어도 호감도가 안 오름
- **탐색 첫날 (10-20 제안, D-45)**: 시드 출현 레벨이 1/3/6/9…라 카테고리 Lv.1 ~ 2에는 후보가 시작 몬스터(가진 종)뿐 → 처음 며칠은 탐색 결과가 꽝 아니면 15G. 옛 결정 B5("Lv.1에 시작 몬스터 + 1종", 1/1/3/6…)를 쓰려면 카테고리마다 두 번째 종의 `unlock_level`을 1로 (앱 `Catalog.species`의 `unlockLevel`도 같이). 이번엔 명세 그대로 두기로 함
- **탐색 "본 종" 인덱스 (10-20, D-30)**: `newlySeen` 판단이 `explore_log (user_id, species_id, result)`를 찾는다. 지금은 사용자당 하루 최대 3줄이라 괜찮지만, 느려지면 `CREATE INDEX ix_explore_user_species ON monster.explore_log (user_id, species_id) WHERE result = 'ENCOUNTER'`
- **API 명세 다음 판 제안 (10-20 추가)**: 남의 탐색에 던지기 403 → **404**(C3와 맞춤), 응답의 `imageUrl` → `imageKey`(D1), `dex.newSlotAvailable`의 뜻 = "이번 포획으로 해금권을 받음"
- **API 명세 다음 판 제안 (10-19 추가)**: `POST /checkins/today`의 `categoryExp[].expInLevel` · `expRequired`(D-43), 선택지 밖 값을 받을지(D-42 — 지금은 400), 카테고리 레벨 조회(앱이 다시 켜도 레벨을 알게)
- **API 명세 다음 판 제안 (10-18)**: `POST /onboarding`의 선택 필드 `partnerCategory`(D-36), `GET /me/status`의 `dayCount`(D-37), `GET /monsters` 목록에 `affection` · `expInLevel`(앱이 마리마다 상세를 부르지 않게, D-40)

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
