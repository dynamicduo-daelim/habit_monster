-- =====================================================================
-- 습관 몬스터 — 물리 스키마 (PostgreSQL 16)
-- 작성일: 2026-10-03  /  v1.1 2026-10-04 (교차 검증 반영)  /  v1.2 2026-10-04 (경량화)
-- v1.3 2026-10-04: 문자열 enum 확장 방식, 스키마 간 FK, consumer_key 단일화
-- v1.4 2026-10-07: 습관 기간을 1주/1개월/3개월 → 7일/30일/100일 (코드 D7/D30/D100)
-- v1.5 2026-10-08: 볼 = 포획용(탐색 추가 제거), 같은 종 중복 보유, 카테고리마다 초기 몬스터,
--                  체크인 재제출(보상은 첫 확정 기준), 온보딩은 마지막에 한 번에 저장
-- v1.6 2026-10-10: 이미 가진 종을 포획하면 골드(종당 1마리 복원), 볼을 안 던지면 건너뜀(보상 없음, 골드 전환 삭제)
-- v1.7 2026-10-15: API 명세 v4 · 설계 변경 기록(10-14~15) 반영
--   * 업무 날짜 경계 04:00 → 00:00 (원칙 5)
--   * 이메일은 가입 방법과 관계없이 한 계정에만 (identity.users.email UNIQUE). Apple 로그인 제외
--   * 출석 기록 테이블(habit.attendance) 추가, 연속 일수를 체크인 기준 → 출석 기준
--   * 습관 상태 ACTIVE/ENDED/STOPPED, 기간을 habit.habit_period로 분리 (연장마다 1행, "채운 날 수" 기준)
--     달력 종료일·동결 정지 일수(paused_days)·완주율 삭제
--   * 체크인 습관 행에 채운 날 여부(is_filled)·기간 번호(period_seq) 고정 기록
--   * 탐색 결과 MISS / DUPLICATE(가진 종, 볼 없이 골드) / ENCOUNTER, 포획 결과 CAPTURED / ESCAPED
--     처리 안 한 등장은 SKIPPED(다시 탐색) / EXPIRED(날짜가 바뀜)로 닫는다
--   * 체크인 대사 저장 테이블(ai.checkin_dialogue): 제출 차수(revision)당 1개
--   * 중복 요청 방지 키 저장(api.idempotency_record): 사용자 + 메서드 + 경로, 24시간 보관
--   * 탈퇴 시 습관명·목표 제목을 비우므로 두 컬럼은 NULL 허용
-- v1.7 보충 2026-10-28 (API 명세 v5 보충 10-28): 목표 기간 = 등록한 날부터 주간 7일 · 월간 30일
--   * goal.goal.period_start = 등록한 날 (월요일 · 1일 제약 ck_goal_period_start 삭제). 끝 날은 시작 + 기간 − 1 (컬럼 없음)
--   * 기간 일수는 config weekly_goal_days · monthly_goal_days
-- 설계 문서: 04_논리물리모델.md (v1.7 반영 전)
-- MVP 밖 구성요소(결제, 수치 변경 이력, AI 기억·호출 로그)는 schema_later.sql (이 파일 다음에 적용)
--
-- 원칙
--  1) DB 1개, 도메인 = 스키마. (v1.3) 스키마 간에도 FK를 건다 → 고아 행을 DB가 막는다.
--     단 ON DELETE는 모두 NO ACTION(원칙 7). 모듈 경계는 FK가 아니라 "누가 쓰는가"로 지킨다:
--     각 모듈은 자기 스키마 테이블만 INSERT/UPDATE 한다 (코드 규칙 + 아키텍처 테스트).
--     서비스를 실제로 분리할 때는 스키마 간 FK를 DROP 하면 된다 (지우기는 쉽고, 나중에 걸기는 어렵다).
--  2) 스키마 간 FK의 참조 방향: 사용자 루트 행·마스터 쪽으로만 (예: *.user_id → identity.users,
--     category_code → habit.category, consumption_id → shop.item_consumption). 순환 없음.
--  3) 도메인 간 처리 = 같은 프로세스 안의 모듈 서비스 호출 + 하나의 DB 트랜잭션 (v1.2).
--     적립·차감·상태 전파가 함께 커밋/롤백되므로 아웃박스·보상 처리가 필요 없다.
--     각 모듈의 저장소(repository)는 자기 스키마만 읽고 쓴다 (코드 규칙, 아키텍처 테스트로 검사).
--     멱등성: 요청 단위는 api.idempotency_record (v1.7), 원장은 UNIQUE(reason_code, ref_id),
--     각 테이블의 idempotency_key·consumer_key는 DB 쪽 마지막 방어선으로 유지한다.
--     서비스를 실제로 분리하게 되면 그때 아웃박스로 전환한다 (04 문서 7장).
--  3-1) 사용자 단위 잠금 행은 SELECT … FOR NO KEY UPDATE로 잡고, 순서를 고정한다 (교착 방지):
--       habit.habit_user → goal.goal_user → monster.monster_user → shop.inventory → wallet.wallet
--       (FOR NO KEY UPDATE는 다른 트랜잭션의 FK 삽입이 잡는 KEY SHARE 잠금과 충돌하지 않음)
--       골드·볼·물약 차감은 조건부 UPDATE(… WHERE balance >= ?) 또는 위 잠금으로 처리하고,
--       CHECK(… >= 0) 위반은 애플리케이션이 422로 바꾼다.
--  3-2) 외부 API(Gemini) 호출은 DB 트랜잭션 밖에서 한다. 잠금을 쥔 채 네트워크를 기다리지 않는다.
--  4) CHECK에는 "구조적 불변식"만 넣는다 (음수 불가, 상태-시각 일치 등).
--     튜닝 대상 수치(레벨당 125 EXP, 필드 5마리, 호감도 최대 10, 카테고리 최대 레벨 20 …)는 config에 두고
--     애플리케이션이 검증한다. 수치를 바꿀 때 마이그레이션이 필요 없게 하기 위함.
--  5) 업무 날짜(checkin_date, quota_date, attended_on 등)는 서버가 Asia/Seoul 고정, 00:00 경계로 계산해 저장한다.
--     주는 월요일 00:00, 월은 1일 00:00에 시작한다. (사용자별 시간대 없음 — v1.1 결정 C, v1.7 경계 변경)
--     단, 목표 기간은 달력 주·달이 아니라 등록한 날부터 센다 (v1.7 보충 10-28).
--  6) 레벨은 누적 EXP(exp_total)가 기준값. level 컬럼은 캐시이며 "내려가지 않는다" (v1.1 결정 B).
--     수치 변경 시 level = GREATEST(level, f(exp_total))로만 재계산.
--  7) 행을 물리 삭제하지 않는다(소프트 삭제·상태값). 그래서 모든 FK는 의도적으로 ON DELETE 미지정(NO ACTION).
--     물리 삭제 대상: 탈퇴 시 identity의 auth_credential·refresh_token·device_token, ai의 대화·대사(·기억),
--     api.idempotency_record(만료 정리 + 탈퇴 시). 탈퇴 시 users.email·habit.name·goal.title은 NULL로 비운다.
--  8) 문자열 enum (v1.3). 모든 enum·코드 컬럼은 TEXT (길이 제한 없음 → 값이 길어져도 타입 변경 불필요).
--     8-1) 열린 집합 — 콘텐츠·운영으로 값이 늘어나는 것: 코드 테이블 + FK. 값 추가 = INSERT 한 줄.
--          identity.auth_provider, wallet.ledger_reason, shop.item_effect, monster.acquisition_source
--     8-2) 닫힌 집합 — 상태 기계·구조 규칙이라 값이 바뀌면 코드 로직도 바뀌는 것: CHECK (… IN …).
--          제약 이름은 PostgreSQL 기본 규칙 <테이블>_<컬럼>_check 로 예측 가능.
--          값 추가 마이그레이션은 한 문장 (04 문서 1장):
--          ALTER TABLE t DROP CONSTRAINT t_col_check, ADD CONSTRAINT t_col_check CHECK (col IN (…)) NOT VALID;
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS identity;
CREATE SCHEMA IF NOT EXISTS habit;
CREATE SCHEMA IF NOT EXISTS goal;
CREATE SCHEMA IF NOT EXISTS wallet;
CREATE SCHEMA IF NOT EXISTS shop;
CREATE SCHEMA IF NOT EXISTS monster;
CREATE SCHEMA IF NOT EXISTS config;
CREATE SCHEMA IF NOT EXISTS ai;
CREATE SCHEMA IF NOT EXISTS api;     -- v1.7: 요청 처리 공통 (중복 요청 방지 키)
-- payment 스키마는 schema_later.sql (v1.2)
-- outbox_event / processed_event 제거 (v1.2: 단일 트랜잭션)

