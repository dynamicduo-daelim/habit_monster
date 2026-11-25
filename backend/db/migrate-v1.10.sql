-- 이미 만든 DB(스키마 · 시드 v1.9)를 v1.10으로 올린다 — 로컬 Docker DB · Supabase에 한 번 실행 (두 번 실행해도 안전)
-- 새로 만드는 DB는 docs/데이터베이스/schema.sql · seed.sql만 적용하면 된다 (이 파일 불필요). 설명: backend/db/README.md v1.10
-- v1.10 = API 명세 v7: 필드 끌기 호감도 DRAG (D-46 · D-86). 데이터는 그대로. 한 트랜잭션으로 실행.
-- 실행 전 확인: 제약 이름이 affection_action_action_type_check 인지 (\d monster.affection_action 또는 Supabase 테이블 화면).
--   이름이 다르면 DROP이 아무것도 안 지우고 옛 CHECK가 남아 DRAG를 계속 막는다.
-- 순서: 이 SQL 먼저 → 그다음 서버 배포 (서버는 affection_drag_gain 키가 없으면 뜨지 않는다)
BEGIN;

ALTER TABLE monster.affection_action DROP CONSTRAINT IF EXISTS affection_action_action_type_check;
ALTER TABLE monster.affection_action ADD  CONSTRAINT affection_action_action_type_check
  CHECK (action_type IN ('PET','PLAY','DRAG'));

INSERT INTO config.balance_config (key, value, description)
VALUES ('affection_drag_gain', '1'::jsonb, '필드에서 끌어 옮기기 (몬스터마다 하루 1회) (v1.10)')
ON CONFLICT (key) DO NOTHING;

-- 확인
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'affection_action_action_type_check';
SELECT key, value FROM config.balance_config WHERE key = 'affection_drag_gain';

COMMIT;
