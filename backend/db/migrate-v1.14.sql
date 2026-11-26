-- 이미 만든 DB(스키마 · 시드 v1.13)를 v1.14로 올린다 — 로컬 Docker DB · Supabase에 한 번 실행 (두 번 실행해도 안전)
-- 새로 만드는 DB는 docs/데이터베이스/schema.sql · seed.sql만 적용하면 된다 (이 파일 불필요). 설명: backend/db/README.md v1.14
-- v1.14 = API 명세 v11: 월간 배지 (D-96). 테이블 · 트리거 · 선물 출처 · 설정 키만 더한다 — 기존 데이터는 바꾸지 않는다
--         (이번 달 줄은 새 서버가 처음 쓸 때 만들고, 그때 그달 이미 완료한 퀘스트 수로 시작한다). 한 트랜잭션으로 실행.
-- 순서: v1.13(migrate-v1.13.sql)이 먼저 → 이 SQL → 그다음 서버 배포 (새 서버는 quest_monthly_* 키가 없으면 뜨지 않는다)
BEGIN;

CREATE TABLE IF NOT EXISTS quest.user_month (
  id               BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id          BIGINT       NOT NULL REFERENCES identity.users(id),
  month_start      DATE         NOT NULL CHECK (extract(day FROM month_start) = 1),
  completed_count  SMALLINT     NOT NULL DEFAULT 0 CHECK (completed_count >= 0),
  badge_earned_at  TIMESTAMPTZ  NULL,
  CONSTRAINT uq_user_month UNIQUE (user_id, month_start)
);

CREATE OR REPLACE FUNCTION quest.forbid_badge_change() RETURNS trigger AS $$
BEGIN
  IF OLD.badge_earned_at IS NOT NULL AND NEW.badge_earned_at IS DISTINCT FROM OLD.badge_earned_at THEN
    RAISE EXCEPTION 'user_month % badge already earned', OLD.id USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS tg_user_month_badge_fixed ON quest.user_month;
CREATE TRIGGER tg_user_month_badge_fixed BEFORE UPDATE ON quest.user_month
  FOR EACH ROW EXECUTE FUNCTION quest.forbid_badge_change();

-- 권한: quest 스키마에는 v1.11에서 ALTER DEFAULT PRIVILEGES를 줬지만, 그건 그 명령을 실행한 역할이 만든 테이블에만 적용된다.
-- 실행 역할이 다를 수 있으니 직접 준다. app_core 역할이 없는 DB(예: Supabase 기본)면 건너뜀
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_core') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON quest.user_month TO app_core;
    GRANT USAGE ON ALL SEQUENCES IN SCHEMA quest TO app_core;
  END IF;
END $$;

INSERT INTO gift.gift_source (code, description)
VALUES ('QUEST_MONTHLY','월간 배지 (성실볼)')
ON CONFLICT (code) DO NOTHING;

INSERT INTO config.balance_config (key, value, description) VALUES
 ('quest_monthly_target',      '20'::jsonb, '월간 배지: 그달 퀘스트 완료 N개 — 베타 달성률 90% 넘으면 재검토 (v1.14)'),
 ('quest_monthly_ball_reward', '1'::jsonb,  '월간 배지 보상 성실볼 개수 — 선물함으로 (v1.14)')
ON CONFLICT (key) DO NOTHING;

-- 확인 (Supabase SQL 편집기는 마지막 결과 하나만 보여 준다 → 한 줄로 모음)
SELECT
  (SELECT count(*) FROM pg_trigger WHERE tgname = 'tg_user_month_badge_fixed')                       AS badge_trigger,   -- 1
  (SELECT count(*) FROM gift.gift_source WHERE code = 'QUEST_MONTHLY')                               AS monthly_source,  -- 1
  (SELECT value FROM config.balance_config WHERE key = 'quest_monthly_target')                       AS target,          -- 20
  (SELECT value FROM config.balance_config WHERE key = 'quest_monthly_ball_reward')                  AS ball,            -- 1
  (SELECT count(*) FROM quest.user_month)                                                            AS month_rows;      -- 0 (처음 실행)

COMMIT;