-- =====================================================================
-- identity (회원)
-- =====================================================================
CREATE TABLE identity.users (
  id                BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nickname          VARCHAR(30)  NULL,               -- 유일성 없음 (소셜·검색 기능 없음)
  -- v1.7: 이메일 하나에 계정 하나 (가입 방법과 관계없이). 소문자로 저장.
  --       카카오는 이메일 제공이 선택이라 NULL 허용. 탈퇴 시 NULL로 비워 같은 이메일로 재가입 가능.
  --       다른 방법으로 가입된 이메일이면 자동 병합하지 않고 409 EMAIL_REGISTERED_WITH_OTHER_METHOD
  email             VARCHAR(255) NULL CHECK (email = lower(email)),
  -- v1.5: 온보딩은 단계별 저장 없이 마지막에 한 트랜잭션으로 저장 (카테고리·습관·목표·초기 몬스터).
  --       중단하면 아무것도 남지 않으므로 다시 처음부터. NULL = 온보딩 미완료
  onboarded_at      TIMESTAMPTZ  NULL,
  status            TEXT         NOT NULL DEFAULT 'ACTIVE'
                    CHECK (status IN ('ACTIVE','WITHDRAWN')),
  last_active_date  DATE         NULL,
  frozen_at         TIMESTAMPTZ  NULL,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  withdrawn_at      TIMESTAMPTZ  NULL,
  CONSTRAINT ck_users_withdrawn CHECK ((status = 'WITHDRAWN') = (withdrawn_at IS NOT NULL))
);
CREATE UNIQUE INDEX uq_users_email ON identity.users (email) WHERE email IS NOT NULL;
-- 동결 대상 탐색(스케줄러): 활성이면서 동결 안 된 사용자 중 마지막 활동일이 오래된 순
CREATE INDEX ix_users_freeze_scan ON identity.users (last_active_date)
  WHERE status = 'ACTIVE' AND frozen_at IS NULL;

-- 로그인 제공자 코드 (열린 집합, 원칙 8-1): 네이버·애플 등 추가 = INSERT
CREATE TABLE identity.auth_provider (
  code       TEXT         PRIMARY KEY,
  name       VARCHAR(20)  NOT NULL,
  is_active  BOOLEAN      NOT NULL DEFAULT true
);
INSERT INTO identity.auth_provider (code, name) VALUES
 ('EMAIL','이메일'),('KAKAO','카카오'),('GOOGLE','구글');   -- v1.7: APPLE 제외

CREATE TABLE identity.auth_credential (
  id                BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id           BIGINT       NOT NULL REFERENCES identity.users(id),
  provider          TEXT         NOT NULL REFERENCES identity.auth_provider(code),
  provider_subject  VARCHAR(255) NOT NULL,   -- EMAIL: 소문자 정규화한 이메일 / 소셜: 제공자 sub
  -- v1.7: 표시용 email 컬럼 삭제 → identity.users.email (계정당 하나, 유일)
  password_hash     VARCHAR(100) NULL,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  last_login_at     TIMESTAMPTZ  NULL,
  CONSTRAINT uq_auth_provider_subject UNIQUE (provider, provider_subject),
  CONSTRAINT uq_auth_user_provider    UNIQUE (user_id, provider),
  CONSTRAINT ck_auth_password CHECK ((provider = 'EMAIL') = (password_hash IS NOT NULL))
);

CREATE TABLE identity.refresh_token (
  id            BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id       BIGINT       NOT NULL REFERENCES identity.users(id),
  token_hash    CHAR(64)     NOT NULL UNIQUE,         -- SHA-256 hex, 원문 저장 안 함
  device_label  VARCHAR(60)  NULL,
  expires_at    TIMESTAMPTZ  NOT NULL,
  revoked_at    TIMESTAMPTZ  NULL,
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX ix_refresh_token_user ON identity.refresh_token (user_id) WHERE revoked_at IS NULL;

CREATE TABLE identity.device_token (
  id          BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     BIGINT       NOT NULL REFERENCES identity.users(id),
  fcm_token   VARCHAR(255) NOT NULL UNIQUE,
  platform    TEXT         NOT NULL CHECK (platform IN ('ANDROID','IOS')),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX ix_device_token_user ON identity.device_token (user_id);

-- =====================================================================
-- habit (습관·체크인·출석) — 카테고리 마스터 소유
-- =====================================================================
CREATE TABLE habit.category (
  code        TEXT         PRIMARY KEY,           -- ex, st, fd, md, sl, mn
  name        VARCHAR(20)  NOT NULL UNIQUE,
  short_name  VARCHAR(10)  NOT NULL,
  element     VARCHAR(10)  NOT NULL,              -- 불꽃, 번개 …
  glyph       CHAR(1)      NOT NULL,
  color       CHAR(7)      NOT NULL CHECK (color ~ '^#[0-9a-fA-F]{6}$'),
  sort_order  SMALLINT     NOT NULL UNIQUE
);

CREATE TABLE habit.measure_type (
  id              SMALLINT      PRIMARY KEY,
  category_code   TEXT          NOT NULL REFERENCES habit.category(code),
  name            VARCHAR(30)   NOT NULL,
  unit            VARCHAR(5)    NOT NULL,          -- 분, 회, 점, L, 끼, p, h, 원, OX
  scoring_mode    TEXT          NOT NULL CHECK (scoring_mode IN ('TARGET_RATIO','BINARY','RANGE')),
  default_target  NUMERIC(12,2) NOT NULL CHECK (default_target > 0),
  step            NUMERIC(12,2) NOT NULL CHECK (step > 0),
  max_value       NUMERIC(12,2) NULL CHECK (max_value > 0),   -- 입력 상한 (물 5L 등)
  range_below     NUMERIC(12,2) NULL CHECK (range_below >= 0), -- RANGE: 목표 - below ~ 목표 + above
  range_above     NUMERIC(12,2) NULL CHECK (range_above >= 0),
  sort_order      SMALLINT      NOT NULL,
  CONSTRAINT uq_measure_category_name UNIQUE (category_code, name),
  CONSTRAINT uq_measure_id_category   UNIQUE (id, category_code),     -- 복합 FK 대상
  CONSTRAINT ck_measure_range CHECK (
    (scoring_mode = 'RANGE') = (range_below IS NOT NULL AND range_above IS NOT NULL)),
  CONSTRAINT ck_measure_range_pair CHECK ((range_below IS NULL) = (range_above IS NULL)),
  CONSTRAINT ck_measure_binary CHECK (scoring_mode <> 'BINARY' OR default_target = 1)
);

CREATE TABLE habit.habit_preset (
  id               SMALLINT      PRIMARY KEY,
  category_code    TEXT          NOT NULL,
  measure_type_id  SMALLINT      NOT NULL,
  name             VARCHAR(30)   NOT NULL,
  default_target   NUMERIC(12,2) NOT NULL CHECK (default_target > 0),
  sort_order       SMALLINT      NOT NULL,
  -- 추천의 측정 항목이 같은 카테고리 것임을 보장
  CONSTRAINT fk_preset_measure FOREIGN KEY (measure_type_id, category_code)
    REFERENCES habit.measure_type (id, category_code)
);

-- 사용자별 습관 도메인 프로필: 연속 출석 + 사용자 단위 직렬화(잠금) 행
CREATE TABLE habit.habit_user (
  user_id             BIGINT       PRIMARY KEY REFERENCES identity.users(id),
  -- v1.7: 연속 일수는 출석(habit.attendance) 기준. 출석 트랜잭션에서 함께 갱신
  current_streak      INT          NOT NULL DEFAULT 0 CHECK (current_streak >= 0),
  longest_streak      INT          NOT NULL DEFAULT 0 CHECK (longest_streak >= 0),
  last_attended_date  DATE         NULL,            -- 조회 시 이 값이 어제보다 이전이면 연속 0으로 표시
  frozen_since        DATE         NULL,            -- 동결 스케줄러가 같은 트랜잭션에서 기록
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
  version             INT          NOT NULL DEFAULT 0,
  CONSTRAINT ck_streak_longest CHECK (longest_streak >= current_streak)
);

-- v1.7 출석: 하루 1행. 앱 실행·복귀 시 POST /me/attendance가 INSERT … ON CONFLICT DO NOTHING
CREATE TABLE habit.attendance (
  user_id      BIGINT       NOT NULL REFERENCES habit.habit_user(user_id),
  attended_on  DATE         NOT NULL,                 -- 00:00 경계 업무 날짜
  attended_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),   -- 그날 첫 출석 시각
  PRIMARY KEY (user_id, attended_on)
);

CREATE TABLE habit.user_category (
  user_id        BIGINT       NOT NULL REFERENCES habit.habit_user(user_id),
  category_code  TEXT         NOT NULL REFERENCES habit.category(code),
  opened_via     TEXT         NOT NULL CHECK (opened_via IN ('INITIAL','TICKET')),
  exp_total      INT          NOT NULL DEFAULT 0 CHECK (exp_total >= 0),
  level          SMALLINT     NOT NULL DEFAULT 1 CHECK (level >= 1),  -- 캐시: GREATEST(level, f(exp_total)), 상한은 config (v1.7: 20)
  opened_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, category_code)
);

