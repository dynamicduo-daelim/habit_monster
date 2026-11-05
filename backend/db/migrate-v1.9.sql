-- 이미 만든 DB(스키마 v1.7 · 시드 v1.8)를 v1.9로 올린다 — 로컬 Docker DB · Supabase에 한 번 실행 (두 번 실행해도 안전)
-- 새로 만드는 DB는 docs/데이터베이스/schema.sql · seed.sql만 적용하면 된다 (이 파일 불필요). 설명: backend/db/README.md v1.9
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
