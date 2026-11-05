-- =====================================================================
-- schema_later.sql 검증 (verify.sql과 같은 psql 세션에서 이어서 실행)
-- v1.7: 스키마 간 FK 허용 목록이 MVP 19쌍 + 나중 블록 5쌍 = 24쌍
-- v1.9: MVP에 ai.daily_call_count → identity.users 1쌍 → 20 + 5 = 25쌍
-- 실행: psql -v ON_ERROR_STOP=1 -f schema.sql -f seed.sql -f schema_later.sql -f verify.sql -f verify_later.sql
-- =====================================================================
TRUNCATE _result;

-- ---------- A. payment ----------
SELECT pg_temp.expect_fail('L-A1 결제 완료 상태는 결제 시각 필수',
  $$INSERT INTO payment.payment_order (user_id, product_code, amount_krw, status, idempotency_key)
    VALUES (1,'WEEKLY_SLOT_1',0,'PAID','00000000-0000-0000-0000-0000000000d1')$$);
SELECT pg_temp.expect_fail('L-A2 권한 종류 제한',
  $$INSERT INTO payment.payment_order (user_id, product_code, amount_krw, status, idempotency_key, paid_at)
    VALUES (1,'WEEKLY_SLOT_1',0,'PAID','00000000-0000-0000-0000-0000000000d2',now());
    INSERT INTO payment.entitlement (user_id, order_id, entitlement_type, value)
    SELECT 1, id, 'FREE_GOLD', 1 FROM payment.payment_order WHERE idempotency_key = '00000000-0000-0000-0000-0000000000d2'$$);
SELECT pg_temp.expect_ok  ('L-A3 결제 → 권한 → 슬롯 지급 (한 트랜잭션)',
  $$WITH o AS (INSERT INTO payment.payment_order (user_id, product_code, amount_krw, status, idempotency_key, paid_at, pg_provider)
               VALUES (1,'WEEKLY_SLOT_1',0,'PAID','00000000-0000-0000-0000-0000000000d3',now(),'TEST') RETURNING id),
         e AS (INSERT INTO payment.entitlement (user_id, order_id, entitlement_type, value)
               SELECT 1, id, 'WEEKLY_GOAL_SLOT', 1 FROM o RETURNING id)
    INSERT INTO goal.goal_slot_grant (user_id, entitlement_id, slots) SELECT 1, id, 1 FROM e$$);
SELECT pg_temp.expect_fail('L-A4 같은 권한으로 슬롯 두 번 지급 불가',
  $$INSERT INTO goal.goal_slot_grant (user_id, entitlement_id, slots)
    SELECT 1, e.id, 1 FROM payment.entitlement e JOIN payment.payment_order o ON o.id = e.order_id
    WHERE o.idempotency_key = '00000000-0000-0000-0000-0000000000d3'$$);
SELECT pg_temp.expect_fail('L-A4b 없는 권한으로 슬롯 지급 불가 (v1.3 스키마 간 FK)',
  $$INSERT INTO goal.goal_slot_grant (user_id, entitlement_id, slots) VALUES (1,999999,1)$$);
INSERT INTO _result
SELECT 'L-A5 스키마 간 FK 25쌍 = 허용 목록 (MVP 20 + 나중 블록 5, v1.9)',
       (SELECT count(*) FROM _cross_fk_actual) = 25
       AND NOT EXISTS (SELECT * FROM _cross_fk_actual EXCEPT SELECT * FROM _cross_fk_expected),
       (SELECT count(*) FROM _cross_fk_actual) || '쌍';
SELECT pg_temp.expect_ok  ('L-A7 새 권한 종류 = INSERT 한 줄',
  $$INSERT INTO payment.entitlement_kind VALUES ('MONTHLY_GOAL_SLOT','월간 목표 슬롯 추가')$$);
INSERT INTO _result
SELECT 'L-A6 app_core가 payment·goal_slot_grant 사용 가능',
       has_table_privilege('app_core','payment.payment_order','INSERT')
       AND has_table_privilege('app_core','goal.goal_slot_grant','INSERT'), '';

-- ---------- B. config 이력 ----------
INSERT INTO _result
SELECT 'L-B1 도입 시점 값이 이력 출발점으로 기록', count(*) = (SELECT count(*) FROM config.balance_config), count(*) || '건'
FROM config.balance_config_history WHERE reason = 'history baseline' OR key = 'memory_prompt_max_items';
SET app.config_reason = '베타 1주차: 탐색 꽝 확률 하향';
UPDATE config.balance_config SET value = '0.30', updated_by = 'yoonseo' WHERE key = 'explore_miss_rate';   -- v1.7: 시드가 0.35라 다른 값으로 변경
RESET app.config_reason;
INSERT INTO _result
SELECT 'L-B2 수치 변경이 이력에 자동 기록', count(*) = 1, max(old_value::text) || ' → ' || max(new_value::text)
FROM config.balance_config_history WHERE key = 'explore_miss_rate' AND changed_by = 'yoonseo'
  AND reason = '베타 1주차: 탐색 꽝 확률 하향';
INSERT INTO _result
SELECT 'L-B3 관리자는 config 수정 가능, 이력은 수정 불가',
       has_table_privilege('app_config_admin','config.balance_config','UPDATE')
       AND NOT has_table_privilege('app_config_admin','config.balance_config_history','UPDATE'), '';

-- ---------- C. ai 기억 ----------
SELECT pg_temp.expect_ok  ('L-C1 기억 추출 완료 표시 + 기억 저장',
  $$UPDATE ai.chat_session SET ended_at = now(), memory_extracted_at = now() WHERE user_id = 1;
    INSERT INTO ai.memory_item (user_id, kind, content, source_session_id, importance)
    SELECT 1,'ROUTINE','아침에 달리는 편', id, 3 FROM ai.chat_session WHERE user_id = 1$$);
SELECT pg_temp.expect_fail('L-C2b 등록 안 된 기억 종류 불가',
  $$INSERT INTO ai.memory_item (user_id, kind, content) VALUES (1,'GOSSIP','x')$$);
SELECT pg_temp.expect_fail('L-C2 기억 중요도 1~5',
  $$INSERT INTO ai.memory_item (user_id, kind, content, importance) VALUES (1,'EVENT','x',9)$$);
INSERT INTO _result
SELECT 'L-C3 app_ai가 기억·호출 로그 사용 가능, 경제 스키마는 여전히 불가',
       has_table_privilege('app_ai','ai.memory_item','INSERT')
       AND has_table_privilege('app_ai','ai.llm_call_log','INSERT')
       AND NOT has_schema_privilege('app_ai','wallet','USAGE'), '';

-- ---------- 결과 ----------
SELECT CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS r, id, note FROM _result ORDER BY ok, id;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM _result WHERE NOT ok) THEN RAISE EXCEPTION '검증 실패 항목 있음 (later)'; END IF;
END $$;