CREATE TABLE habit.category_unlock_ticket (
  id                  BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id             BIGINT       NOT NULL REFERENCES habit.habit_user(user_id),
  milestone           SMALLINT     NOT NULL CHECK (milestone > 0),   -- 도감 기준값 (5, 10, 15 …)
  -- 탐색으로 도감 수가 기준값에 닿으면 같은 트랜잭션에서 지급. 중복 지급은 uq_ticket_milestone이 막음 (v1.2)
  granted_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
  used_category_code  TEXT         NULL,
  used_at             TIMESTAMPTZ  NULL,
  CONSTRAINT uq_ticket_milestone UNIQUE (user_id, milestone),
  CONSTRAINT ck_ticket_used CHECK ((used_category_code IS NULL) = (used_at IS NULL)),
  CONSTRAINT fk_ticket_category FOREIGN KEY (user_id, used_category_code)
    REFERENCES habit.user_category (user_id, category_code)
);
CREATE INDEX ix_ticket_unused ON habit.category_unlock_ticket (user_id) WHERE used_at IS NULL;

-- 습관 (v1.7): 이름·카테고리·측정 항목·상태만. 기간·목표값은 habit.habit_period (연장마다 1행)
--   ACTIVE  : 기간 진행 중 (마지막 기간이 아직 안 참)
--   ENDED   : 마지막 기간을 채움 → 연장(새 기간 행) 또는 그만두기 선택 대기
--   STOPPED : 그만둠. 통계·기록용으로만 남음 (진행 중 기간은 채우지 못한 채로 남음, 보너스 없음)
-- 습관 개수 상한(ACTIVE + ENDED 5개)은 config(max_active_habits) → 애플리케이션 검사
CREATE TABLE habit.habit (
  id                 BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id            BIGINT        NOT NULL,
  category_code      TEXT          NOT NULL,
  measure_type_id    SMALLINT      NOT NULL,
  name               VARCHAR(30)   NULL CHECK (length(btrim(name)) > 0),   -- 탈퇴 시 NULL (원칙 7)
  status             TEXT          NOT NULL DEFAULT 'ACTIVE'
                     CHECK (status IN ('ACTIVE','ENDED','STOPPED')),
  stopped_at         TIMESTAMPTZ   NULL,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
  CONSTRAINT fk_habit_user_category FOREIGN KEY (user_id, category_code)
    REFERENCES habit.user_category (user_id, category_code),
  CONSTRAINT fk_habit_measure FOREIGN KEY (measure_type_id, category_code)
    REFERENCES habit.measure_type (id, category_code),
  CONSTRAINT ck_habit_stopped CHECK ((status = 'STOPPED') = (stopped_at IS NOT NULL))
);
-- 습관 상한 검사·체크인 대상 조회 (ACTIVE + ENDED)
CREATE INDEX ix_habit_user_open ON habit.habit (user_id) WHERE status IN ('ACTIVE','ENDED');

-- 습관 기간 (v1.7): 습관 등록 = seq 1, 연장할 때마다 seq + 1
-- 기간은 "채운 날 수" 기준 — 첫 제출에서 했다고(done) 제출한 날만 센다. 연속 불필요, 빠진 날·미접속은 초기화하지 않음.
-- filled_days가 period_days에 닿는 첫 제출에서 ended_on·period_bonus를 기록하고 습관을 ENDED로 바꾼다 (같은 트랜잭션).
-- 시작일 규칙: 오늘 체크인 제출 전이면 오늘, 제출 후면 내일 (애플리케이션)
CREATE TABLE habit.habit_period (
  id                 BIGINT        GENERATED ALWAYS AS IDENTITY UNIQUE,   -- 원장 PERIOD_BONUS의 ref_id
  habit_id           BIGINT        NOT NULL REFERENCES habit.habit(id),
  seq                SMALLINT      NOT NULL CHECK (seq >= 1),
  period_code        TEXT          NOT NULL CHECK (period_code IN ('D7','D30','D100')),  -- 배수는 config
  period_days        SMALLINT      NOT NULL CHECK (period_days > 0),                  -- 채워야 할 날 수
  daily_target       NUMERIC(12,2) NOT NULL CHECK (daily_target > 0),   -- 기간 중 변경 불가, 연장 때만 변경
  started_on         DATE          NOT NULL,
  filled_days        SMALLINT      NOT NULL DEFAULT 0 CHECK (filled_days >= 0),  -- 캐시: is_filled 행 수
  counted_score_sum  INT           NOT NULL DEFAULT 0 CHECK (counted_score_sum >= 0), -- 캐시: 반영 습관으로 받은 점수 합
  ended_on           DATE          NULL,                                  -- 기간을 채운 업무 날짜
  period_bonus       INT           NULL CHECK (period_bonus >= 0),        -- 골드 = counted_score_sum × (배수 − 1)
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
  PRIMARY KEY (habit_id, seq),
  CONSTRAINT ck_period_days CHECK (
    (period_code = 'D7'   AND period_days = 7)  OR
    (period_code = 'D30'  AND period_days = 30) OR
    (period_code = 'D100' AND period_days = 100)),
  CONSTRAINT ck_period_filled_max CHECK (filled_days <= period_days),
  CONSTRAINT ck_period_ended CHECK ((filled_days = period_days) = (ended_on IS NOT NULL)),
  CONSTRAINT ck_period_bonus CHECK ((ended_on IS NULL) = (period_bonus IS NULL)),
  CONSTRAINT ck_period_ended_after_start CHECK (ended_on IS NULL OR ended_on >= started_on)
);
-- 채우지 않은 기간은 습관당 1개 (진행 중 또는 그만둔 채 남은 기간)
CREATE UNIQUE INDEX uq_period_open ON habit.habit_period (habit_id) WHERE ended_on IS NULL;

