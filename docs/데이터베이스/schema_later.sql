-- =====================================================================
-- 습관 몬스터 — MVP 이후 추가 스키마 (v1.2에서 schema.sql에서 분리, v1.3 규칙 적용: TEXT enum, 스키마 간 FK)
-- 적용 순서: schema.sql → seed.sql → (필요할 때) schema_later.sql
-- 각 블록은 독립적이므로 필요한 것만 골라 적용해도 된다.
--   A. 결제 + 유료 목표 슬롯       — 실제 결제(PG) 붙일 때
--   B. 밸런스 수치 변경 이력        — 운영 화면에서 수치를 바꾸기 시작할 때
--   C. AI 개인화 기억 + 호출 로그   — 체크인 대사가 안정된 뒤 기억 기능을 붙일 때
-- =====================================================================

-- =====================================================================
-- A. payment (결제) + goal 유료 슬롯
--  결제 확정 → 권한 생성 → goal 슬롯 지급을 같은 트랜잭션에서 처리 (schema.sql 원칙 3)
--  PG 웹훅은 트랜잭션 밖에서 오므로 payment_order.idempotency_key / pg_tx_id 로 중복 처리를 막는다
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS payment;

-- 권한 종류 코드 (열린 집합, schema.sql 원칙 8-1)
CREATE TABLE payment.entitlement_kind (
  code         TEXT          PRIMARY KEY,
  description  VARCHAR(100)  NOT NULL
);
INSERT INTO payment.entitlement_kind (code, description) VALUES ('WEEKLY_GOAL_SLOT','주간 목표 슬롯 추가');

CREATE TABLE payment.payment_product (
  code               TEXT         PRIMARY KEY,      -- WEEKLY_SLOT_1
  name               VARCHAR(40)  NOT NULL,
  price_krw          INT          NOT NULL CHECK (price_krw >= 0),
  entitlement_type   TEXT         NOT NULL REFERENCES payment.entitlement_kind(code),
  entitlement_value  SMALLINT     NOT NULL CHECK (entitlement_value > 0),
  is_active          BOOLEAN      NOT NULL DEFAULT true
);

CREATE TABLE payment.payment_order (
  id               BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id          BIGINT       NOT NULL REFERENCES identity.users(id),
  product_code     TEXT         NOT NULL REFERENCES payment.payment_product(code),
  amount_krw       INT          NOT NULL CHECK (amount_krw >= 0),
  status           TEXT         NOT NULL DEFAULT 'CREATED'
                   CHECK (status IN ('CREATED','PAID','FAILED','CANCELED','REFUNDED')),
  pg_provider      TEXT         NULL,
  pg_tx_id         VARCHAR(100) NULL UNIQUE,
  idempotency_key  UUID         NOT NULL UNIQUE,
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  paid_at          TIMESTAMPTZ  NULL,
  CONSTRAINT ck_order_paid CHECK (status NOT IN ('PAID','REFUNDED') OR paid_at IS NOT NULL)
);
CREATE INDEX ix_order_user ON payment.payment_order (user_id, created_at DESC);

CREATE TABLE payment.entitlement (
  id                BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id           BIGINT       NOT NULL REFERENCES identity.users(id),
  order_id          BIGINT       NOT NULL UNIQUE REFERENCES payment.payment_order(id),
  entitlement_type  TEXT         NOT NULL REFERENCES payment.entitlement_kind(code),
  value             SMALLINT     NOT NULL CHECK (value > 0),
  granted_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  revoked_at        TIMESTAMPTZ  NULL
);

CREATE TABLE goal.goal_slot_grant (
  id              BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         BIGINT       NOT NULL REFERENCES goal.goal_user(user_id),
  entitlement_id  BIGINT       NOT NULL UNIQUE REFERENCES payment.entitlement(id),  -- v1.3 스키마 간 FK
  slots           SMALLINT     NOT NULL CHECK (slots > 0),
  granted_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  revoked_at      TIMESTAMPTZ  NULL    -- 환불 시: 이미 만든 유료 슬롯 목표는 유지, 신규만 제한
);

GRANT USAGE ON SCHEMA payment TO app_core;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA payment TO app_core;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA payment TO app_core;
ALTER DEFAULT PRIVILEGES IN SCHEMA payment GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_core;
ALTER DEFAULT PRIVILEGES IN SCHEMA payment GRANT USAGE ON SEQUENCES TO app_core;
-- goal.goal_slot_grant 권한은 schema.sql의 DEFAULT PRIVILEGES로 자동 부여

INSERT INTO payment.payment_product (code, name, price_krw, entitlement_type, entitlement_value) VALUES
 ('WEEKLY_SLOT_1','주간 목표 슬롯 +1',0,'WEEKLY_GOAL_SLOT',1);

