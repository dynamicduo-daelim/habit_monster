-- 이미 만든 DB(스키마 · 시드 v1.11)를 v1.12로 올린다 — 로컬 Docker DB · Supabase에 한 번 실행 (두 번 실행해도 안전)
-- 새로 만드는 DB는 docs/데이터베이스/schema.sql · seed.sql만 적용하면 된다 (이 파일 불필요). 설명: backend/db/README.md v1.12
-- v1.12 = API 명세 v9: 주간 퀘스트 (D-88). 테이블 변경 없음 — 원장 사유 · 시드 · 설정 키만. 한 트랜잭션으로 실행.
-- 순서: v1.11(migrate-v1.11.sql)이 먼저 적용돼 있어야 한다 → 이 SQL → 그다음 서버 배포 (서버는 quest_weekly_rate_threshold 키가 없으면 뜨지 않는다)
BEGIN;

INSERT INTO wallet.ledger_reason (code, direction, description)
VALUES ('QUEST_WEEKLY','CREDIT','주간 퀘스트 완료')
ON CONFLICT DO NOTHING;

INSERT INTO quest.quest_def (code, kind, title, target_count, reward_gold, sort_order) VALUES
 ('WEEKLY_ATTEND',     'WEEKLY','주 4일 출석',              4, 5, 11),
 ('WEEKLY_GOOD_DAYS',  'WEEKLY','성실도 80% 이상인 날 2일',  2, 5, 12),
 ('WEEKLY_CATEGORIES', 'WEEKLY','카테고리 3곳 체크인',       3, 5, 13)
ON CONFLICT (code) DO NOTHING;

INSERT INTO config.balance_config (key, value, description)
VALUES ('quest_weekly_rate_threshold', '80'::jsonb, '주간 퀘스트 "성실도 N% 이상인 날"의 N — 첫 제출 성실도 기준 (v1.12)')
ON CONFLICT (key) DO NOTHING;

-- 확인 (Supabase SQL 편집기는 마지막 결과 하나만 보여 준다 → 한 줄로 모음)
SELECT
  (SELECT string_agg(code || ':' || target_count || ':' || reward_gold, ', ' ORDER BY sort_order)
     FROM quest.quest_def WHERE kind = 'WEEKLY')                                    AS weekly_quests,   -- WEEKLY_ATTEND:4:5, WEEKLY_GOOD_DAYS:2:5, WEEKLY_CATEGORIES:3:5
  (SELECT count(*) FROM wallet.ledger_reason WHERE code = 'QUEST_WEEKLY')          AS quest_weekly,    -- 1
  (SELECT value FROM config.balance_config WHERE key = 'quest_weekly_rate_threshold') AS threshold;    -- 80

COMMIT;