-- v1.5 체크인 재제출: 하루 1행은 그대로. 같은 날 다시 제출하면 수치(value·score·total_score)만 갱신하고,
-- 보상·카테고리 EXP·채운 날·탐색 횟수는 첫 확정 값(counted_score, rewarded_*, is_filled)으로 고정한다.
-- 첫 확정 값은 트리거가 수정을 막는다 (habit.forbid_reward_change).
-- v1.7: 다시 체크의 대상은 첫 제출에 들어간 습관 전체 (그 뒤 ENDED·STOPPED가 된 습관 포함). 새 습관은 끼어들지 않음.
CREATE TABLE habit.daily_checkin (
  id                 BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id            BIGINT       NOT NULL REFERENCES habit.habit_user(user_id),
  checkin_date       DATE         NOT NULL,                -- 00:00 경계, 서버 계산 (v1.7)
  habit_count        SMALLINT     NOT NULL CHECK (habit_count > 0),     -- 첫 제출의 습관 수 (다시 체크도 같음)
  total_score        SMALLINT     NOT NULL CHECK (total_score >= 0),    -- 최신 제출의 전체 합 (화면·통계)
  counted_score      SMALLINT     NOT NULL CHECK (counted_score >= 0),  -- 첫 확정의 반영 상위 N개 합 = 점수 골드 (불변)
  revision           SMALLINT     NOT NULL DEFAULT 1 CHECK (revision >= 1),  -- 제출 횟수
  confirmed_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),  -- 첫 확정 (불변)
  last_submitted_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT uq_checkin_user_date UNIQUE (user_id, checkin_date)      -- 하루 1행 (BR-08)
);

-- 제출 1건 = 1행. 재시도(같은 키)와 재제출(새 키)을 구분하는 멱등 키 보관 (v1.5)
-- (daily_checkin_id, revision)은 체크인 대사(ai.checkin_dialogue)의 참조 대상 (v1.7)
CREATE TABLE habit.checkin_submission (
  idempotency_key   UUID         PRIMARY KEY,
  daily_checkin_id  BIGINT       NOT NULL REFERENCES habit.daily_checkin(id),
  revision          SMALLINT     NOT NULL CHECK (revision >= 1),
  submitted_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT uq_submission_revision UNIQUE (daily_checkin_id, revision)
);

CREATE TABLE habit.habit_checkin (
  daily_checkin_id  BIGINT        NOT NULL REFERENCES habit.daily_checkin(id),
  habit_id          BIGINT        NOT NULL REFERENCES habit.habit(id),
  period_seq        SMALLINT      NOT NULL,                        -- v1.7: 이 날이 속한 습관 기간 (불변)
  value             NUMERIC(12,2) NOT NULL CHECK (value >= 0),     -- 최신 값. "못했어" = 0, O/X는 0/1
  target_snapshot   NUMERIC(12,2) NOT NULL CHECK (target_snapshot > 0),
  score             SMALLINT      NOT NULL CHECK (score >= 0),     -- 최신 점수 0~25 (화면·통계)
  rewarded_value    NUMERIC(12,2) NOT NULL CHECK (rewarded_value >= 0),  -- 첫 확정 값 (불변)
  rewarded_score    SMALLINT      NOT NULL CHECK (rewarded_score >= 0),  -- 첫 확정 점수 (불변) → 골드·EXP·기간 점수 기준
  is_counted        BOOLEAN       NOT NULL,     -- 첫 확정 때 점수 상위 N개 반영 여부 (불변, 동점은 등록 순서)
  is_filled         BOOLEAN       NOT NULL,     -- v1.7: 첫 확정에서 "했어"(값 > 0) → 기간 채운 날 1일 (불변)
  PRIMARY KEY (daily_checkin_id, habit_id),
  CONSTRAINT fk_hc_period FOREIGN KEY (habit_id, period_seq)
    REFERENCES habit.habit_period (habit_id, seq),
  CONSTRAINT ck_hc_filled CHECK (is_filled = (rewarded_value > 0))
);
CREATE INDEX ix_habit_checkin_habit ON habit.habit_checkin (habit_id, period_seq);

-- 보상 기준값 불변 (v1.5, v1.7 확장): 재제출은 최신 값(value·score·total_score)만 바꾼다
CREATE FUNCTION habit.forbid_reward_change() RETURNS trigger AS $$
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
       OR NEW.target_snapshot IS DISTINCT FROM OLD.target_snapshot THEN
      RAISE EXCEPTION 'habit_checkin (%, %): reward fields are fixed at first confirmation',
        OLD.daily_checkin_id, OLD.habit_id USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER tg_daily_checkin_reward_fixed BEFORE UPDATE ON habit.daily_checkin
  FOR EACH ROW EXECUTE FUNCTION habit.forbid_reward_change();
CREATE TRIGGER tg_habit_checkin_reward_fixed BEFORE UPDATE ON habit.habit_checkin
  FOR EACH ROW EXECUTE FUNCTION habit.forbid_reward_change();

