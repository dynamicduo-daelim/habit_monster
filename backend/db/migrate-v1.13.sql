-- 이미 만든 DB(스키마 · 시드 v1.12)를 v1.13으로 올린다 — 로컬 Docker DB · Supabase에 한 번 실행 (두 번 실행해도 안전)
-- 새로 만드는 DB는 docs/데이터베이스/schema.sql · seed.sql만 적용하면 된다 (이 파일 불필요). 설명: backend/db/README.md v1.13
-- v1.13 = API 명세 v10: 선물함 (D-89). 지갑 잔액 · 원장은 건드리지 않는다. 한 트랜잭션으로 실행.
-- 순서: v1.12(migrate-v1.12.sql)가 먼저 적용돼 있어야 한다 → 이 SQL → 그다음 서버 배포
-- 옛 방식 퀘스트 골드(v1.11 ~ v1.12 서버가 완료 즉시 지급한 원장 줄, ref_id = user_quest.id)는 4)에서
-- "이미 받은 선물"로 옮긴다 — 선물 id를 그 ref_id와 같게 만들어서, 원장 줄은 그대로 두고도 새 뜻(ref_id = 선물 id)에 맞게 한다.
-- ⚠ 새 서버(선물함)를 배포하기 **직전에 한 번 더** 실행한다: 그사이 옛 서버가 지급한 퀘스트 골드도 선물로 옮겨야
--   새 선물 번호와 겹치지 않는다 (겹치면 새 서버가 "이미 지급됨"으로 보고 골드를 건너뜀).
BEGIN;

CREATE SCHEMA IF NOT EXISTS gift;

CREATE TABLE IF NOT EXISTS gift.gift_source (
  code         TEXT          PRIMARY KEY,
  description  VARCHAR(100)  NOT NULL
);

CREATE TABLE IF NOT EXISTS gift.gift (
  id             BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id        BIGINT       NOT NULL REFERENCES identity.users(id),
  source_code    TEXT         NOT NULL REFERENCES gift.gift_source(code),
  source_ref     VARCHAR(64)  NOT NULL,
  title          VARCHAR(40)  NOT NULL,
  gold           INT          NOT NULL DEFAULT 0 CHECK (gold >= 0),
  item_code      TEXT         NULL REFERENCES shop.shop_item(code),
  item_quantity  SMALLINT     NULL CHECK (item_quantity > 0),
  created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
  claimed_at     TIMESTAMPTZ  NULL,
  CONSTRAINT uq_gift_source   UNIQUE (source_code, source_ref),
  CONSTRAINT ck_gift_item     CHECK ((item_code IS NULL) = (item_quantity IS NULL)),
  CONSTRAINT ck_gift_nonempty CHECK (gold > 0 OR item_code IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS ix_gift_unclaimed ON gift.gift (user_id, id DESC) WHERE claimed_at IS NULL;

CREATE OR REPLACE FUNCTION gift.forbid_gift_change() RETURNS trigger AS $$
BEGIN
  IF NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.source_code IS DISTINCT FROM OLD.source_code
     OR NEW.source_ref IS DISTINCT FROM OLD.source_ref OR NEW.title IS DISTINCT FROM OLD.title
     OR NEW.gold IS DISTINCT FROM OLD.gold OR NEW.item_code IS DISTINCT FROM OLD.item_code
     OR NEW.item_quantity IS DISTINCT FROM OLD.item_quantity OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'gift % content cannot change', OLD.id USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.claimed_at IS NOT NULL AND NEW.claimed_at IS DISTINCT FROM OLD.claimed_at THEN
    RAISE EXCEPTION 'gift % already claimed', OLD.id USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS tg_gift_fixed ON gift.gift;
CREATE TRIGGER tg_gift_fixed BEFORE UPDATE ON gift.gift
  FOR EACH ROW EXECUTE FUNCTION gift.forbid_gift_change();

INSERT INTO gift.gift_source (code, description) VALUES
 ('QUEST_DAILY','일일 퀘스트 완료'),
 ('QUEST_WEEKLY','주간 퀘스트 완료')
ON CONFLICT (code) DO NOTHING;

-- 권한 (schema.sql 끝의 권한 블록과 같게). app_core 역할이 없는 DB(예: Supabase 기본)면 건너뜀
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_core') THEN
    GRANT USAGE ON SCHEMA gift TO app_core;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA gift TO app_core;
    GRANT USAGE ON ALL SEQUENCES IN SCHEMA gift TO app_core;
    ALTER DEFAULT PRIVILEGES IN SCHEMA gift GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_core;
    ALTER DEFAULT PRIVILEGES IN SCHEMA gift GRANT USAGE ON SEQUENCES TO app_core;
  END IF;
END $$;

-- 4) 옛 방식 퀘스트 골드 → 이미 받은 선물 (원장 줄 1개 = 선물 1개, 선물 id = 원장 ref_id = user_quest.id)
--    id를 직접 넣는다(OVERRIDING SYSTEM VALUE). user_quest id는 일일 · 주간을 통틀어 하나뿐이라 겹치지 않는다.
--    이미 선물과 짝이 맞는 줄(앞서 이 파일을 실행했거나 새 서버가 지급한 줄)은 건너뛴다 → 두 번 실행해도 안전.
INSERT INTO gift.gift (id, user_id, source_code, source_ref, title, gold, created_at, claimed_at)
OVERRIDING SYSTEM VALUE
SELECT q.id, l.user_id, l.reason_code, q.id::text, d.title, l.amount,
       coalesce(q.completed_at, l.occurred_at), l.occurred_at
FROM wallet.wallet_ledger l
JOIN quest.user_quest q ON q.id::text = l.ref_id AND q.user_id = l.user_id
JOIN quest.quest_def d  ON d.code = q.quest_code
                       AND d.kind = CASE l.reason_code WHEN 'QUEST_DAILY' THEN 'DAILY' ELSE 'WEEKLY' END
WHERE l.reason_code IN ('QUEST_DAILY','QUEST_WEEKLY')
  AND NOT EXISTS (SELECT 1 FROM gift.gift g WHERE g.source_code = l.reason_code AND g.id::text = l.ref_id)
ON CONFLICT DO NOTHING;

-- 5) 다음 선물 번호가 옮긴 번호와 겹치지 않게 번호표를 가장 큰 id 뒤로 (선물이 하나도 없으면 그대로)
SELECT setval(pg_get_serial_sequence('gift.gift','id'), max(id)) FROM gift.gift HAVING count(*) > 0;

