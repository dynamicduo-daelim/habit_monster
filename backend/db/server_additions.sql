-- =====================================================================
-- 서버가 공식 스키마(v1.6) 위에 추가로 쓰는 테이블 — DB 담당에게 넘길 제안
-- 적용 순서: schema.sql → seed.sql → 이 파일   (backend/docker-compose.yml이 자동으로 이 순서로 적용)
-- 작성: 2026-10-15 (0단계, API 명세 v4 "중복 요청 방지 키 저장")
-- =====================================================================

-- 중복 요청 방지 키 (Idempotency-Key)
-- 앱이 버튼을 누를 때 만든 UUID. 응답을 못 받아 같은 키로 다시 보내면 처음 결과를 그대로 돌려준다.
-- 키 범위는 사용자 + 메서드 + 경로 (API 명세 v4). 24시간 보관 후 서버가 지운다.
-- 처리 순서 (server: idempotency/IdempotencyFilter):
--   1) 행을 만든다 (PENDING, 따로 커밋)
--   2) 요청 트랜잭션에서 SELECT … FOR UPDATE NOWAIT — 잠겨 있으면 같은 키가 처리 중 → 409
--   3) 2xx면 결과를 같은 트랜잭션에 저장(COMPLETED) / 4xx면 변경을 되돌린 뒤 결과만 저장 / 5xx면 저장 안 함
-- 도메인 테이블의 idempotency_key UNIQUE(purchase · explore_log · checkin_submission)는 그대로 두는 마지막 방어선.
CREATE TABLE identity.idempotency_record (
  id               BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id          BIGINT       NOT NULL REFERENCES identity.users(id),
  method           VARCHAR(10)  NOT NULL,
  path             VARCHAR(500) NOT NULL,          -- /api/v1 뒤 경로 (예: /explores/500/capture)
  idem_key         UUID         NOT NULL,
  request_hash     CHAR(64)     NOT NULL,          -- SHA-256(쿼리 + 본문). 같은 키 · 다른 본문 → 422
  status           TEXT         NOT NULL CHECK (status IN ('PENDING','COMPLETED')),
  response_status  INT          NULL,
  response_type    VARCHAR(100) NULL,
  response_body    TEXT         NULL,
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  expires_at       TIMESTAMPTZ  NOT NULL,
  CONSTRAINT uq_idempotency_record UNIQUE (user_id, method, path, idem_key),
  CONSTRAINT ck_idempotency_completed CHECK ((status = 'COMPLETED') = (response_status IS NOT NULL))
);
-- 만료 정리(매일 04:30)용
CREATE INDEX ix_idempotency_expires ON identity.idempotency_record (expires_at);