-- =====================================================================
-- goal (목표) — 기간은 등록한 날부터 주간 7일 · 월간 30일 (v1.7 보충 10-28, config *_goal_days)
-- 기간이 남은 목표(ACTIVE·COMPLETED)가 칸을 차지한다. 기간이 끝난 ACTIVE 목표는 상태를 바꾸지 않고 날짜로 거른다.
-- =====================================================================
CREATE TABLE goal.goal_user (
  user_id             BIGINT       PRIMARY KEY REFERENCES identity.users(id),
  extra_weekly_slots  SMALLINT     NOT NULL DEFAULT 0 CHECK (extra_weekly_slots >= 0),  -- 결제 도입 전에는 항상 0
  version             INT          NOT NULL DEFAULT 0,
  updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE goal.goal (
  id            BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id       BIGINT       NOT NULL REFERENCES goal.goal_user(user_id),
  goal_type     TEXT         NOT NULL CHECK (goal_type IN ('WEEKLY','MONTHLY')),
  period_start  DATE         NOT NULL,                -- 등록한 날 (업무 날짜). 끝 날 = 시작 + 기간 − 1
  title         VARCHAR(50)  NULL CHECK (length(btrim(title)) > 0),   -- 탈퇴 시 NULL (원칙 7), 그 외 필수는 앱 검사
  detail        VARCHAR(500) NULL,
  is_paid_slot  BOOLEAN      NOT NULL DEFAULT false,   -- 결제 도입 전에는 항상 false
  status        TEXT         NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','COMPLETED','DELETED')),
  completed_at  TIMESTAMPTZ  NULL,
  deleted_at    TIMESTAMPTZ  NULL,
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT ck_goal_status_time CHECK (
    (status = 'ACTIVE'    AND completed_at IS NULL     AND deleted_at IS NULL) OR
    (status = 'COMPLETED' AND completed_at IS NOT NULL AND deleted_at IS NULL) OR
    (status = 'DELETED'   AND completed_at IS NULL     AND deleted_at IS NOT NULL)),  -- 완료 목표 삭제 불가
  CONSTRAINT ck_goal_paid_weekly CHECK (NOT is_paid_slot OR goal_type = 'WEEKLY')
);
CREATE INDEX ix_goal_user_period ON goal.goal (user_id, goal_type, period_start)
  WHERE status <> 'DELETED';

-- 상태 전이 규칙 (Q-5): ACTIVE → COMPLETED | DELETED 만 허용, 완료·삭제 이후 상태·시각 변경 불가.
-- CHECK는 "한 행의 모양"만 검사하므로 status와 completed_at을 함께 되돌리는 UPDATE를 막지 못함 → 트리거.
CREATE FUNCTION goal.forbid_goal_reopen() RETURNS trigger AS $$
BEGIN
  IF OLD.status <> 'ACTIVE' AND (NEW.status IS DISTINCT FROM OLD.status
       OR NEW.completed_at IS DISTINCT FROM OLD.completed_at
       OR NEW.deleted_at   IS DISTINCT FROM OLD.deleted_at) THEN
    RAISE EXCEPTION 'goal % is %, state cannot change', OLD.id, OLD.status USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER tg_goal_no_reopen BEFORE UPDATE ON goal.goal
  FOR EACH ROW EXECUTE FUNCTION goal.forbid_goal_reopen();

-- goal.goal_slot_grant (유료 슬롯 지급 기록)는 결제와 함께 schema_later.sql (v1.2)

-- =====================================================================
-- wallet (지갑)
-- =====================================================================
CREATE TABLE wallet.wallet (
  user_id     BIGINT       PRIMARY KEY REFERENCES identity.users(id),
  balance     BIGINT       NOT NULL DEFAULT 0 CHECK (balance >= 0),
  version     INT          NOT NULL DEFAULT 0,
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- 원장 사유 코드 (열린 집합, 원칙 8-1). 사유마다 허용 방향(적립 CREDIT / 차감 DEBIT)을 행으로 둔다.
-- 원장의 direction(금액 부호에서 자동 계산)과 복합 FK → "구매는 차감만, 체크인은 적립만"을 데이터로 강제.
-- 새 보상 추가 = INSERT ('EVENT_REWARD','CREDIT') 한 줄. 양방향 사유(ADJUST)는 두 행.
-- ref_id: CHECKIN → daily_checkin.id / LEVELUP → daily_checkin.id:카테고리 코드 /
--         PERIOD_BONUS → habit_period.id / GOAL_* → goal.id / DUPLICATE → explore_log.id / SHOP_PURCHASE → purchase.id
CREATE TABLE wallet.ledger_reason (
  code         TEXT          NOT NULL,
  direction    TEXT          NOT NULL CHECK (direction IN ('CREDIT','DEBIT')),
  description  VARCHAR(100)  NOT NULL,
  PRIMARY KEY (code, direction)
);
INSERT INTO wallet.ledger_reason (code, direction, description) VALUES
 ('CHECKIN','CREDIT','체크인 성실도 (반영 습관 점수 합)'),
 ('LEVELUP','CREDIT','카테고리 레벨업'),
 ('PERIOD_BONUS','CREDIT','습관 기간 채움 보너스'),
 ('GOAL_WEEKLY','CREDIT','주간 목표 완료'),
 ('GOAL_MONTHLY','CREDIT','월간 목표 완료'),
 ('DUPLICATE','CREDIT','탐색에서 가진 종 등장 → 볼 없이 골드'),   -- v1.7
 ('SHOP_PURCHASE','DEBIT','상점 구매'),
 ('ADJUST','CREDIT','운영 보정 (지급·환불)'),
 ('ADJUST','DEBIT','운영 보정 (회수)');

CREATE TABLE wallet.wallet_ledger (
  id             BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id        BIGINT       NOT NULL REFERENCES wallet.wallet(user_id),
  amount         INT          NOT NULL CHECK (amount <> 0),
  balance_after  BIGINT       NOT NULL CHECK (balance_after >= 0),
  reason_code    TEXT         NOT NULL,
  direction      TEXT         NOT NULL GENERATED ALWAYS AS
                   (CASE WHEN amount > 0 THEN 'CREDIT' ELSE 'DEBIT' END) STORED,
  ref_id         VARCHAR(64)  NOT NULL,             -- 위 ledger_reason 주석 / ADJUST: 운영 처리 번호
  memo           VARCHAR(200) NULL,                 -- ADJUST 필수: 사유 (CS 보상, 버그 복구, 수치 조정 보상)
  occurred_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT uq_ledger_reason_ref UNIQUE (reason_code, ref_id),   -- 멱등성 (BR-31): 스케줄러 재실행·재시도 이중 지급 방지
  -- 금액 0인 적립(전부 "못했어"인 날, 보너스 0)은 원장에 쓰지 않는다 (호출하는 쪽이 건너뜀)
  -- v1.3: 부호 규칙 CHECK(ck_ledger_sign) → 사유 코드 테이블과의 복합 FK
  CONSTRAINT fk_ledger_reason FOREIGN KEY (reason_code, direction)
    REFERENCES wallet.ledger_reason (code, direction),
  CONSTRAINT ck_ledger_adjust_memo CHECK (reason_code <> 'ADJUST' OR memo IS NOT NULL)
);
CREATE INDEX ix_ledger_user_time ON wallet.wallet_ledger (user_id, occurred_at DESC);

-- =====================================================================
-- shop (상점·가방)
--  v1.2: 구매·소모는 지갑 차감/몬스터 반영과 같은 트랜잭션 → 실패하면 행 자체가 남지 않음.
--        그래서 PENDING·FAILED·REFUNDED 상태와 소모 복구(RESTORED) 상태를 없앴다.
-- =====================================================================
-- 아이템 효과 코드 (열린 집합, 원칙 8-1)
CREATE TABLE shop.item_effect (
  code         TEXT          PRIMARY KEY,
  description  VARCHAR(100)  NOT NULL
);
INSERT INTO shop.item_effect (code, description) VALUES
 ('MONSTER_EXP','몬스터 개체 경험치'),
 ('CAPTURE','등장한 몬스터 포획 시도');   -- v1.5: 탐색 추가권 → 포획용

CREATE TABLE shop.shop_item (
  code          TEXT         PRIMARY KEY,           -- POTION_S, POTION_M, POTION_L, BALL(포획용)
  name          VARCHAR(30)  NOT NULL,
  short_name    VARCHAR(10)  NOT NULL,
  price         INT          NOT NULL CHECK (price > 0),
  effect_type   TEXT         NOT NULL REFERENCES shop.item_effect(code),
  effect_value  INT          NOT NULL CHECK (effect_value > 0),
  sort_order    SMALLINT     NOT NULL,
  is_active     BOOLEAN      NOT NULL DEFAULT true
);

CREATE TABLE shop.inventory (
  user_id     BIGINT       NOT NULL REFERENCES identity.users(id),
  item_code   TEXT         NOT NULL REFERENCES shop.shop_item(code),
  quantity    INT          NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  version     INT          NOT NULL DEFAULT 0,
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, item_code)
);

CREATE TABLE shop.purchase (
  id               BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id          BIGINT       NOT NULL REFERENCES identity.users(id),
  item_code        TEXT         NOT NULL REFERENCES shop.shop_item(code),
  quantity         SMALLINT     NOT NULL CHECK (quantity > 0),   -- 1~99는 애플리케이션 검사
  unit_price       INT          NOT NULL CHECK (unit_price > 0),   -- 구매 시점 가격 스냅샷
  total_price      INT          NOT NULL CHECK (total_price > 0),
  idempotency_key  UUID         NOT NULL UNIQUE,        -- 클라이언트 재시도 시 같은 구매로 인식
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),  -- 행이 있으면 완료된 구매
  CONSTRAINT ck_purchase_total CHECK (total_price = unit_price * quantity)
);
CREATE INDEX ix_purchase_user ON shop.purchase (user_id, created_at DESC);

CREATE TABLE shop.item_consumption (
  id            BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id       BIGINT       NOT NULL REFERENCES identity.users(id),
  item_code     TEXT         NOT NULL REFERENCES shop.shop_item(code),
  quantity      SMALLINT     NOT NULL CHECK (quantity > 0),
  consumer_key  TEXT         NOT NULL UNIQUE,   -- 'FEED:<uuid>' / 'CAPTURE:<uuid>'. 소모 멱등 키를 보관하는 유일한 곳 (v1.3)
  consumed_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);
-- 가방 수량 대사: inventory.quantity = 구매 수량 합 − 소모 수량 합 (verify S-12)
CREATE INDEX ix_consumption_user_item ON shop.item_consumption (user_id, item_code);