-- 6) 확인: 선물과 짝이 없는 퀘스트 골드 원장 줄이 남았으면 멈춘다 (전부 되돌림).
--    남는 경우: ref_id가 user_quest가 아니거나, 그 번호를 다른 선물이 이미 쓰고 있음 → 손으로 확인 필요
DO $$
DECLARE n bigint;
BEGIN
  SELECT count(*) INTO n FROM wallet.wallet_ledger l
  WHERE l.reason_code IN ('QUEST_DAILY','QUEST_WEEKLY')
    AND NOT EXISTS (SELECT 1 FROM gift.gift g
                    WHERE g.source_code = l.reason_code AND g.id::text = l.ref_id AND g.claimed_at IS NOT NULL);
  IF n > 0 THEN
    RAISE EXCEPTION '선물로 옮기지 못한 퀘스트 골드 원장 줄 %건 — 손으로 확인 필요 (backend/db/README.md v1.13)', n;
  END IF;
END $$;

-- 확인 (Supabase SQL 편집기는 마지막 결과 하나만 보여 준다 → 한 줄로 모음)
SELECT
  (SELECT string_agg(code, ', ' ORDER BY code) FROM gift.gift_source)                       AS gift_sources,    -- QUEST_DAILY, QUEST_WEEKLY
  (SELECT count(*) FROM pg_trigger WHERE tgname = 'tg_gift_fixed')                           AS gift_trigger,    -- 1
  (SELECT count(*) FROM gift.gift WHERE claimed_at IS NOT NULL)                              AS moved_gifts,     -- 옮긴 옛 퀘스트 골드 수 (Supabase는 4)
  (SELECT count(*) FROM wallet.wallet_ledger WHERE reason_code LIKE 'QUEST\_%')              AS quest_ledger;    -- 위와 같은 수

COMMIT;