-- =====================================================================
-- B. 밸런스 수치 변경 이력 (기획서: 수치 조정 기록을 포트폴리오 근거로 사용)
--  도입 전에는 수치 변경 = 마이그레이션 파일 (git 이력이 기록 역할)
-- =====================================================================
CREATE TABLE config.balance_config_history (
  id          BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  key         TEXT         NOT NULL,
  old_value   JSONB        NULL,                    -- 최초 등록이면 NULL
  new_value   JSONB        NOT NULL,
  changed_by  VARCHAR(40)  NOT NULL,
  reason      VARCHAR(200) NULL,                    -- SET LOCAL app.config_reason = '…' 로 전달
  changed_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX ix_config_history_key ON config.balance_config_history (key, changed_at DESC);

CREATE FUNCTION config.log_balance_change() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.value IS DISTINCT FROM OLD.value THEN
    INSERT INTO config.balance_config_history (key, old_value, new_value, changed_by, reason)
    VALUES (NEW.key, CASE WHEN TG_OP = 'UPDATE' THEN OLD.value END, NEW.value, NEW.updated_by,
            NULLIF(current_setting('app.config_reason', true), ''));
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = config, pg_temp;  -- 관리자 역할은 이력 쓰기 권한 없음
CREATE TRIGGER tg_balance_config_history AFTER INSERT OR UPDATE ON config.balance_config
  FOR EACH ROW EXECUTE FUNCTION config.log_balance_change();

-- 도입 시점의 값을 이력의 출발점으로 기록
INSERT INTO config.balance_config_history (key, old_value, new_value, changed_by, reason)
SELECT key, NULL, value, updated_by, 'history baseline' FROM config.balance_config;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_config_admin') THEN
    CREATE ROLE app_config_admin NOLOGIN;
  END IF;
END $$;
GRANT USAGE ON SCHEMA config TO app_config_admin;
GRANT SELECT, INSERT, UPDATE ON config.balance_config TO app_config_admin;
GRANT SELECT ON config.balance_config_history TO app_config_admin;

-- =====================================================================
-- C. AI 개인화 기억 + 호출 로그
--  기억은 사용자에게 노출하지 않음 (A-3). 탈퇴 시 전부 삭제.
-- =====================================================================
ALTER TABLE ai.chat_session
  ADD COLUMN memory_extracted_at TIMESTAMPTZ NULL;   -- 기억 추출 완료 (중복 추출 방지)
CREATE INDEX ix_chat_session_extract ON ai.chat_session (ended_at)
  WHERE memory_extracted_at IS NULL AND safety_flagged_at IS NULL AND ended_at IS NOT NULL;

-- 기억 종류 코드 (열린 집합: 추출 프롬프트를 다듬으며 늘어날 수 있음)
CREATE TABLE ai.memory_kind (
  code         TEXT          PRIMARY KEY,
  description  VARCHAR(100)  NOT NULL
);
INSERT INTO ai.memory_kind (code, description) VALUES
 ('ROUTINE','생활 패턴'),('PREFERENCE','선호'),('EVENT','시효가 있는 일'),('MOOD_HINT','기분 단서');

CREATE TABLE ai.memory_item (
  id                 BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id            BIGINT       NOT NULL REFERENCES identity.users(id),
  kind               TEXT         NOT NULL REFERENCES ai.memory_kind(code),
  content            VARCHAR(300) NOT NULL,
  source_session_id  BIGINT       NULL REFERENCES ai.chat_session(id),
  importance         SMALLINT     NOT NULL DEFAULT 1 CHECK (importance BETWEEN 1 AND 5),
  created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
  last_used_at       TIMESTAMPTZ  NULL,
  expires_at         TIMESTAMPTZ  NULL               -- EVENT 등 시효가 있는 기억
);
CREATE INDEX ix_memory_user ON ai.memory_item (user_id, importance DESC, created_at DESC);

-- LLM 호출 메타데이터 (내용 없음): 비용·지연·대체율 측정
CREATE TABLE ai.llm_call_log (
  id                 BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id            BIGINT       NOT NULL REFERENCES identity.users(id),
  session_id         BIGINT       NULL REFERENCES ai.chat_session(id),
  purpose            TEXT         NOT NULL CHECK (purpose IN ('CHECKIN_LINE','MEMORY_EXTRACT')),
  model              TEXT         NOT NULL,
  status             TEXT         NOT NULL CHECK (status IN ('OK','ERROR','TIMEOUT','BLOCKED')),
  prompt_tokens      INT          NULL CHECK (prompt_tokens >= 0),
  completion_tokens  INT          NULL CHECK (completion_tokens >= 0),
  latency_ms         INT          NOT NULL CHECK (latency_ms >= 0),
  created_at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX ix_llm_call_time ON ai.llm_call_log (created_at);
-- ai 테이블 권한은 schema.sql의 DEFAULT PRIVILEGES로 app_ai에 자동 부여

INSERT INTO config.balance_config (key, value, description) VALUES
 ('memory_prompt_max_items', '8', '프롬프트에 넣는 기억 항목 최대 수');
