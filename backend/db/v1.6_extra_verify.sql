-- v1.6에서 바뀐 규칙만 따로 확인 (schema.sql v1.6 + seed.sql 다음에 실행)
CREATE TEMP TABLE _result (id text, ok boolean, note text);
CREATE OR REPLACE FUNCTION pg_temp.expect_fail(_id text, _sql text) RETURNS void AS $$
BEGIN
  BEGIN
    EXECUTE _sql;
    INSERT INTO _result VALUES (_id, false, '막혀야 하는데 통과됨');
  EXCEPTION WHEN others THEN
    INSERT INTO _result VALUES (_id, true, SQLSTATE || ' ' || left(SQLERRM, 80));
  END;
END $$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION pg_temp.expect_ok(_id text, _sql text) RETURNS void AS $$
BEGIN
  BEGIN
    EXECUTE _sql;
    INSERT INTO _result VALUES (_id, true, 'ok');
  EXCEPTION WHEN others THEN
    INSERT INTO _result VALUES (_id, false, SQLERRM);
  END;
END $$ LANGUAGE plpgsql;

-- 사용자 1명 + 운동 카테고리 + 초기 몬스터(늑대) + 체크인 + 탐색 쿼터 + 볼 소모 2건
INSERT INTO identity.users (nickname) VALUES ('테스터');
INSERT INTO habit.habit_user (user_id) VALUES (1);
INSERT INTO goal.goal_user (user_id) VALUES (1);
INSERT INTO wallet.wallet (user_id) VALUES (1);
INSERT INTO monster.monster_user (user_id) VALUES (1);
INSERT INTO habit.user_category (user_id, category_code, opened_via) VALUES (1,'ex','INITIAL'),(1,'st','INITIAL');
INSERT INTO monster.user_monster (user_id, species_id, affection, location, is_partner, acquired_via) VALUES (1,1,3,'FIELD',true,'STARTER');
INSERT INTO habit.daily_checkin (user_id, checkin_date, habit_count, total_score, counted_score) VALUES (1,'2026-10-10',1,20,20);
INSERT INTO monster.daily_explore_quota (user_id, quota_date, base_count, source_checkin_id) VALUES (1,'2026-10-10',3,1);
INSERT INTO shop.item_consumption (user_id, item_code, quantity, consumer_key) VALUES (1,'BALL',1,'CAPTURE:a'),(1,'BALL',1,'CAPTURE:b');

SELECT pg_temp.expect_fail('X-1 같은 종 두 마리 불가 (종당 1마리 복원)',
  $$INSERT INTO monster.user_monster (user_id, species_id, location, acquired_via) VALUES (1,1,'BAG','EXPLORE')$$);

SELECT pg_temp.expect_ok('X-2 등장 (이미 가진 늑대)',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id)
    VALUES (1,'2026-10-10',1,'00000000-0000-0000-0000-0000000000a1','ENCOUNTER',1)$$);
SELECT pg_temp.expect_fail('X-3 옛 값 CONVERTED 불가',
  $$UPDATE monster.explore_log SET outcome = 'CONVERTED', resolved_at = now(), gold_awarded = 15 WHERE seq = 1$$);
SELECT pg_temp.expect_fail('X-4 DUPLICATE인데 볼 소모가 없으면 불가',
  $$UPDATE monster.explore_log SET outcome = 'DUPLICATE', resolved_at = now(), gold_awarded = 15 WHERE seq = 1$$);
SELECT pg_temp.expect_fail('X-5 DUPLICATE인데 골드 0 불가',
  $$UPDATE monster.explore_log SET outcome = 'DUPLICATE', resolved_at = now(),
      consumption_id = (SELECT id FROM shop.item_consumption WHERE consumer_key = 'CAPTURE:a') WHERE seq = 1$$);
SELECT pg_temp.expect_ok('X-6 중복 포획 = 볼 소모 + 골드 15 + 원장 DUPLICATE (개체 없음)',
  $$UPDATE monster.explore_log SET outcome = 'DUPLICATE', resolved_at = now(), gold_awarded = 15,
      consumption_id = (SELECT id FROM shop.item_consumption WHERE consumer_key = 'CAPTURE:a') WHERE seq = 1;
    UPDATE wallet.wallet SET balance = balance + 15 WHERE user_id = 1;
    INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id)
    SELECT 1, 15, 15, 'DUPLICATE', id::text FROM monster.explore_log WHERE seq = 1$$);
SELECT pg_temp.expect_fail('X-7 같은 탐색으로 중복 골드 두 번 불가 (원장 유일)',
  $$INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id)
    SELECT 1, 15, 30, 'DUPLICATE', id::text FROM monster.explore_log WHERE seq = 1$$);
SELECT pg_temp.expect_fail('X-8 옛 원장 사유 EXPLORE_GOLD 없음',
  $$INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id) VALUES (1,15,30,'EXPLORE_GOLD','x')$$);

SELECT pg_temp.expect_ok('X-9 등장 (번쩍 병아리)',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id)
    VALUES (1,'2026-10-10',2,'00000000-0000-0000-0000-0000000000a2','ENCOUNTER',3)$$);
SELECT pg_temp.expect_fail('X-10 넘기기인데 골드를 주면 불가',
  $$UPDATE monster.explore_log SET outcome = 'SKIPPED', resolved_at = now(), gold_awarded = 15 WHERE seq = 2$$);
SELECT pg_temp.expect_fail('X-11 넘기기인데 볼을 쓰면 불가',
  $$UPDATE monster.explore_log SET outcome = 'SKIPPED', resolved_at = now(),
      consumption_id = (SELECT id FROM shop.item_consumption WHERE consumer_key = 'CAPTURE:b') WHERE seq = 2$$);
SELECT pg_temp.expect_ok('X-12 넘기기 = 볼 · 골드 · 개체 없이 마감',
  $$UPDATE monster.explore_log SET outcome = 'SKIPPED', resolved_at = now() WHERE seq = 2$$);
SELECT pg_temp.expect_fail('X-13 넘긴 몬스터를 나중에 잡을 수 없음',
  $$UPDATE monster.explore_log SET outcome = 'ESCAPED',
      consumption_id = (SELECT id FROM shop.item_consumption WHERE consumer_key = 'CAPTURE:b') WHERE seq = 2$$);
SELECT pg_temp.expect_ok('X-14 넘긴 뒤 다음 탐색 가능 (처리 전 등장 없음)',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id)
    VALUES (1,'2026-10-10',3,'00000000-0000-0000-0000-0000000000a3','ENCOUNTER',3)$$);
SELECT pg_temp.expect_ok('X-15 새 종 포획 = 볼 + 개체',
  $$WITH m AS (INSERT INTO monster.user_monster (user_id, species_id, location, acquired_via) VALUES (1,3,'FIELD','EXPLORE') RETURNING id)
    UPDATE monster.explore_log SET outcome = 'CAPTURED', resolved_at = now(),
      consumption_id = (SELECT id FROM shop.item_consumption WHERE consumer_key = 'CAPTURE:b'),
      user_monster_id = (SELECT id FROM m) WHERE seq = 3$$);

SELECT CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS r, id, note FROM _result ORDER BY id;
