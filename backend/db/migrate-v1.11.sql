-- 이미 만든 DB(스키마 · 시드 v1.10)를 v1.11로 올린다 — 로컬 Docker DB · Supabase에 한 번 실행 (두 번 실행해도 안전)
-- 새로 만드는 DB는 docs/데이터베이스/schema.sql · seed.sql만 적용하면 된다 (이 파일 불필요). 설명: backend/db/README.md v1.11
-- v1.11 = API 명세 v8: 퀘스트 기반 + 일일 퀘스트 (D-83 · D-85 · D-87). 기존 데이터는 그대로. 한 트랜잭션으로 실행.
-- 순서: v1.10(migrate-v1.10.sql)이 먼저 적용돼 있어야 한다 → 이 SQL → 그다음 서버 배포 (서버는 quest_enabled 키가 없으면 뜨지 않는다)
BEGIN;

CREATE SCHEMA IF NOT EXISTS quest;

CREATE TABLE IF NOT EXISTS quest.quest_def (
  code          TEXT         PRIMARY KEY,
  kind          TEXT         NOT NULL CHECK (kind IN ('DAILY','WEEKLY','SURPRISE','CONDITIONAL')),
  title         VARCHAR(40)  NOT NULL,
  target_count  SMALLINT     NOT NULL CHECK (target_count >= 1),
  reward_gold   INT          NOT NULL CHECK (reward_gold >= 0),
  sort_order    SMALLINT     NOT NULL,
  is_active     BOOLEAN      NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS quest.user_quest (
  id            BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id       BIGINT       NOT NULL REFERENCES identity.users(id),
  period_start  DATE         NOT NULL,
  quest_code    TEXT         NOT NULL REFERENCES quest.quest_def(code),
  progress      SMALLINT     NOT NULL DEFAULT 0 CHECK (progress >= 0),
  target        SMALLINT     NOT NULL CHECK (target >= 1),
  reward_gold   INT          NOT NULL CHECK (reward_gold >= 0),
  status        TEXT         NOT NULL DEFAULT 'IN_PROGRESS' CHECK (status IN ('IN_PROGRESS','DONE')),
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  completed_at  TIMESTAMPTZ  NULL,
  CONSTRAINT uq_user_quest UNIQUE (user_id, period_start, quest_code),
  CONSTRAINT ck_user_quest_done     CHECK ((status = 'DONE') = (completed_at IS NOT NULL)),
  CONSTRAINT ck_user_quest_progress CHECK (progress <= target)
);

-- 권한 (schema.sql 끝의 권한 블록과 같게). app_core 역할이 없는 DB(예: Supabase 기본)면 건너뜀
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_core') THEN
    GRANT USAGE ON SCHEMA quest TO app_core;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA quest TO app_core;
    GRANT USAGE ON ALL SEQUENCES IN SCHEMA quest TO app_core;
    ALTER DEFAULT PRIVILEGES IN SCHEMA quest GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_core;
    ALTER DEFAULT PRIVILEGES IN SCHEMA quest GRANT USAGE ON SEQUENCES TO app_core;
  END IF;
END $$;

INSERT INTO wallet.ledger_reason (code, direction, description)
VALUES ('QUEST_DAILY','CREDIT','일일 퀘스트 완료')
ON CONFLICT DO NOTHING;

INSERT INTO quest.quest_def (code, kind, title, target_count, reward_gold, sort_order) VALUES
 ('DAILY_CHECKIN','DAILY','오늘의 기록',        1, 3, 1),
 ('DAILY_PET',    'DAILY','몬스터 쓰다듬기',    1, 1, 2),
 ('DAILY_TIMER',  'DAILY','타이머 한 번 쓰기',  1, 1, 3),
 ('DAILY_TALK',   'DAILY','몬스터에게 말 걸기', 1, 1, 4)
ON CONFLICT (code) DO NOTHING;

INSERT INTO config.balance_config (key, value, description)
VALUES ('quest_enabled', 'true'::jsonb, '퀘스트 켜기 (끄면 조회 · 진행 · 지급 모두 멈춤) (v1.11)')
ON CONFLICT (key) DO NOTHING;

-- 확인
SELECT code, kind, title, reward_gold FROM quest.quest_def ORDER BY sort_order;
SELECT code FROM wallet.ledger_reason WHERE code = 'QUEST_DAILY';
SELECT key, value FROM config.balance_config WHERE key = 'quest_enabled';

COMMIT;