-- =====================================================================
-- monster (몬스터)
-- =====================================================================
CREATE TABLE monster.monster_species (
  id              SMALLINT     PRIMARY KEY,
  code            TEXT         NOT NULL UNIQUE,
  category_code   TEXT         NOT NULL REFERENCES habit.category(code),
  name            VARCHAR(20)  NOT NULL UNIQUE,
  rarity          SMALLINT     NOT NULL CHECK (rarity BETWEEN 1 AND 3),   -- 1 흔함, 2 보통, 3 희귀
  -- v1.7: 카테고리 7종 기준 해금 레벨 1/3/6/9/12/15/18로 분산 (시드 데이터). 상한은 config category_max_level
  unlock_level    SMALLINT     NOT NULL CHECK (unlock_level >= 1),
  dex_no          SMALLINT     NOT NULL UNIQUE CHECK (dex_no > 0),
  description     VARCHAR(200) NOT NULL,
  is_starter      BOOLEAN      NOT NULL DEFAULT false,
  display_height  SMALLINT     NOT NULL DEFAULT 72 CHECK (display_height > 0),
  facing          TEXT         NOT NULL DEFAULT 'FRONT' CHECK (facing IN ('LEFT','FRONT')),
  CONSTRAINT ck_species_starter_unlock CHECK (NOT is_starter OR unlock_level = 1),
  CONSTRAINT uq_species_id_category UNIQUE (id, category_code)          -- starter_grant 복합 FK 대상 (v1.5)
);
-- 카테고리당 스타터 정확히 1종 (최대 1은 DB, 최소 1은 시드 검증 쿼리)
CREATE UNIQUE INDEX uq_species_starter ON monster.monster_species (category_code) WHERE is_starter;
CREATE INDEX ix_species_pool ON monster.monster_species (category_code, unlock_level);

CREATE TABLE monster.monster_form (
  species_id  SMALLINT     NOT NULL REFERENCES monster.monster_species(id),
  stage       SMALLINT     NOT NULL CHECK (stage BETWEEN 0 AND 2),   -- 0 기본, 1 1차, 2 최종
  min_level   SMALLINT     NOT NULL CHECK (min_level >= 1),
  image_url   VARCHAR(255) NOT NULL,
  PRIMARY KEY (species_id, stage)
);

CREATE TABLE monster.species_line (
  id              INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  species_id      SMALLINT     NOT NULL REFERENCES monster.monster_species(id),
  affection_tier  TEXT         NOT NULL CHECK (affection_tier IN ('LOW','MID','HIGH')),
  line_text       VARCHAR(100) NOT NULL
);
CREATE INDEX ix_species_line ON monster.species_line (species_id, affection_tier);

-- 사용자별 몬스터 프로필: 도감 수 + 사용자 단위 직렬화(잠금) 행
CREATE TABLE monster.monster_user (
  user_id     BIGINT       PRIMARY KEY REFERENCES identity.users(id),
  dex_count   SMALLINT     NOT NULL DEFAULT 0 CHECK (dex_count >= 0),
  version     INT          NOT NULL DEFAULT 0,
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- 개체 획득 경로 코드 (열린 집합, 원칙 8-1): 이벤트 보상·선물 등 추가 = INSERT
CREATE TABLE monster.acquisition_source (
  code         TEXT          PRIMARY KEY,
  description  VARCHAR(100)  NOT NULL
);
INSERT INTO monster.acquisition_source (code, description) VALUES
 ('STARTER','카테고리 초기 몬스터 (온보딩·해금 시 카테고리마다 1마리)'),
 ('EXPLORE','탐색 신규 획득');

CREATE TABLE monster.user_monster (
  id            BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id       BIGINT       NOT NULL REFERENCES monster.monster_user(user_id),
  species_id    SMALLINT     NOT NULL REFERENCES monster.monster_species(id),
  level         SMALLINT     NOT NULL DEFAULT 1 CHECK (level >= 1),     -- 캐시, 내려가지 않음 (원칙 6)
  exp_total     INT          NOT NULL DEFAULT 0 CHECK (exp_total >= 0), -- 누적 EXP (기준값)
  affection     SMALLINT     NOT NULL DEFAULT 0 CHECK (affection >= 0),
  location      TEXT         NOT NULL CHECK (location IN ('FIELD','BAG')),
  is_partner    BOOLEAN      NOT NULL DEFAULT false,                    -- 챗봇 대화 상대 (가방에 있어도 됨)
  acquired_via  TEXT         NOT NULL REFERENCES monster.acquisition_source(code),
  acquired_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  version       INT          NOT NULL DEFAULT 0,
  CONSTRAINT uq_user_species UNIQUE (user_id, species_id),             -- 종당 1마리 (BR-54)
  CONSTRAINT uq_user_monster_owner_species UNIQUE (id, user_id, species_id)  -- starter_grant 복합 FK 대상
);
CREATE UNIQUE INDEX uq_user_partner ON monster.user_monster (user_id) WHERE is_partner;   -- 대화 상대 1마리

-- 카테고리마다 초기 몬스터 1마리 (v1.5: 사용자당 1마리 → 카테고리당 1마리)
-- 온보딩에서 고른 카테고리와 해금권으로 연 카테고리 모두 지급. 지급 트랜잭션은 카테고리를 여는 트랜잭션과 같다.
CREATE TABLE monster.starter_grant (
  user_id          BIGINT       NOT NULL,
  category_code    TEXT         NOT NULL,
  user_monster_id  BIGINT       NOT NULL UNIQUE,
  species_id       SMALLINT     NOT NULL,
  granted_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, category_code),                                       -- 카테고리당 1마리
  -- 지급 개체가 이 사용자의 것이고 종이 일치하는지
  CONSTRAINT fk_starter_monster FOREIGN KEY (user_monster_id, user_id, species_id)
    REFERENCES monster.user_monster (id, user_id, species_id),
  -- 지급한 종이 그 카테고리 소속인지 (스타터 종 여부는 앱 + verify 검사)
  CONSTRAINT fk_starter_species FOREIGN KEY (species_id, category_code)
    REFERENCES monster.monster_species (id, category_code),
  -- 사용자가 연 카테고리에만 지급 (스키마 간 FK)
  CONSTRAINT fk_starter_category_opened FOREIGN KEY (user_id, category_code)
    REFERENCES habit.user_category (user_id, category_code)
);

CREATE TABLE monster.monster_growth_log (
  id               BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_monster_id  BIGINT       NOT NULL REFERENCES monster.user_monster(id),
  consumption_id   BIGINT       NOT NULL UNIQUE REFERENCES shop.item_consumption(id),  -- v1.3: 키 대신 소모 행 참조 (1:1)
  exp_gained       INT          NOT NULL CHECK (exp_gained > 0),
  exp_total_after  INT          NOT NULL CHECK (exp_total_after >= exp_gained),
  level_before     SMALLINT     NOT NULL,
  level_after      SMALLINT     NOT NULL,
  fed_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT ck_growth_level CHECK (level_after >= level_before)
);
CREATE INDEX ix_growth_monster ON monster.monster_growth_log (user_monster_id, fed_at DESC);

CREATE TABLE monster.dex_entry (
  user_id           BIGINT       NOT NULL REFERENCES monster.monster_user(user_id),
  species_id        SMALLINT     NOT NULL REFERENCES monster.monster_species(id),
  first_acquired_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, species_id)
);

-- v1.2 제거:
--  * monster.dex_milestone — 해금권 중복 지급은 habit.category_unlock_ticket UNIQUE(user_id, milestone)가 막음
--  * monster.monster_category_view — 탐색 시 habit 모듈 서비스로 카테고리 레벨을 직접 조회 (복제본 불필요)

-- 탐색 기회: 체크인 첫 확정 트랜잭션에서 생성
-- v1.7: base_count = 첫 제출이 전부 "못했어"면 1, 그 외 3 (config explore_daily_free / explore_daily_all_missed)
CREATE TABLE monster.daily_explore_quota (
  user_id           BIGINT       NOT NULL REFERENCES monster.monster_user(user_id),
  quota_date        DATE         NOT NULL,
  base_count        SMALLINT     NOT NULL CHECK (base_count >= 0),
  used_count        SMALLINT     NOT NULL DEFAULT 0 CHECK (used_count >= 0),
  source_checkin_id BIGINT       NOT NULL UNIQUE REFERENCES habit.daily_checkin(id),  -- 같은 체크인으로 재생성 불가
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  version           INT          NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, quota_date),
  CONSTRAINT ck_quota_used CHECK (used_count <= base_count)
);

CREATE TABLE monster.explore_quota_category (
  user_id        BIGINT       NOT NULL,
  quota_date     DATE         NOT NULL,
  category_code  TEXT         NOT NULL,
  PRIMARY KEY (user_id, quota_date, category_code),
  FOREIGN KEY (user_id, quota_date) REFERENCES monster.daily_explore_quota (user_id, quota_date),
  -- 사용자가 연 카테고리만 탐색 풀에 들어감 (v1.3 스키마 간 복합 FK)
  CONSTRAINT fk_quota_category_opened FOREIGN KEY (user_id, category_code)
    REFERENCES habit.user_category (user_id, category_code)
);

-- 탐색 1회 = 1행 (v1.7). result는 셋:
--   MISS      : 꽝
--   DUPLICATE : 가진 종 등장 → 볼 없이 바로 골드 (gold_awarded, 원장 DUPLICATE ref_id = explore_log.id). 그 자리에서 끝
--   ENCOUNTER : 안 가진 종 등장 → 처리 전(outcome NULL) → 아래 넷 중 하나로 끝난다
--     CAPTURED : 볼 1개 소모, 포획 성공 → 개체 생성
--     ESCAPED  : 볼 1개 소모, 포획 실패 → 도망 (등장 끝)
--     SKIPPED  : 볼을 던지지 않고 같은 날 다시 탐색 → 보상 없음
--     EXPIRED  : 처리하지 않은 채 날짜가 바뀜 (다음 탐색 때 또는 정리 배치가 닫음)
-- 처리 전 등장은 사용자당 1건만. 다음 탐색을 요청하면 남아 있는 등장을 같은 트랜잭션에서
-- 같은 날이면 SKIPPED, 지난 날이면 EXPIRED로 닫는다. GET /explores/pending은 오늘 등장만 돌려준다.
CREATE TABLE monster.explore_log (
  id               BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id          BIGINT       NOT NULL,
  quota_date       DATE         NOT NULL,
  seq              SMALLINT     NOT NULL CHECK (seq >= 1),
  idempotency_key  UUID         NOT NULL UNIQUE,
  result           TEXT         NOT NULL CHECK (result IN ('MISS','DUPLICATE','ENCOUNTER')),
  species_id       SMALLINT     NULL REFERENCES monster.monster_species(id),
  outcome          TEXT         NULL CHECK (outcome IN ('CAPTURED','ESCAPED','SKIPPED','EXPIRED')),
  consumption_id   BIGINT       NULL UNIQUE REFERENCES shop.item_consumption(id),   -- 던진 볼 (스키마 간 FK)
  user_monster_id  BIGINT       NULL UNIQUE REFERENCES monster.user_monster(id),    -- 포획된 개체
  gold_awarded     SMALLINT     NOT NULL DEFAULT 0 CHECK (gold_awarded >= 0),
  explored_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  resolved_at      TIMESTAMPTZ  NULL,
  FOREIGN KEY (user_id, quota_date) REFERENCES monster.daily_explore_quota (user_id, quota_date),
  CONSTRAINT uq_explore_seq UNIQUE (user_id, quota_date, seq),
  CONSTRAINT ck_explore_state CHECK (
    (result = 'MISS'      AND species_id IS NULL     AND outcome IS NULL      AND resolved_at IS NULL
                          AND consumption_id IS NULL AND user_monster_id IS NULL AND gold_awarded = 0) OR
    (result = 'DUPLICATE' AND species_id IS NOT NULL AND outcome IS NULL      AND resolved_at IS NULL
                          AND consumption_id IS NULL AND user_monster_id IS NULL AND gold_awarded > 0) OR
    (result = 'ENCOUNTER' AND species_id IS NOT NULL AND outcome IS NULL      AND resolved_at IS NULL
                          AND consumption_id IS NULL AND user_monster_id IS NULL AND gold_awarded = 0) OR
    (result = 'ENCOUNTER' AND species_id IS NOT NULL AND outcome = 'CAPTURED' AND resolved_at IS NOT NULL
                          AND consumption_id IS NOT NULL AND user_monster_id IS NOT NULL AND gold_awarded = 0) OR
    (result = 'ENCOUNTER' AND species_id IS NOT NULL AND outcome = 'ESCAPED'  AND resolved_at IS NOT NULL
                          AND consumption_id IS NOT NULL AND user_monster_id IS NULL AND gold_awarded = 0) OR
    (result = 'ENCOUNTER' AND species_id IS NOT NULL AND outcome = 'SKIPPED'  AND resolved_at IS NOT NULL
                          AND consumption_id IS NULL AND user_monster_id IS NULL AND gold_awarded = 0) OR
    (result = 'ENCOUNTER' AND species_id IS NOT NULL AND outcome = 'EXPIRED'  AND resolved_at IS NOT NULL
                          AND consumption_id IS NULL AND user_monster_id IS NULL AND gold_awarded = 0))
);
CREATE UNIQUE INDEX uq_explore_pending ON monster.explore_log (user_id)
  WHERE result = 'ENCOUNTER' AND outcome IS NULL;                     -- 처리 전 등장 1건

-- 끝난 탐색은 결과를 바꿀 수 없음 (포획 개체·볼 소모·골드와 어긋나지 않게)
-- 바꿀 수 있는 것은 "처리 전 ENCOUNTER → 결과 기록" 한 번뿐
CREATE FUNCTION monster.forbid_encounter_reopen() RETURNS trigger AS $$
BEGIN
  IF (OLD.result <> 'ENCOUNTER' OR OLD.outcome IS NOT NULL)
     AND (NEW.result IS DISTINCT FROM OLD.result
       OR NEW.species_id IS DISTINCT FROM OLD.species_id
       OR NEW.outcome IS DISTINCT FROM OLD.outcome
       OR NEW.consumption_id IS DISTINCT FROM OLD.consumption_id
       OR NEW.user_monster_id IS DISTINCT FROM OLD.user_monster_id
       OR NEW.gold_awarded IS DISTINCT FROM OLD.gold_awarded) THEN
    RAISE EXCEPTION 'explore_log % already resolved (% / %)', OLD.id, OLD.result, OLD.outcome
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER tg_encounter_no_reopen BEFORE UPDATE ON monster.explore_log
  FOR EACH ROW EXECUTE FUNCTION monster.forbid_encounter_reopen();

CREATE TABLE monster.affection_action (
  user_monster_id  BIGINT       NOT NULL REFERENCES monster.user_monster(id),
  action_date      DATE         NOT NULL,
  action_type      TEXT         NOT NULL CHECK (action_type IN ('PET','PLAY')),
  gain             SMALLINT     NOT NULL CHECK (gain >= 0),   -- 최대치면 0
  acted_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
  PRIMARY KEY (user_monster_id, action_date, action_type)    -- 하루 1회 (BR-59)
);

-- =====================================================================
-- config (밸런스 상수) — 쓰기: 마이그레이션(시드) / 읽기: 전 모듈(앱 캐시)
--  v1.2: 변경 이력 테이블·트리거·관리자 역할은 schema_later.sql
--        MVP에서는 수치 변경을 마이그레이션 파일로 남긴다 (git 이력 = 변경 기록)
-- =====================================================================
CREATE TABLE config.balance_config (
  key          TEXT         PRIMARY KEY,
  value        JSONB        NOT NULL,
  description  VARCHAR(200) NOT NULL,
  updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_by   VARCHAR(40)  NOT NULL DEFAULT 'seed'
);

-- =====================================================================
-- ai (체크인 대사 생성, Gemini API)
--  * 체크인 입력·확정·점수는 habit이 담당. ai는 "대사"만 만든다 (결정 A-1).
--  * 경제 도메인(habit·wallet·monster …)에 접근 권한 없음 → 점수·골드에 영향 불가.
--    (v1.3 스키마 간 FK 검사는 참조 테이블 소유자 권한으로 실행되므로 app_ai에 읽기 권한을 줄 필요 없음)
--    필요한 문맥(습관 이름, 대화 상대 종, 호감도 단계)은 호출하는 쪽이 값으로 넘긴다.
--  * 대화 원문은 보관 기간(config chat_message_retention_days) 후 삭제 (A-2). 탈퇴 시 전부 삭제.
--  * v1.2: 개인화 기억(memory_item)·호출 로그(llm_call_log)는 schema_later.sql
-- =====================================================================
CREATE TABLE ai.chat_session (
  id                    BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id               BIGINT       NOT NULL REFERENCES identity.users(id),
  session_date          DATE         NOT NULL,      -- 체크인 업무 날짜
  partner_species_code  TEXT         NOT NULL REFERENCES monster.monster_species(code),
  affection_tier        TEXT         NOT NULL CHECK (affection_tier IN ('LOW','MID','HIGH')),
  daily_checkin_id      BIGINT       NULL REFERENCES habit.daily_checkin(id),  -- 확정되면 기록
  started_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
  ended_at              TIMESTAMPTZ  NULL,
  safety_flagged_at     TIMESTAMPTZ  NULL,          -- 위기 신호 감지: 게임화 대사 중단
  messages_purged_at    TIMESTAMPTZ  NULL
);
CREATE INDEX ix_chat_session_user ON ai.chat_session (user_id, session_date DESC);

CREATE TABLE ai.chat_message (
  session_id   BIGINT        NOT NULL REFERENCES ai.chat_session(id),
  seq          SMALLINT      NOT NULL CHECK (seq >= 1),
  role         TEXT          NOT NULL CHECK (role IN ('BOT','USER')),
  source       TEXT          NOT NULL CHECK (source IN ('LLM','TEMPLATE','WIDGET')), -- TEMPLATE = API 실패 대체
  content      VARCHAR(1000) NOT NULL,
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, seq),
  CONSTRAINT ck_message_source CHECK ((role = 'USER') = (source = 'WIDGET'))
);
CREATE INDEX ix_chat_message_purge ON ai.chat_message (created_at);   -- 보관 기간 지난 원문 삭제

-- v1.7 체크인 대사 (POST /checkins/today/dialogue): 체크인 제출 차수(revision)당 1개.
-- 같은 revision에 다시 요청하면 저장된 대사를 돌려준다 (LLM 비용·남용 방지).
-- AI 실패·제한 시간 초과면 템플릿 대사를 source = 'TEMPLATE'로 저장.
-- user_id는 탈퇴 시 ai 모듈이 habit을 읽지 않고 지우기 위해 둔다.
CREATE TABLE ai.checkin_dialogue (
  daily_checkin_id  BIGINT       NOT NULL,
  revision          SMALLINT     NOT NULL,
  user_id           BIGINT       NOT NULL REFERENCES identity.users(id),
  line_text         VARCHAR(300) NOT NULL CHECK (length(btrim(line_text)) > 0),
  source            TEXT         NOT NULL CHECK (source IN ('LLM','TEMPLATE')),
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  PRIMARY KEY (daily_checkin_id, revision),
  -- 존재하는 제출 차수에만 대사가 붙는다 (스키마 간 복합 FK)
  CONSTRAINT fk_dialogue_submission FOREIGN KEY (daily_checkin_id, revision)
    REFERENCES habit.checkin_submission (daily_checkin_id, revision)
);
CREATE INDEX ix_checkin_dialogue_user ON ai.checkin_dialogue (user_id);

-- =====================================================================
-- api (요청 처리 공통) — v1.7
--  중복 요청 방지 키 (헤더 Idempotency-Key). 대상: 구매, 간식 주기, 체크인 제출·수정, 탐색, 포획,
--  목표 완료, 카테고리 열기.
--  * 키는 사용자 + 메서드 + 경로 단위, 24시간 보관 (expires_at, 만료 행은 배치로 물리 삭제)
--  * 같은 키·같은 본문(request_hash) → 저장된 결과(상태 코드·본문)를 그대로 반환
--  * 같은 키·다른 본문 → 422 IDEMPOTENCY_KEY_REUSED / 처리 중 → 409 REQUEST_IN_PROGRESS
--  * 흐름: ① IN_PROGRESS 행 INSERT (별도 트랜잭션, 충돌 시 기존 행으로 판단)
--          ② 업무 트랜잭션 안에서 같은 행을 COMPLETED + 결과로 UPDATE (업무와 함께 커밋/롤백)
--          ③ 업무가 롤백되면 행은 IN_PROGRESS로 남고, locked_until이 지나면 같은 키로 다시 처리할 수 있다
--  * 결과에 422 같은 업무 오류도 저장한다 (재전송 시 같은 응답). 5xx는 저장하지 않는다.
-- =====================================================================
CREATE TABLE api.idempotency_record (
  user_id          BIGINT       NOT NULL REFERENCES identity.users(id),
  http_method      TEXT         NOT NULL CHECK (http_method IN ('POST','PUT','PATCH','DELETE')),
  request_path     VARCHAR(255) NOT NULL,          -- 실제 경로 (예: /api/v1/monsters/10/feed)
  idempotency_key  UUID         NOT NULL,
  request_hash     CHAR(64)     NOT NULL,          -- 정규화한 요청 본문의 SHA-256 hex
  status           TEXT         NOT NULL DEFAULT 'IN_PROGRESS'
                   CHECK (status IN ('IN_PROGRESS','COMPLETED')),
  locked_until     TIMESTAMPTZ  NULL,               -- IN_PROGRESS 처리 기한 (서버가 죽었을 때 다시 잡기 위함)
  response_status  SMALLINT     NULL CHECK (response_status BETWEEN 200 AND 499),
  response_body    JSONB        NULL,
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  completed_at     TIMESTAMPTZ  NULL,
  expires_at       TIMESTAMPTZ  NOT NULL DEFAULT now() + interval '24 hours',
  PRIMARY KEY (user_id, http_method, request_path, idempotency_key),
  CONSTRAINT ck_idem_state CHECK (
    (status = 'IN_PROGRESS' AND locked_until IS NOT NULL AND response_status IS NULL
                            AND response_body IS NULL AND completed_at IS NULL) OR
    (status = 'COMPLETED'   AND locked_until IS NULL AND response_status IS NOT NULL
                            AND completed_at IS NOT NULL)),
  CONSTRAINT ck_idem_expiry CHECK (expires_at > created_at)
);
CREATE INDEX ix_idempotency_expiry ON api.idempotency_record (expires_at);   -- 만료 정리

-- =====================================================================
-- 권한 (v1.2): 역할 2개
--  * app_core — 경제·회원 도메인 전체 (identity, habit, goal, wallet, shop, monster) + api + config 읽기
--               모듈 경계는 DB 역할이 아니라 코드 규칙(아키텍처 테스트)으로 지킨다.
--  * app_ai   — ai 스키마 + config 읽기만. 경제 데이터 격리는 DB가 강제한다 (S-9).
--  config 쓰기는 마이그레이션 실행 역할(소유자)만.
-- =====================================================================
DO $$
DECLARE s text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_core') THEN
    CREATE ROLE app_core NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_ai') THEN
    CREATE ROLE app_ai NOLOGIN;
  END IF;

  FOREACH s IN ARRAY ARRAY['identity','habit','goal','wallet','shop','monster','api'] LOOP
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO app_core', s);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO app_core', s);
    EXECUTE format('GRANT USAGE ON ALL SEQUENCES IN SCHEMA %I TO app_core', s);
    -- 이후 마이그레이션으로 추가되는 테이블에도 같은 권한 (마이그레이션 실행 역할 기준)
    EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_core', s);
    EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT USAGE ON SEQUENCES TO app_core', s);
  END LOOP;

  GRANT USAGE ON SCHEMA ai TO app_ai;
  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ai TO app_ai;
  GRANT USAGE ON ALL SEQUENCES IN SCHEMA ai TO app_ai;
  ALTER DEFAULT PRIVILEGES IN SCHEMA ai GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_ai;
  ALTER DEFAULT PRIVILEGES IN SCHEMA ai GRANT USAGE ON SEQUENCES TO app_ai;

  GRANT USAGE ON SCHEMA config TO app_core, app_ai;
  GRANT SELECT ON ALL TABLES IN SCHEMA config TO app_core, app_ai;
  ALTER DEFAULT PRIVILEGES IN SCHEMA config GRANT SELECT ON TABLES TO app_core, app_ai;
END $$;
