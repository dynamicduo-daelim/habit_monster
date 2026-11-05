-- =====================================================================
-- 5단계 검증 스크립트: 스키마 규칙 + 비즈니스 규칙 위반이 DB에서 막히는지
-- 실행: psql -v ON_ERROR_STOP=1 -f schema.sql -f seed.sql -f verify.sql   (v1.8)
-- MVP 이후 블록까지: … -f schema_later.sql -f verify.sql -f verify_later.sql
-- 각 검사는 PASS/FAIL을 결과 표로 출력하고, FAIL이 하나라도 있으면 마지막에 예외
-- v1.7: 이메일 고유·Apple 제외, 출석, 습관 기간(habit_period)·채운 날, 탐색 DUPLICATE/EXPIRED,
--       체크인 대사, 중복 요청 방지 키, 설정값 변경 검사 추가
-- v1.8 보충 10-28: 목표 기간은 등록한 날부터 (월요일 시작 검사 → 아무 요일이나 시작 가능 검사) · 목표 기간 일수 설정
-- v1.8: 시드 몬스터 28종 (id = 카테고리 순서). 검사가 쓰는 종 id를 새 번호로 —
--       1 운동 스타터(그대로) · 6 공부 스타터(옛 2) · 7 공부 비스타터(옛 3) · 10 식습관 스타터(옛 4) · 19 수면 스타터(옛 5).
--       S-2를 "스타터 없는 카테고리 0개" 검사로 (6개 카테고리 모두 스타터)
-- v1.9: 체크인 근거(evidence · rewarded_evidence 불변 · score_capped), 습관 타이머(habit_timer — 습관마다 하나 · 도는 것은
--       사용자당 하나 · 상태-시각 일치 · 끝난 날 기록), AI 호출 수(daily_call_count), 설정 키 8개
-- =====================================================================
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

-- ---------- 구조 검사 ----------
-- S-1 (v1.3) 스키마 간 FK = 허용 목록과 정확히 일치 (빠진 것도, 계획에 없는 것도 없어야 함)
CREATE TEMP TABLE _cross_fk_expected (src text, dst text);
INSERT INTO _cross_fk_expected VALUES
 ('habit.habit_user','identity.users'), ('goal.goal_user','identity.users'),
 ('wallet.wallet','identity.users'), ('monster.monster_user','identity.users'),
 ('shop.inventory','identity.users'), ('shop.purchase','identity.users'),
 ('shop.item_consumption','identity.users'), ('ai.chat_session','identity.users'),
 ('monster.monster_species','habit.category'), ('monster.explore_quota_category','habit.user_category'),
 ('monster.daily_explore_quota','habit.daily_checkin'), ('ai.chat_session','habit.daily_checkin'),
 ('ai.chat_session','monster.monster_species'),
 ('monster.monster_growth_log','shop.item_consumption'), ('monster.explore_log','shop.item_consumption'),
 ('monster.starter_grant','habit.user_category'),
 -- v1.7
 ('ai.checkin_dialogue','identity.users'), ('ai.checkin_dialogue','habit.checkin_submission'),
 ('api.idempotency_record','identity.users'),
 -- v1.9
 ('ai.daily_call_count','identity.users');
-- schema_later.sql을 적용한 DB라면 그 블록의 FK도 허용 목록에 포함
INSERT INTO _cross_fk_expected
SELECT * FROM (VALUES
 ('payment.payment_order','identity.users'), ('payment.entitlement','identity.users'),
 ('goal.goal_slot_grant','payment.entitlement'),
 ('ai.memory_item','identity.users'), ('ai.llm_call_log','identity.users')) v(src, dst)
WHERE to_regclass(v.src) IS NOT NULL;
CREATE TEMP VIEW _cross_fk_actual AS
SELECT DISTINCT tn.nspname || '.' || t.relname AS src, rn.nspname || '.' || r.relname AS dst
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace tn ON tn.oid = t.relnamespace
JOIN pg_class r ON r.oid = c.confrelid JOIN pg_namespace rn ON rn.oid = r.relnamespace
WHERE c.contype = 'f' AND t.relnamespace <> r.relnamespace;
INSERT INTO _result
SELECT 'S-1 스키마 간 FK = 허용 목록과 일치 (MVP 19쌍, 나중 블록 포함 24쌍)',
       NOT EXISTS (SELECT * FROM _cross_fk_actual EXCEPT SELECT * FROM _cross_fk_expected)
       AND NOT EXISTS (SELECT * FROM _cross_fk_expected EXCEPT SELECT * FROM _cross_fk_actual),
       (SELECT count(*) FROM _cross_fk_actual) || '쌍';
-- S-14 (v1.3) 닫힌 집합 enum의 CHECK 이름이 <테이블>_<컬럼>_check 규칙을 따름 (마이그레이션 한 줄로 교체 가능)
INSERT INTO _result
SELECT 'S-14 enum CHECK 이름 규칙', count(*) = 0, coalesce(string_agg(conname, ','), '')
FROM pg_constraint c
WHERE c.contype = 'c' AND pg_get_constraintdef(c.oid) LIKE '%= ANY (ARRAY[%'
  AND array_length(c.conkey, 1) = 1
  AND c.conname <> (SELECT relname FROM pg_class WHERE oid = c.conrelid) || '_'
                   || (SELECT attname FROM pg_attribute WHERE attrelid = c.conrelid AND attnum = c.conkey[1]) || '_check';
-- S-15 (v1.3) enum·코드 컬럼에 길이 제한 VARCHAR 없음: CHECK IN 대상 컬럼과 코드 테이블 FK 컬럼이 모두 text
INSERT INTO _result
SELECT 'S-15 enum·코드 컬럼은 TEXT', count(*) = 0, coalesce(string_agg(x, ','), '')
FROM (
  SELECT DISTINCT cl.relname || '.' || a.attname AS x
  FROM pg_constraint c
  JOIN pg_class cl ON cl.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = cl.relnamespace
  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
  WHERE n.nspname IN ('identity','habit','goal','wallet','shop','monster','config','ai','api','payment')
    AND ((c.contype = 'c' AND pg_get_constraintdef(c.oid) LIKE '%= ANY (ARRAY[%')
      OR (c.contype = 'f' AND a.atttypid IN ('text'::regtype, 'varchar'::regtype)))
    AND a.atttypid <> 'text'::regtype
) v;

-- S-2 시드: 모든 카테고리에 스타터 종이 있다 (v1.8: 6개 카테고리 모두. 최대 1종은 uq_species_starter)
INSERT INTO _result
SELECT 'S-2 모든 카테고리에 스타터 종', count(*) = 0,
       coalesce(string_agg(c.code, ','), '없음')
FROM habit.category c
WHERE NOT EXISTS (SELECT 1 FROM monster.monster_species s WHERE s.category_code = c.code AND s.is_starter);

-- S-3 monster_species.category_code가 모두 habit.category에 존재
INSERT INTO _result
SELECT 'S-3 종의 카테고리 코드 유효', count(*) = 0, count(*) || '건 불일치'
FROM monster.monster_species s
WHERE NOT EXISTS (SELECT 1 FROM habit.category c WHERE c.code = s.category_code);

-- S-13 v1.2: 아웃박스·복제본 테이블이 없어야 함 (단일 트랜잭션)
INSERT INTO _result
SELECT 'S-13 outbox/processed_event/복제본/ball_use 테이블 없음', count(*) = 0, coalesce(string_agg(table_schema||'.'||table_name, ','), '')
FROM information_schema.tables
WHERE table_name IN ('outbox_event','processed_event','monster_category_view','dex_milestone','ball_use');

-- S-21 (v1.7) 설정값: 변경·삭제·추가가 반영되었는지
INSERT INTO _result
SELECT 'S-21 설정값 v1.7 (경계 0시, 최대 레벨 20, 꽝 0.35, 완주율·60일 리셋 삭제, 탐색 가중치 추가)',
       (SELECT value FROM config.balance_config WHERE key = 'day_boundary_hour') = '0'::jsonb
   AND (SELECT value FROM config.balance_config WHERE key = 'category_max_level') = '20'::jsonb
   AND (SELECT value FROM config.balance_config WHERE key = 'explore_miss_rate') = '0.35'::jsonb
   AND NOT EXISTS (SELECT 1 FROM config.balance_config WHERE key IN ('period_completion_rate','period_reset_days'))
   AND (SELECT count(*) FROM config.balance_config
        WHERE key IN ('explore_rarity_weight','explore_unowned_multiplier','explore_daily_all_missed','idempotency_ttl_hours')) = 4,
       '';
-- S-21b (v1.8 보충 10-28) 목표 기간 일수
INSERT INTO _result
SELECT 'S-21b 목표 기간 일수 (주간 7 · 월간 30)',
       (SELECT value FROM config.balance_config WHERE key = 'weekly_goal_days') = '7'::jsonb
   AND (SELECT value FROM config.balance_config WHERE key = 'monthly_goal_days') = '30'::jsonb,
       '';
-- S-22 (v1.7) 탐색 가중치·포획률 키가 희귀도 1~3과 일치
INSERT INTO _result
SELECT 'S-22 희귀도 키 = 1·2·3 (등장 가중치, 포획률)',
       (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys((SELECT value FROM config.balance_config WHERE key = 'explore_rarity_weight')) k) = ARRAY['1','2','3']
   AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys((SELECT value FROM config.balance_config WHERE key = 'capture_rate')) k) = ARRAY['1','2','3'],
       '';
-- S-23 (v1.7) 종 해금 레벨이 카테고리 최대 레벨 이하
INSERT INTO _result
SELECT 'S-23 종 해금 레벨 ≤ category_max_level', count(*) = 0, count(*) || '종 위반'
FROM monster.monster_species
WHERE unlock_level > (SELECT value::int FROM config.balance_config WHERE key = 'category_max_level');

-- ---------- 테스트 데이터: 사용자 1명 (가입 트랜잭션 결과를 직접 재현) ----------
INSERT INTO identity.users (nickname, email) VALUES ('테스터', 'a@b.com');   -- id = 1
INSERT INTO identity.auth_credential (user_id, provider, provider_subject)
  VALUES (1, 'KAKAO', 'kakao-123');
INSERT INTO habit.habit_user (user_id) VALUES (1);
INSERT INTO goal.goal_user (user_id) VALUES (1);
INSERT INTO wallet.wallet (user_id) VALUES (1);
INSERT INTO monster.monster_user (user_id) VALUES (1);
INSERT INTO habit.user_category (user_id, category_code, opened_via) VALUES (1,'ex','INITIAL'),(1,'st','INITIAL');

-- ---------- identity ----------
SELECT pg_temp.expect_ok  ('같은 계정에 다른 로그인 수단 추가 가능 (계정 연결은 확장 단계, DB는 허용)',
  $$INSERT INTO identity.auth_credential (user_id, provider, provider_subject, password_hash)
    VALUES (1,'EMAIL','a@b.com','$2a$hash')$$);
SELECT pg_temp.expect_fail('v1.7 이메일 하나에 계정 하나 (다른 가입 방법이어도 불가)',
  $$INSERT INTO identity.users (nickname, email) VALUES ('선점', 'a@b.com')$$);
SELECT pg_temp.expect_fail('v1.7 이메일은 소문자로 저장',
  $$INSERT INTO identity.users (nickname, email) VALUES ('대문자', 'C@D.com')$$);
SELECT pg_temp.expect_ok  ('v1.7 이메일 없는 계정은 여러 개 가능 (카카오 이메일 미제공)',
  $$INSERT INTO identity.users (nickname) VALUES ('무이메일1'), ('무이메일2')$$);
SELECT pg_temp.expect_ok  ('v1.7 탈퇴로 비운 이메일은 다시 가입 가능',
  $$INSERT INTO identity.users (nickname, email) VALUES ('탈퇴예정', 'x@y.com');
    UPDATE identity.users SET status = 'WITHDRAWN', withdrawn_at = now(), email = NULL WHERE email = 'x@y.com';
    INSERT INTO identity.users (nickname, email) VALUES ('재가입', 'x@y.com')$$);
SELECT pg_temp.expect_fail('v1.7 Apple 로그인 제외 (등록 안 된 제공자)',
  $$INSERT INTO identity.auth_credential (user_id, provider, provider_subject) VALUES (1,'APPLE','apple-1')$$);
SELECT pg_temp.expect_fail('Q-20 같은 (제공자, 식별자) 중복 가입 차단',
  $$WITH u AS (INSERT INTO identity.users DEFAULT VALUES RETURNING id)
    INSERT INTO identity.auth_credential (user_id, provider, provider_subject)
    SELECT id,'KAKAO','kakao-123' FROM u$$);
SELECT pg_temp.expect_fail('이메일 수단은 비밀번호 필수',
  $$WITH u AS (INSERT INTO identity.users DEFAULT VALUES RETURNING id)
    INSERT INTO identity.auth_credential (user_id, provider, provider_subject)
    SELECT id,'EMAIL','p@q.com' FROM u$$);

-- ---------- habit: 출석 (v1.7) ----------
SELECT pg_temp.expect_ok  ('v1.7 출석 기록 + 연속 일수 갱신',
  $$INSERT INTO habit.attendance (user_id, attended_on) VALUES (1,'2026-10-04'),(1,'2026-10-05');
    UPDATE habit.habit_user SET current_streak = 2, longest_streak = 2, last_attended_date = '2026-10-05' WHERE user_id = 1$$);
SELECT pg_temp.expect_fail('v1.7 같은 날 출석 행은 1개 (하루 여러 번 호출 → ON CONFLICT DO NOTHING)',
  $$INSERT INTO habit.attendance (user_id, attended_on) VALUES (1,'2026-10-05')$$);
SELECT pg_temp.expect_fail('스트릭: 최장 기록 < 현재 연속 불가',
  $$UPDATE habit.habit_user SET current_streak = 3, longest_streak = 2 WHERE user_id = 1$$);

-- ---------- habit: 습관·기간 ----------
SELECT pg_temp.expect_fail('BR-02 열지 않은 카테고리에 습관 생성 불가',
  $$INSERT INTO habit.habit (user_id, category_code, measure_type_id, name) VALUES (1,'fd',7,'물')$$);
SELECT pg_temp.expect_fail('BR-03 다른 카테고리의 측정 항목 사용 불가',
  $$INSERT INTO habit.habit (user_id, category_code, measure_type_id, name) VALUES (1,'ex',4,'공부시간을 운동에')$$);
SELECT pg_temp.expect_fail('습관 이름 공백 불가',
  $$INSERT INTO habit.habit (user_id, category_code, measure_type_id, name) VALUES (1,'ex',1,'   ')$$);
SELECT pg_temp.expect_fail('v1.7 습관 상태는 ACTIVE·ENDED·STOPPED만 (옛 COMPLETED 불가)',
  $$INSERT INTO habit.habit (user_id, category_code, measure_type_id, name, status) VALUES (1,'ex',1,'러닝','COMPLETED')$$);
SELECT pg_temp.expect_ok  ('습관 등록 + 첫 기간 (seq 1)',
  $$INSERT INTO habit.habit (user_id, category_code, measure_type_id, name) VALUES
      (1,'ex',1,'아침 러닝'), (1,'st',4,'전공 공부'), (1,'st',5,'문제집 풀기');
    INSERT INTO habit.habit_period (habit_id, seq, period_code, period_days, daily_target, started_on)
    SELECT h.id, 1, v.pc, v.pd, v.tg, '2026-10-05'
    FROM (VALUES ('아침 러닝','D30',30,30),('전공 공부','D100',100,60),('문제집 풀기','D7',7,20)) v(nm,pc,pd,tg)
    JOIN habit.habit h ON h.name = v.nm$$);
SELECT pg_temp.expect_fail('BR-04 기간 목표값 0 불가',
  $$INSERT INTO habit.habit_period (habit_id, seq, period_code, period_days, daily_target, started_on)
    SELECT id, 2, 'D7', 7, 0, '2026-10-05' FROM habit.habit WHERE name = '아침 러닝'$$);
SELECT pg_temp.expect_fail('BR-05 기간 코드 제한 (D7/D30/D100만)',
  $$INSERT INTO habit.habit_period (habit_id, seq, period_code, period_days, daily_target, started_on)
    SELECT id, 2, '6M', 180, 30, '2026-10-05' FROM habit.habit WHERE name = '아침 러닝'$$);
SELECT pg_temp.expect_fail('BR-05 기간 코드와 일수 불일치 불가',
  $$INSERT INTO habit.habit_period (habit_id, seq, period_code, period_days, daily_target, started_on)
    SELECT id, 2, 'D100', 90, 30, '2026-10-05' FROM habit.habit WHERE name = '아침 러닝'$$);
SELECT pg_temp.expect_fail('v1.7 채우지 않은 기간은 습관당 1개 (진행 중 기간이 있으면 연장 불가)',
  $$INSERT INTO habit.habit_period (habit_id, seq, period_code, period_days, daily_target, started_on)
    SELECT id, 2, 'D7', 7, 30, '2026-10-06' FROM habit.habit WHERE name = '아침 러닝'$$);
SELECT pg_temp.expect_fail('v1.7 채운 날 > 기간 일수 불가',
  $$UPDATE habit.habit_period SET filled_days = 8 FROM habit.habit h
    WHERE h.id = habit_id AND h.name = '문제집 풀기'$$);
SELECT pg_temp.expect_fail('v1.7 기간을 채웠는데 종료일·보너스 없음 불가',
  $$UPDATE habit.habit_period SET filled_days = 7 FROM habit.habit h
    WHERE h.id = habit_id AND h.name = '문제집 풀기'$$);
SELECT pg_temp.expect_fail('v1.7 기간을 안 채웠는데 종료 처리 불가',
  $$UPDATE habit.habit_period SET filled_days = 3, ended_on = '2026-10-08', period_bonus = 10 FROM habit.habit h
    WHERE h.id = habit_id AND h.name = '문제집 풀기'$$);
SELECT pg_temp.expect_fail('v1.7 그만둔 습관은 그만둔 시각 필수',
  $$UPDATE habit.habit SET status = 'STOPPED' WHERE name = '문제집 풀기'$$);
INSERT INTO _result
SELECT 'S-18 config 기간 키 = 스키마 기간 코드',
       (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys((SELECT value FROM config.balance_config WHERE key = 'period_multiplier')) k)
     = ARRAY['D100','D30','D7']
   AND (SELECT value FROM config.balance_config WHERE key = 'period_days') = '{"D7":7,"D30":30,"D100":100}'::jsonb, '';

-- ---------- habit: 체크인 ----------
-- 첫 확정: 아침 러닝 30분(20점), 전공 공부 90분(25점) = 반영, 문제집 "못했어"(0점) = 반영 안 됨
-- 채운 날은 했다고 제출한 습관만 +1, 기간 점수는 반영 습관만 누적
SELECT pg_temp.expect_ok  ('BR-08 체크인 첫 확정 (보상 기준값·채운 날·기간 점수 기록)',
  $$INSERT INTO habit.daily_checkin (user_id, checkin_date, habit_count, total_score, counted_score)
    VALUES (1,'2026-10-05',3,45,45);
    INSERT INTO habit.checkin_submission (idempotency_key, daily_checkin_id, revision)
    SELECT '00000000-0000-0000-0000-000000000001', id, 1 FROM habit.daily_checkin WHERE checkin_date = '2026-10-05';
    INSERT INTO habit.habit_checkin
      (daily_checkin_id, habit_id, period_seq, value, target_snapshot, score, rewarded_value, rewarded_score, is_counted, is_filled)
    SELECT d.id, h.id, 1, v.val, v.tgt, v.sc, v.val, v.sc, v.cnt, v.val > 0
    FROM habit.daily_checkin d,
         (VALUES ('아침 러닝',30,30,20,true),('전공 공부',90,60,25,true),('문제집 풀기',0,20,0,false)) v(nm,val,tgt,sc,cnt)
    JOIN habit.habit h ON h.name = v.nm
    WHERE d.checkin_date = '2026-10-05';
    UPDATE habit.habit_period p SET filled_days = filled_days + 1, counted_score_sum = counted_score_sum + v.sc
    FROM habit.habit h, (VALUES ('아침 러닝',20),('전공 공부',25)) v(nm,sc)
    WHERE h.id = p.habit_id AND h.name = v.nm AND p.seq = 1$$);
SELECT pg_temp.expect_fail('v1.7 채운 날 여부는 첫 확정 값과 일치해야 함 ("못했어"인데 채운 날 불가)',
  $$INSERT INTO habit.daily_checkin (user_id, checkin_date, habit_count, total_score, counted_score)
    VALUES (1,'2026-10-06',1,0,0);
    INSERT INTO habit.habit_checkin
      (daily_checkin_id, habit_id, period_seq, value, target_snapshot, score, rewarded_value, rewarded_score, is_counted, is_filled)
    SELECT d.id, h.id, 1, 0, 30, 0, 0, 0, false, true
    FROM habit.daily_checkin d, habit.habit h WHERE d.checkin_date = '2026-10-06' AND h.name = '아침 러닝'$$);
SELECT pg_temp.expect_fail('v1.7 체크인 행의 기간은 그 습관의 기간이어야 함',
  $$INSERT INTO habit.daily_checkin (user_id, checkin_date, habit_count, total_score, counted_score)
    VALUES (1,'2026-10-06',1,20,20);
    INSERT INTO habit.habit_checkin
      (daily_checkin_id, habit_id, period_seq, value, target_snapshot, score, rewarded_value, rewarded_score, is_counted, is_filled)
    SELECT d.id, h.id, 2, 30, 30, 20, 30, 20, true, true
    FROM habit.daily_checkin d, habit.habit h WHERE d.checkin_date = '2026-10-06' AND h.name = '아침 러닝'$$);
SELECT pg_temp.expect_fail('BR-08 같은 날 체크인 행은 1개',
  $$INSERT INTO habit.daily_checkin (user_id, checkin_date, habit_count, total_score, counted_score)
    VALUES (1,'2026-10-05',1,20,20)$$);
SELECT pg_temp.expect_ok  ('v1.5 재제출: 최신 값만 갱신, 보상 기준값은 그대로',
  $$INSERT INTO habit.checkin_submission (idempotency_key, daily_checkin_id, revision)
    SELECT '00000000-0000-0000-0000-000000000002', id, 2 FROM habit.daily_checkin WHERE checkin_date = '2026-10-05';
    UPDATE habit.habit_checkin hc SET value = 40, score = 23
    FROM habit.habit h WHERE h.id = hc.habit_id AND h.name = '아침 러닝';
    UPDATE habit.daily_checkin SET total_score = 48, revision = 2, last_submitted_at = now()
    WHERE checkin_date = '2026-10-05'$$);
SELECT pg_temp.expect_fail('v1.5 재제출로 지급 골드(counted_score) 변경 불가',
  $$UPDATE habit.daily_checkin SET counted_score = 48 WHERE checkin_date = '2026-10-05'$$);
SELECT pg_temp.expect_fail('v1.5 재제출로 첫 확정 점수(rewarded_score) 변경 불가',
  $$UPDATE habit.habit_checkin SET rewarded_score = 23$$);
SELECT pg_temp.expect_fail('v1.5 재제출로 반영 여부(is_counted) 변경 불가',
  $$UPDATE habit.habit_checkin SET is_counted = false$$);
SELECT pg_temp.expect_fail('v1.7 재제출로 채운 날(is_filled) 변경 불가 ("못했어" → "했어"로 고쳐도 기간은 안 셈)',
  $$UPDATE habit.habit_checkin hc SET value = 20, score = 20, rewarded_value = 20, is_filled = true
    FROM habit.habit h WHERE h.id = hc.habit_id AND h.name = '문제집 풀기'$$);
SELECT pg_temp.expect_ok  ('v1.7 재제출로 "못했어" → "했어" 최신 값 수정은 가능 (통계용)',
  $$UPDATE habit.habit_checkin hc SET value = 20, score = 20
    FROM habit.habit h WHERE h.id = hc.habit_id AND h.name = '문제집 풀기'$$);
SELECT pg_temp.expect_fail('v1.7 재제출로 습관 수(habit_count) 변경 불가',
  $$UPDATE habit.daily_checkin SET habit_count = 4 WHERE checkin_date = '2026-10-05'$$);
SELECT pg_temp.expect_fail('멱등성 키 재전송 차단 (같은 제출 키)',
  $$INSERT INTO habit.checkin_submission (idempotency_key, daily_checkin_id, revision)
    SELECT '00000000-0000-0000-0000-000000000001', id, 3 FROM habit.daily_checkin WHERE checkin_date = '2026-10-05'$$);
SELECT pg_temp.expect_fail('같은 제출 차수 중복 불가',
  $$INSERT INTO habit.checkin_submission (idempotency_key, daily_checkin_id, revision)
    SELECT '00000000-0000-0000-0000-000000000003', id, 2 FROM habit.daily_checkin WHERE checkin_date = '2026-10-05'$$);
-- S-24 (v1.7) 기간 캐시 대사: 채운 날 = is_filled 행 수, 기간 점수 = 반영 행의 첫 확정 점수 합
INSERT INTO _result
SELECT 'S-24 기간 캐시 = 체크인 기록 (채운 날, 기간 점수)', count(*) = 0, count(*) || '건 불일치'
FROM habit.habit_period p
WHERE p.filled_days <> (SELECT count(*) FROM habit.habit_checkin c
                        WHERE c.habit_id = p.habit_id AND c.period_seq = p.seq AND c.is_filled)
   OR p.counted_score_sum <> (SELECT coalesce(sum(c.rewarded_score),0) FROM habit.habit_checkin c
                              WHERE c.habit_id = p.habit_id AND c.period_seq = p.seq AND c.is_counted);

-- ---------- v1.9 habit: 체크인 근거 · 점수 상한 ----------
INSERT INTO _result
SELECT 'v1.9 기존 체크인 행의 근거 기본값 = SHORT · 상한 안 걸림 (지금 보상과 같음)',
       NOT EXISTS (SELECT 1 FROM habit.habit_checkin
                   WHERE evidence <> 'SHORT' OR rewarded_evidence <> 'SHORT' OR score_capped), '';
SELECT pg_temp.expect_fail('v1.9 근거는 SHORT·DETAILED·VERIFIED만',
  $$UPDATE habit.habit_checkin SET evidence = 'PHOTO'$$);
SELECT pg_temp.expect_ok  ('v1.9 재제출로 최신 근거 · 상한 여부는 바뀔 수 있음',
  $$UPDATE habit.habit_checkin hc SET evidence = 'DETAILED', score_capped = true
    FROM habit.habit h WHERE h.id = hc.habit_id AND h.name = '아침 러닝'$$);
SELECT pg_temp.expect_fail('v1.9 재제출로 첫 확정 근거(rewarded_evidence) 변경 불가',
  $$UPDATE habit.habit_checkin SET rewarded_evidence = 'VERIFIED'$$);

-- ---------- v1.9 habit: 습관 타이머 ----------
-- 아침 러닝(운동 시간, 분) · 전공 공부(공부 시간, 분) 습관 사용
SELECT pg_temp.expect_ok  ('v1.9 타이머 시작 (RUNNING)',
  $$INSERT INTO habit.habit_timer (user_id, habit_id, business_date, status, started_at)
    SELECT 1, id, '2026-10-05', 'RUNNING', '2026-10-05 19:00+09' FROM habit.habit WHERE name = '아침 러닝'$$);
SELECT pg_temp.expect_fail('v1.9 같은 습관에 끝나지 않은 타이머 두 개 불가',
  $$INSERT INTO habit.habit_timer (user_id, habit_id, business_date, status, started_at, paused_at)
    SELECT 1, id, '2026-10-05', 'PAUSED', '2026-10-05 19:10+09', '2026-10-05 19:20+09' FROM habit.habit WHERE name = '아침 러닝'$$);
SELECT pg_temp.expect_fail('v1.9 도는 타이머는 사용자당 하나 (다른 습관도)',
  $$INSERT INTO habit.habit_timer (user_id, habit_id, business_date, status, started_at)
    SELECT 1, id, '2026-10-05', 'RUNNING', '2026-10-05 19:10+09' FROM habit.habit WHERE name = '전공 공부'$$);
SELECT pg_temp.expect_ok  ('v1.9 다른 습관에 일시정지한 타이머는 남아 있어도 됨',
  $$INSERT INTO habit.habit_timer (user_id, habit_id, business_date, status, started_at, paused_at)
    SELECT 1, id, '2026-10-05', 'PAUSED', '2026-10-05 18:00+09', '2026-10-05 18:30+09' FROM habit.habit WHERE name = '전공 공부'$$);
SELECT pg_temp.expect_fail('v1.9 일시정지 상태는 일시정지 시각 필수',
  $$UPDATE habit.habit_timer t SET paused_at = NULL FROM habit.habit h WHERE h.id = t.habit_id AND h.name = '전공 공부'$$);
SELECT pg_temp.expect_fail('v1.9 끝났는데 끝난 시각 · 기록 분 · 이유 없음 불가',
  $$UPDATE habit.habit_timer t SET status = 'STOPPED' FROM habit.habit h WHERE h.id = t.habit_id AND h.name = '아침 러닝'$$);
SELECT pg_temp.expect_fail('v1.9 끝난 이유에 MIDNIGHT 없음 (00시에 끊지 않음)',
  $$UPDATE habit.habit_timer t SET status = 'STOPPED', ended_at = '2026-10-06 00:00+09', counted_minutes = 60, end_reason = 'MIDNIGHT'
    FROM habit.habit h WHERE h.id = t.habit_id AND h.name = '아침 러닝'$$);
SELECT pg_temp.expect_fail('v1.9 기록 분은 하루(1440) 이하',
  $$UPDATE habit.habit_timer t SET status = 'STOPPED', ended_at = '2026-10-07 00:00+09', counted_minutes = 1441, end_reason = 'USER'
    FROM habit.habit h WHERE h.id = t.habit_id AND h.name = '아침 러닝'$$);
SELECT pg_temp.expect_fail('v1.9 끝난 시각은 시작 시각 이후',
  $$UPDATE habit.habit_timer t SET status = 'STOPPED', ended_at = '2026-10-05 18:00+09', counted_minutes = 0, end_reason = 'USER'
    FROM habit.habit h WHERE h.id = t.habit_id AND h.name = '아침 러닝'$$);
SELECT pg_temp.expect_ok  ('v1.9 날을 넘겨 끝내면 끝난 날 기록 (23:30 ~ 00:12 → 다음 날 42분)',
  $$UPDATE habit.habit_timer t SET started_at = '2026-10-05 23:30+09', status = 'STOPPED', ended_at = '2026-10-06 00:12+09',
      business_date = '2026-10-06', counted_minutes = 42, end_reason = 'USER'
    FROM habit.habit h WHERE h.id = t.habit_id AND h.name = '아침 러닝'$$);
SELECT pg_temp.expect_ok  ('v1.9 일시정지한 타이머를 습관 그만두기로 끝냄 · 끝난 습관은 새로 시작 가능',
  $$UPDATE habit.habit_timer t SET status = 'STOPPED', paused_seconds = 1800, paused_at = NULL,
      ended_at = '2026-10-05 19:00+09', counted_minutes = 30, end_reason = 'HABIT_STOPPED'
    FROM habit.habit h WHERE h.id = t.habit_id AND h.name = '전공 공부';
    INSERT INTO habit.habit_timer (user_id, habit_id, business_date, status, started_at)
    SELECT 1, id, '2026-10-06', 'RUNNING', '2026-10-06 07:00+09' FROM habit.habit WHERE name = '아침 러닝'$$);
INSERT INTO _result
SELECT 'v1.9 그날 기록 = 그날 끝난 타이머 합 (10-06 아침 러닝 42분, 도는 타이머는 안 셈)',
       (SELECT sum(counted_minutes) FROM habit.habit_timer t JOIN habit.habit h ON h.id = t.habit_id
        WHERE h.name = '아침 러닝' AND t.business_date = '2026-10-06' AND t.status = 'STOPPED') = 42, '';
UPDATE habit.habit_timer SET status = 'STOPPED', ended_at = '2026-10-06 07:30+09', counted_minutes = 30, end_reason = 'USER'
WHERE status = 'RUNNING';   -- 뒤 검사에 영향 없게 정리

-- ---------- habit: 기간 채움·연장·그만두기 (v1.7) ----------
-- 아래는 상태 전이 테스트라 체크인 행 없이 캐시 값을 직접 넣는다 (S-24 대사 이후에 실행)
SELECT pg_temp.expect_ok  ('v1.7 기간 채움 = 종료일·보너스 기록 + 습관 ENDED',
  $$UPDATE habit.habit_period p SET filled_days = 7, counted_score_sum = 140, ended_on = '2026-10-11', period_bonus = 28
    FROM habit.habit h WHERE h.id = p.habit_id AND h.name = '문제집 풀기' AND p.seq = 1;
    UPDATE habit.habit SET status = 'ENDED' WHERE name = '문제집 풀기'$$);
SELECT pg_temp.expect_ok  ('v1.7 연장 = 새 기간(seq 2, 목표값 변경) + 습관 ACTIVE',
  $$INSERT INTO habit.habit_period (habit_id, seq, period_code, period_days, daily_target, started_on)
    SELECT id, 2, 'D30', 30, 30, '2026-10-12' FROM habit.habit WHERE name = '문제집 풀기';
    UPDATE habit.habit SET status = 'ACTIVE' WHERE name = '문제집 풀기'$$);
SELECT pg_temp.expect_ok  ('v1.7 그만두기 = STOPPED + 시각 (진행 중 기간은 채우지 못한 채 남음)',
  $$UPDATE habit.habit SET status = 'STOPPED', stopped_at = now() WHERE name = '문제집 풀기'$$);
SELECT pg_temp.expect_ok  ('탈퇴 시 습관 이름 비우기 (NULL)',
  $$UPDATE habit.habit SET name = NULL WHERE name = '문제집 풀기'$$);
-- S-25 (v1.7) 습관 상태 ↔ 마지막 기간: ACTIVE면 마지막 기간 진행 중, ENDED면 마지막 기간 채움, 모든 습관에 기간 1개 이상
INSERT INTO _result
SELECT 'S-25 습관 상태 = 마지막 기간 상태', count(*) = 0, count(*) || '건 불일치'
FROM habit.habit h
LEFT JOIN LATERAL (SELECT * FROM habit.habit_period p WHERE p.habit_id = h.id ORDER BY seq DESC LIMIT 1) last ON true
WHERE last.habit_id IS NULL
   OR (h.status = 'ACTIVE' AND last.ended_on IS NOT NULL)
   OR (h.status = 'ENDED'  AND last.ended_on IS NULL);

-- ---------- habit: 해금권 ----------
SELECT pg_temp.expect_fail('해금권: 같은 기준값 두 번 지급 불가',
  $$INSERT INTO habit.category_unlock_ticket (user_id, milestone) VALUES (1,5),(1,5)$$);
SELECT pg_temp.expect_fail('해금권: 사용 카테고리는 열린 카테고리여야 함',
  $$INSERT INTO habit.category_unlock_ticket (user_id, milestone, used_category_code, used_at)
    VALUES (1,10,'md',now())$$);

-- ---------- goal ----------
SELECT pg_temp.expect_ok  ('v1.8 보충 목표 기간은 등록한 날부터 (수요일 시작 가능)',
  $$INSERT INTO goal.goal (user_id, goal_type, period_start, title) VALUES (1,'WEEKLY','2026-10-07','러닝');
    INSERT INTO goal.goal (user_id, goal_type, period_start, title) VALUES (1,'MONTHLY','2026-10-23','책')$$);
SELECT pg_temp.expect_fail('BR-22 제목 공백 불가',
  $$INSERT INTO goal.goal (user_id, goal_type, period_start, title) VALUES (1,'WEEKLY','2026-10-05','   ')$$);
SELECT pg_temp.expect_ok  ('목표 등록·완료',
  $$INSERT INTO goal.goal (user_id, goal_type, period_start, title) VALUES (1,'WEEKLY','2026-10-05','주 3회 러닝');
    UPDATE goal.goal SET status = 'COMPLETED', completed_at = now() WHERE title = '주 3회 러닝'$$);
SELECT pg_temp.expect_fail('Q-5 완료 목표 삭제 불가',
  $$UPDATE goal.goal SET status = 'DELETED', deleted_at = now() WHERE title = '주 3회 러닝'$$);
SELECT pg_temp.expect_fail('Q-5 완료 취소 불가 (완료 시각 남긴 채 ACTIVE)',
  $$UPDATE goal.goal SET status = 'ACTIVE' WHERE title = '주 3회 러닝'$$);
SELECT pg_temp.expect_fail('Q-5 완료 취소 불가 (상태·완료 시각을 함께 되돌림, v1.1 트리거)',
  $$UPDATE goal.goal SET status = 'ACTIVE', completed_at = NULL WHERE title = '주 3회 러닝'$$);
SELECT pg_temp.expect_ok  ('진행 중 목표는 수정·삭제 가능',
  $$INSERT INTO goal.goal (user_id, goal_type, period_start, title) VALUES (1,'WEEKLY','2026-10-05','전공 2챕터');
    UPDATE goal.goal SET title = '전공 3챕터' WHERE title = '전공 2챕터';
    UPDATE goal.goal SET status = 'DELETED', deleted_at = now() WHERE title = '전공 3챕터'$$);
SELECT pg_temp.expect_fail('삭제된 목표 복구 불가',
  $$UPDATE goal.goal SET status = 'ACTIVE', deleted_at = NULL WHERE title = '전공 3챕터'$$);
SELECT pg_temp.expect_fail('유료 슬롯은 주간 목표만',
  $$INSERT INTO goal.goal (user_id, goal_type, period_start, title, is_paid_slot) VALUES (1,'MONTHLY','2026-10-01','책',true)$$);
SELECT pg_temp.expect_ok  ('v1.7 탈퇴 시 목표 제목 비우기 (완료 목표도 상태는 그대로)',
  $$UPDATE goal.goal SET title = NULL, detail = NULL WHERE title = '주 3회 러닝'$$);

-- ---------- wallet ----------
SELECT pg_temp.expect_ok  ('적립 + 원장',
  $$UPDATE wallet.wallet SET balance = balance + 45 WHERE user_id = 1;
    INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id)
    VALUES (1,45,45,'CHECKIN','1')$$);
SELECT pg_temp.expect_fail('BR-31 같은 사유·참조 ID 중복 적립 차단',
  $$INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id)
    VALUES (1,45,90,'CHECKIN','1')$$);
SELECT pg_temp.expect_ok  ('v1.7 기간 보너스 원장 (ref_id = habit_period.id)',
  $$UPDATE wallet.wallet SET balance = balance + 28 WHERE user_id = 1;
    INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id)
    SELECT 1, 28, 73, 'PERIOD_BONUS', p.id::text FROM habit.habit_period p WHERE p.period_bonus = 28$$);
SELECT pg_temp.expect_fail('BR-33 잔액 음수 불가',
  $$UPDATE wallet.wallet SET balance = balance - 1000 WHERE user_id = 1$$);
SELECT pg_temp.expect_fail('구매 차감은 음수여야 함',
  $$INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id)
    VALUES (1,20,65,'SHOP_PURCHASE','p1')$$);
SELECT pg_temp.expect_fail('v1.2 SHOP_REFUND 사유 없음 (보상 흐름 제거, 환불은 ADJUST)',
  $$INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id)
    VALUES (1,20,65,'SHOP_REFUND','p1')$$);
SELECT pg_temp.expect_fail('0골드 적립은 원장에 쓰지 않음 (호출 쪽이 건너뜀)',
  $$INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id)
    VALUES (1,0,73,'CHECKIN','2')$$);
SELECT pg_temp.expect_fail('ADJUST는 사유(memo) 필수',
  $$INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id)
    VALUES (1,-5,68,'ADJUST','ops-1')$$);
SELECT pg_temp.expect_ok  ('ADJUST 차감 (운영 보정)',
  $$UPDATE wallet.wallet SET balance = balance - 5 WHERE user_id = 1;
    INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id, memo)
    VALUES (1,-5,68,'ADJUST','ops-1','중복 지급 버그 회수')$$);

-- ---------- shop ----------
SELECT pg_temp.expect_fail('BR-43 보유 수량 음수 불가',
  $$INSERT INTO shop.inventory (user_id, item_code, quantity) VALUES (1,'POTION_S',-1)$$);
SELECT pg_temp.expect_fail('구매 총액 = 단가 × 수량',
  $$INSERT INTO shop.purchase (user_id, item_code, quantity, unit_price, total_price, idempotency_key)
    VALUES (1,'POTION_S',2,20,30,'00000000-0000-0000-0000-0000000000b1')$$);
SELECT pg_temp.expect_fail('소모 키 재사용 차단 (재시도 이중 차감 방지)',
  $$INSERT INTO shop.item_consumption (user_id, item_code, quantity, consumer_key) VALUES
    (1,'BALL',1,'BALL:x'),(1,'BALL',1,'BALL:x')$$);
SELECT pg_temp.expect_ok  ('구매 = 원장 차감 + 구매 기록 + 가방 증가 (한 트랜잭션)',
  $$UPDATE wallet.wallet SET balance = balance - 20 WHERE user_id = 1;
    INSERT INTO shop.purchase (user_id, item_code, quantity, unit_price, total_price, idempotency_key)
    VALUES (1,'POTION_S',1,20,20,'00000000-0000-0000-0000-0000000000b2');
    INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id)
    SELECT 1,-20,48,'SHOP_PURCHASE',id::text FROM shop.purchase WHERE idempotency_key = '00000000-0000-0000-0000-0000000000b2';
    INSERT INTO shop.inventory (user_id, item_code, quantity) VALUES (1,'POTION_S',1)$$);
SELECT pg_temp.expect_fail('구매 재시도(같은 멱등 키) 차단',
  $$INSERT INTO shop.purchase (user_id, item_code, quantity, unit_price, total_price, idempotency_key)
    VALUES (1,'POTION_S',1,20,20,'00000000-0000-0000-0000-0000000000b2')$$);
SELECT pg_temp.expect_fail('v1.2 구매 상태값 없음 (실패하면 행이 남지 않음)',
  $$SELECT status FROM shop.purchase$$);

-- ---------- monster ----------
SELECT pg_temp.expect_fail('스타터 종은 카테고리당 1종',
  $$INSERT INTO monster.monster_species (id, code, category_code, name, rarity, unlock_level, dex_no, description, is_starter)
    VALUES (99,'x','ex','중복스타터',1,1,99,'-',true)$$);
SELECT pg_temp.expect_ok  ('초기 몬스터 지급: 운동 카테고리 (대화 상대)',
  $$WITH m AS (INSERT INTO monster.user_monster (user_id, species_id, affection, location, is_partner, acquired_via)
               VALUES (1,1,3,'FIELD',true,'STARTER') RETURNING id)
    INSERT INTO monster.starter_grant (user_id, category_code, user_monster_id, species_id) SELECT 1,'ex',id,1 FROM m;
    INSERT INTO monster.dex_entry (user_id, species_id) VALUES (1,1)$$);
SELECT pg_temp.expect_fail('다른 카테고리 종을 초기 몬스터로 지급 불가 (수면 종을 공부 카테고리에)',
  $$WITH m AS (INSERT INTO monster.user_monster (user_id, species_id, location, acquired_via)
               VALUES (1,19,'BAG','STARTER') RETURNING id)
    INSERT INTO monster.starter_grant (user_id, category_code, user_monster_id, species_id) SELECT 1,'st',id,19 FROM m$$);
SELECT pg_temp.expect_ok  ('v1.5 초기 몬스터 지급: 공부 카테고리 (카테고리마다 1마리)',
  $$WITH m AS (INSERT INTO monster.user_monster (user_id, species_id, affection, location, acquired_via)
               VALUES (1,6,3,'FIELD','STARTER') RETURNING id)
    INSERT INTO monster.starter_grant (user_id, category_code, user_monster_id, species_id) SELECT 1,'st',id,6 FROM m;
    INSERT INTO monster.dex_entry (user_id, species_id) VALUES (1,6)$$);
SELECT pg_temp.expect_fail('같은 카테고리 초기 몬스터 두 번 불가',
  $$INSERT INTO monster.monster_species (id, code, category_code, name, rarity, unlock_level, dex_no, description)
    VALUES (90,'test_ex','ex','테스트종',1,1,90,'-');
    WITH m AS (INSERT INTO monster.user_monster (user_id, species_id, location, acquired_via)
               VALUES (1,90,'BAG','STARTER') RETURNING id)
    INSERT INTO monster.starter_grant (user_id, category_code, user_monster_id, species_id) SELECT 1,'ex',id,90 FROM m$$);
SELECT pg_temp.expect_fail('열지 않은 카테고리에 초기 몬스터 불가 (스키마 간 FK)',
  $$WITH m AS (INSERT INTO monster.user_monster (user_id, species_id, location, acquired_via)
               VALUES (1,10,'BAG','STARTER') RETURNING id)
    INSERT INTO monster.starter_grant (user_id, category_code, user_monster_id, species_id) SELECT 1,'fd',id,10 FROM m$$);
SELECT pg_temp.expect_fail('BR-54 같은 종 두 마리 불가',
  $$INSERT INTO monster.user_monster (user_id, species_id, location, acquired_via) VALUES (1,1,'BAG','EXPLORE')$$);
SELECT pg_temp.expect_fail('BR-61 대화 상대 2마리 불가',
  $$INSERT INTO monster.user_monster (user_id, species_id, location, is_partner, acquired_via) VALUES (1,7,'FIELD',true,'EXPLORE')$$);
SELECT pg_temp.expect_fail('탐색 쿼터 없이 탐색 불가 (체크인 전)',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result)
    VALUES (1,'2026-10-05',1,'00000000-0000-0000-0000-0000000000c1','MISS')$$);
SELECT pg_temp.expect_ok  ('체크인 확정 트랜잭션에서 쿼터 생성',
  $$INSERT INTO monster.daily_explore_quota (user_id, quota_date, base_count, source_checkin_id) VALUES (1,'2026-10-05',3,1);
    INSERT INTO monster.explore_quota_category VALUES (1,'2026-10-05','ex'),(1,'2026-10-05','st')$$);
SELECT pg_temp.expect_fail('같은 체크인으로 쿼터 재생성 불가',
  $$INSERT INTO monster.daily_explore_quota (user_id, quota_date, base_count, source_checkin_id) VALUES (1,'2026-10-06',3,1)$$);
SELECT pg_temp.expect_fail('BR-50 사용 횟수 > 기본 횟수 불가',
  $$UPDATE monster.daily_explore_quota SET used_count = 4 WHERE user_id = 1$$);

-- ---------- v1.7 탐색: 꽝 / 가진 종(볼 없이 골드) / 안 가진 종 → 포획·도망·건너뜀·만료 ----------
SELECT pg_temp.expect_ok  ('안 가진 종 등장 (처리 전)',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id)
    VALUES (1,'2026-10-05',1,'00000000-0000-0000-0000-0000000000c1','ENCOUNTER',7)$$);
SELECT pg_temp.expect_fail('처리 전 등장은 1건만 (다음 탐색 전에 닫음)',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id)
    VALUES (1,'2026-10-05',2,'00000000-0000-0000-0000-0000000000c2','ENCOUNTER',6)$$);
SELECT pg_temp.expect_fail('포획인데 볼 소모가 없으면 불가',
  $$UPDATE monster.explore_log SET outcome = 'CAPTURED', resolved_at = now(),
      user_monster_id = (SELECT max(id) FROM monster.user_monster) WHERE seq = 1 AND quota_date = '2026-10-05'$$);
SELECT pg_temp.expect_ok  ('포획 성공 = 볼 소모 + 개체 생성 + 도감 + 처리 (한 트랜잭션)',
  $$INSERT INTO shop.item_consumption (user_id, item_code, quantity, consumer_key) VALUES (1,'BALL',1,'CAPTURE:k1');
    WITH m AS (INSERT INTO monster.user_monster (user_id, species_id, location, acquired_via)
               VALUES (1,7,'FIELD','EXPLORE') RETURNING id)
    UPDATE monster.explore_log SET outcome = 'CAPTURED', resolved_at = now(),
      consumption_id = (SELECT id FROM shop.item_consumption WHERE consumer_key = 'CAPTURE:k1'),
      user_monster_id = (SELECT id FROM m)
    WHERE seq = 1 AND quota_date = '2026-10-05';
    INSERT INTO monster.dex_entry (user_id, species_id) VALUES (1,7) ON CONFLICT DO NOTHING$$);
SELECT pg_temp.expect_fail('처리 끝난 등장 결과 변경 불가',
  $$UPDATE monster.explore_log SET outcome = 'ESCAPED', user_monster_id = NULL WHERE seq = 1 AND quota_date = '2026-10-05'$$);
SELECT pg_temp.expect_fail('포획 재시도: 같은 볼 키는 소모 단계에서 차단',
  $$INSERT INTO shop.item_consumption (user_id, item_code, quantity, consumer_key) VALUES (1,'BALL',1,'CAPTURE:k1')$$);
SELECT pg_temp.expect_ok  ('도망 = 볼만 소모, 개체 없음, 등장 끝',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id)
    VALUES (1,'2026-10-05',2,'00000000-0000-0000-0000-0000000000c3','ENCOUNTER',6);
    INSERT INTO shop.item_consumption (user_id, item_code, quantity, consumer_key) VALUES (1,'BALL',1,'CAPTURE:k2');
    UPDATE monster.explore_log SET outcome = 'ESCAPED', resolved_at = now(),
      consumption_id = (SELECT id FROM shop.item_consumption WHERE consumer_key = 'CAPTURE:k2')
    WHERE seq = 2 AND quota_date = '2026-10-05'$$);
SELECT pg_temp.expect_ok  ('v1.7 가진 종 등장 = 볼 없이 골드 (원장 DUPLICATE, ref_id = explore_log.id)',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id, gold_awarded)
    VALUES (1,'2026-10-05',3,'00000000-0000-0000-0000-0000000000c4','DUPLICATE',1,15);
    UPDATE wallet.wallet SET balance = balance + 15 WHERE user_id = 1;
    INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id)
    SELECT 1, 15, (SELECT balance FROM wallet.wallet WHERE user_id = 1), 'DUPLICATE', id::text
    FROM monster.explore_log WHERE seq = 3 AND quota_date = '2026-10-05'$$);
SELECT pg_temp.expect_fail('v1.7 가진 종 등장인데 골드 0 불가',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id)
    VALUES (1,'2026-10-05',9,'00000000-0000-0000-0000-0000000000c5','DUPLICATE',1)$$);
SELECT pg_temp.expect_fail('v1.7 가진 종 등장에 볼 소모 불가',
  $$INSERT INTO shop.item_consumption (user_id, item_code, quantity, consumer_key) VALUES (1,'BALL',1,'CAPTURE:k9');
    INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id, gold_awarded, consumption_id)
    SELECT 1,'2026-10-05',9,'00000000-0000-0000-0000-0000000000c5','DUPLICATE',1,15, id
    FROM shop.item_consumption WHERE consumer_key = 'CAPTURE:k9'$$);
SELECT pg_temp.expect_fail('v1.7 가진 종 등장 결과 변경 불가 (골드 금액)',
  $$UPDATE monster.explore_log SET gold_awarded = 30 WHERE seq = 3 AND quota_date = '2026-10-05'$$);
SELECT pg_temp.expect_fail('v1.7 가진 종 등장을 포획 결과로 바꾸기 불가',
  $$UPDATE monster.explore_log SET result = 'ENCOUNTER', gold_awarded = 0 WHERE seq = 3 AND quota_date = '2026-10-05'$$);
SELECT pg_temp.expect_fail('v1.7 옛 포획 결과 DUPLICATE(볼 소모 후 골드) 불가',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id, outcome, resolved_at, gold_awarded)
    VALUES (1,'2026-10-05',9,'00000000-0000-0000-0000-0000000000c5','ENCOUNTER',1,'DUPLICATE',now(),15)$$);
SELECT pg_temp.expect_ok  ('건너뜀 = 볼 안 던지고 같은 날 다시 탐색, 보상 없음',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id)
    VALUES (1,'2026-10-05',4,'00000000-0000-0000-0000-0000000000c9','ENCOUNTER',6);
    UPDATE monster.explore_log SET outcome = 'SKIPPED', resolved_at = now() WHERE seq = 4 AND quota_date = '2026-10-05'$$);
SELECT pg_temp.expect_ok  ('v1.7 만료 = 처리 안 한 채 날짜가 바뀐 등장, 보상 없음',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id)
    VALUES (1,'2026-10-05',5,'00000000-0000-0000-0000-0000000000ca','ENCOUNTER',6);
    UPDATE monster.explore_log SET outcome = 'EXPIRED', resolved_at = now() WHERE seq = 5 AND quota_date = '2026-10-05'$$);
SELECT pg_temp.expect_fail('건너뜀·만료에 골드 불가',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id, outcome, resolved_at, gold_awarded)
    VALUES (1,'2026-10-05',9,'00000000-0000-0000-0000-0000000000cb','ENCOUNTER',6,'SKIPPED',now(),15)$$);
SELECT pg_temp.expect_fail('v1.6 골드 전환(CONVERTED) 없음',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id, outcome, resolved_at)
    VALUES (1,'2026-10-05',9,'00000000-0000-0000-0000-0000000000cc','ENCOUNTER',6,'CONVERTED',now())$$);
SELECT pg_temp.expect_fail('같은 볼로 두 등장을 처리 불가',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id)
    VALUES (1,'2026-10-05',6,'00000000-0000-0000-0000-0000000000c8','ENCOUNTER',6);
    UPDATE monster.explore_log SET outcome = 'ESCAPED', resolved_at = now(),
      consumption_id = (SELECT id FROM shop.item_consumption WHERE consumer_key = 'CAPTURE:k1')
    WHERE seq = 6 AND quota_date = '2026-10-05'$$);
SELECT pg_temp.expect_fail('꽝인데 종 기록 불가',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result, species_id)
    VALUES (1,'2026-10-05',8,'00000000-0000-0000-0000-0000000000c7','MISS',1)$$);
SELECT pg_temp.expect_ok  ('꽝',
  $$INSERT INTO monster.explore_log (user_id, quota_date, seq, idempotency_key, result)
    VALUES (1,'2026-10-05',7,'00000000-0000-0000-0000-0000000000cd','MISS')$$);
SELECT pg_temp.expect_ok  ('BR-59 쓰다듬기 1회',
  $$INSERT INTO monster.affection_action SELECT id,'2026-10-05','PET',2,now() FROM monster.user_monster WHERE user_id = 1 AND species_id = 1 AND acquired_via = 'STARTER'$$);
SELECT pg_temp.expect_fail('BR-59 같은 날 쓰다듬기 2회 불가',
  $$INSERT INTO monster.affection_action SELECT id,'2026-10-05','PET',2,now() FROM monster.user_monster WHERE user_id = 1 AND species_id = 1 AND acquired_via = 'STARTER'$$);
SELECT pg_temp.expect_ok  ('먹이 = 가방 소모 + 성장 기록 (같은 소모 키, 한 트랜잭션)',
  $$INSERT INTO shop.item_consumption (user_id, item_code, quantity, consumer_key) VALUES (1,'POTION_S',1,'FEED:f1');
    UPDATE shop.inventory SET quantity = quantity - 1 WHERE user_id = 1 AND item_code = 'POTION_S';
    UPDATE monster.user_monster SET exp_total = exp_total + 20 WHERE user_id = 1 AND species_id = 1 AND acquired_via = 'STARTER';
    INSERT INTO monster.monster_growth_log (user_monster_id, consumption_id, exp_gained, exp_total_after, level_before, level_after)
    SELECT m.id, c.id, 20, 20, 1, 1 FROM monster.user_monster m, shop.item_consumption c
    WHERE m.user_id = 1 AND m.species_id = 1 AND m.acquired_via = 'STARTER' AND c.consumer_key = 'FEED:f1'$$);
SELECT pg_temp.expect_fail('먹이 재시도: 같은 소모 키는 소모 단계에서 차단',
  $$INSERT INTO shop.item_consumption (user_id, item_code, quantity, consumer_key) VALUES (1,'POTION_S',1,'FEED:f1')$$);
SELECT pg_temp.expect_fail('같은 소모 행으로 성장 두 번 기록 불가',
  $$INSERT INTO monster.monster_growth_log (user_monster_id, consumption_id, exp_gained, exp_total_after, level_before, level_after)
    SELECT m.id, c.id, 20, 40, 1, 1 FROM monster.user_monster m, shop.item_consumption c
    WHERE m.user_id = 1 AND m.species_id = 1 AND m.acquired_via = 'STARTER' AND c.consumer_key = 'FEED:f1'$$);
INSERT INTO _result
SELECT 'S-16 consumer_key는 shop.item_consumption 한 곳에만 존재 (v1.3)', count(*) = 1, string_agg(table_schema||'.'||table_name, ',')
FROM information_schema.columns WHERE column_name = 'consumer_key'
  AND table_schema IN ('identity','habit','goal','wallet','shop','monster','config','ai','api');
INSERT INTO _result
SELECT 'S-6 잔액 = 원장 합계 (BR-32, 구매 차감 포함)', w.balance = coalesce(sum(l.amount),0), w.balance || ' / ' || coalesce(sum(l.amount),0)
FROM wallet.wallet w LEFT JOIN wallet.wallet_ledger l ON l.user_id = w.user_id
WHERE w.user_id = 1 GROUP BY w.balance;
-- S-12 가방 대사: 수량 = 구매 합 − 소모 합 (보상 흐름 대신 대사 쿼리로 확인)
INSERT INTO _result
SELECT 'S-12 가방 수량 = 구매 − 소모', count(*) = 0, count(*) || '건 불일치'
FROM shop.inventory i
WHERE i.quantity <> coalesce((SELECT sum(quantity) FROM shop.purchase p WHERE p.user_id = i.user_id AND p.item_code = i.item_code),0)
                  - coalesce((SELECT sum(quantity) FROM shop.item_consumption c WHERE c.user_id = i.user_id AND c.item_code = i.item_code),0);
-- S-26 (v1.7) 가진 종 등장 골드 = 원장 DUPLICATE 기록
INSERT INTO _result
SELECT 'S-26 가진 종 등장 골드 = 원장 DUPLICATE', count(*) = 0, count(*) || '건 불일치'
FROM monster.explore_log e
WHERE e.result = 'DUPLICATE'
  AND NOT EXISTS (SELECT 1 FROM wallet.wallet_ledger l
                  WHERE l.reason_code = 'DUPLICATE' AND l.ref_id = e.id::text AND l.amount = e.gold_awarded);

-- ---------- v1.3 스키마 간 FK: 고아 행 차단 ----------
SELECT pg_temp.expect_fail('없는 사용자의 지갑 생성 불가',
  $$INSERT INTO wallet.wallet (user_id) VALUES (999999)$$);
SELECT pg_temp.expect_fail('없는 사용자의 구매 기록 불가',
  $$INSERT INTO shop.purchase (user_id, item_code, quantity, unit_price, total_price, idempotency_key)
    VALUES (999999,'BALL',1,50,50,'00000000-0000-0000-0000-0000000000e1')$$);
SELECT pg_temp.expect_fail('없는 카테고리의 몬스터 종 불가',
  $$INSERT INTO monster.monster_species (id, code, category_code, name, rarity, unlock_level, dex_no, description)
    VALUES (98,'ghost','zz','유령',1,1,98,'-')$$);
SELECT pg_temp.expect_fail('열지 않은 카테고리는 탐색 풀에 못 들어감',
  $$INSERT INTO monster.explore_quota_category VALUES (1,'2026-10-05','fd')$$);
SELECT pg_temp.expect_fail('없는 체크인으로 쿼터 생성 불가',
  $$INSERT INTO monster.daily_explore_quota (user_id, quota_date, base_count, source_checkin_id) VALUES (1,'2026-10-08',3,999999)$$);
SELECT pg_temp.expect_fail('없는 종을 대화 상대로 세션 생성 불가',
  $$INSERT INTO ai.chat_session (user_id, session_date, partner_species_code, affection_tier) VALUES (1,'2026-10-05','nope','LOW')$$);

-- ---------- v1.3 열린 집합: 코드 테이블에 INSERT 한 줄로 확장 ----------
SELECT pg_temp.expect_fail('등록 안 된 로그인 제공자 불가',
  $$INSERT INTO identity.auth_credential (user_id, provider, provider_subject) VALUES (1,'NAVER','naver-1')$$);
SELECT pg_temp.expect_ok  ('제공자 추가 = INSERT 한 줄 (제약 변경 없음, 긴 코드도 가능)',
  $$INSERT INTO identity.auth_provider (code, name) VALUES ('NAVER','네이버'), ('NAVER_WORKS_ENTERPRISE','네이버웍스');
    INSERT INTO identity.auth_credential (user_id, provider, provider_subject) VALUES (1,'NAVER','naver-1')$$);
SELECT pg_temp.expect_ok  ('원장 새 보상 사유 = INSERT 한 줄',
  $$INSERT INTO wallet.ledger_reason VALUES ('EVENT_REWARD','CREDIT','이벤트 보상');
    UPDATE wallet.wallet SET balance = balance + 10 WHERE user_id = 1;
    INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id)
    SELECT 1, 10, balance, 'EVENT_REWARD', 'ev-1' FROM wallet.wallet WHERE user_id = 1$$);
SELECT pg_temp.expect_fail('적립 전용 사유로 차감 불가 (방향 FK)',
  $$INSERT INTO wallet.wallet_ledger (user_id, amount, balance_after, reason_code, ref_id) VALUES (1,-10,20,'EVENT_REWARD','ev-2')$$);

-- ---------- v1.3 닫힌 집합: 한 문장 마이그레이션으로 값 추가 ----------
SELECT pg_temp.expect_fail('닫힌 집합: 정의되지 않은 교감 종류 불가',
  $$INSERT INTO monster.affection_action SELECT id,'2026-10-06','FEED',1,now() FROM monster.user_monster WHERE user_id = 1 AND species_id = 1 AND acquired_via = 'STARTER'$$);
SELECT pg_temp.expect_ok  ('닫힌 집합 값 추가 = ALTER 한 문장 (예측 가능한 제약 이름)',
  $$ALTER TABLE monster.affection_action
      DROP CONSTRAINT affection_action_action_type_check,
      ADD  CONSTRAINT affection_action_action_type_check CHECK (action_type IN ('PET','PLAY','FEED')) NOT VALID;
    INSERT INTO monster.affection_action SELECT id,'2026-10-06','FEED',1,now() FROM monster.user_monster WHERE user_id = 1 AND species_id = 1 AND acquired_via = 'STARTER'$$);

-- ---------- habit 측정 항목 ----------
SELECT pg_temp.expect_fail('범위값은 둘 다 있거나 둘 다 없어야 함 (v1.1)',
  $$INSERT INTO habit.measure_type VALUES (99,'ex','t','분','TARGET_RATIO',1,1,NULL,1,NULL,9)$$);

-- S-19 (v1.5) 초기 몬스터로 지급된 종은 그 카테고리의 스타터 종 (FK는 카테고리 소속까지만 보장)
INSERT INTO _result
SELECT 'S-19 초기 몬스터 = 카테고리 스타터 종', count(*) = 0, count(*) || '건 위반'
FROM monster.starter_grant g JOIN monster.monster_species s ON s.id = g.species_id
WHERE NOT s.is_starter;
-- S-20 (v1.5) 온보딩 단계 컬럼 없음 (마지막에 한 번에 저장)
INSERT INTO _result
SELECT 'S-20 users.onboarding_step 없음, onboarded_at 있음',
       NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='identity' AND table_name='users' AND column_name='onboarding_step')
   AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='identity' AND table_name='users' AND column_name='onboarded_at'), '';

-- ---------- 시드 무결성 ----------
INSERT INTO _result
SELECT 'S-7 형태: 종마다 3단계, 기본형 Lv.1, 단계별 레벨 증가', count(*) = 0, count(*) || '종 위반'
FROM monster.monster_species s
WHERE (SELECT count(*) FROM monster.monster_form f WHERE f.species_id = s.id) <> 3
   OR (SELECT min_level FROM monster.monster_form f WHERE f.species_id = s.id AND stage = 0) <> 1
   OR EXISTS (SELECT 1 FROM monster.monster_form a JOIN monster.monster_form b
              ON a.species_id = b.species_id AND b.stage = a.stage + 1
              WHERE a.species_id = s.id AND b.min_level <= a.min_level);

-- ---------- ai ----------
INSERT INTO ai.chat_session (user_id, session_date, partner_species_code, affection_tier)
VALUES (1,'2026-10-05','monkey','MID');
SELECT pg_temp.expect_fail('사용자 메시지는 위젯 입력만 (자유 텍스트 없음, A-1)',
  $$INSERT INTO ai.chat_message (session_id, seq, role, source, content)
    SELECT id, 1, 'USER', 'LLM', '했어' FROM ai.chat_session WHERE user_id = 1$$);
SELECT pg_temp.expect_ok  ('대사(LLM)·대체(TEMPLATE)·위젯 응답 기록',
  $$INSERT INTO ai.chat_message (session_id, seq, role, source, content)
    SELECT id, v.seq, v.role, v.src, v.txt FROM ai.chat_session,
      (VALUES (1,'BOT','LLM','오늘도 뛸 거지?'),(2,'USER','WIDGET','30분'),(3,'BOT','TEMPLATE','최고야!')) v(seq,role,src,txt)
    WHERE user_id = 1$$);

-- v1.7 체크인 대사: 제출 차수당 1개
SELECT pg_temp.expect_ok  ('v1.7 체크인 대사 저장 (revision 1, LLM)',
  $$INSERT INTO ai.checkin_dialogue (daily_checkin_id, revision, user_id, line_text, source)
    SELECT id, 1, 1, '오늘 30분이나 달렸구나!', 'LLM' FROM habit.daily_checkin WHERE checkin_date = '2026-10-05'$$);
SELECT pg_temp.expect_fail('v1.7 같은 revision에 대사 두 번 불가 (재요청은 저장값 반환)',
  $$INSERT INTO ai.checkin_dialogue (daily_checkin_id, revision, user_id, line_text, source)
    SELECT id, 1, 1, '다른 대사', 'LLM' FROM habit.daily_checkin WHERE checkin_date = '2026-10-05'$$);
SELECT pg_temp.expect_fail('v1.7 없는 제출 차수에는 대사 불가',
  $$INSERT INTO ai.checkin_dialogue (daily_checkin_id, revision, user_id, line_text, source)
    SELECT id, 9, 1, '대사', 'LLM' FROM habit.daily_checkin WHERE checkin_date = '2026-10-05'$$);
SELECT pg_temp.expect_fail('v1.7 대사 출처는 LLM·TEMPLATE만',
  $$INSERT INTO ai.checkin_dialogue (daily_checkin_id, revision, user_id, line_text, source)
    SELECT id, 2, 1, '대사', 'WIDGET' FROM habit.daily_checkin WHERE checkin_date = '2026-10-05'$$);

-- ---------- v1.9 ai: 해석 호출 수 ----------
SELECT pg_temp.expect_ok  ('v1.9 호출 수: 첫 호출은 1행, 같은 날 다시 부르면 +1 (한 문장 올리기)',
  $$INSERT INTO ai.daily_call_count (user_id, call_date, call_count) VALUES (1, '2026-10-05', 1)
    ON CONFLICT (user_id, call_date) DO UPDATE SET call_count = ai.daily_call_count.call_count + 1, updated_at = now()
      WHERE ai.daily_call_count.call_count < 60;
    INSERT INTO ai.daily_call_count (user_id, call_date, call_count) VALUES (1, '2026-10-05', 1)
    ON CONFLICT (user_id, call_date) DO UPDATE SET call_count = ai.daily_call_count.call_count + 1, updated_at = now()
      WHERE ai.daily_call_count.call_count < 60$$);
INSERT INTO _result
SELECT 'v1.9 호출 수 = 2', (SELECT call_count FROM ai.daily_call_count WHERE user_id = 1 AND call_date = '2026-10-05') = 2, '';
UPDATE ai.daily_call_count SET call_count = 60 WHERE user_id = 1 AND call_date = '2026-10-05';
SELECT pg_temp.expect_ok  ('v1.9 한도(60)에 닿은 뒤 올리기 시도 (오류 없이 0행)',
  $$INSERT INTO ai.daily_call_count (user_id, call_date, call_count) VALUES (1, '2026-10-05', 1)
    ON CONFLICT (user_id, call_date) DO UPDATE SET call_count = ai.daily_call_count.call_count + 1, updated_at = now()
      WHERE ai.daily_call_count.call_count < 60$$);
INSERT INTO _result
SELECT 'v1.9 한도에 닿으면 더 올라가지 않음 (행이 안 돌아옴 → 429)',
       (SELECT call_count FROM ai.daily_call_count WHERE user_id = 1 AND call_date = '2026-10-05') = 60, '';
SELECT pg_temp.expect_fail('v1.9 호출 수 음수 불가',
  $$UPDATE ai.daily_call_count SET call_count = -1$$);
SELECT pg_temp.expect_fail('v1.9 같은 사용자 · 같은 날 호출 수는 1행',
  $$INSERT INTO ai.daily_call_count (user_id, call_date, call_count) VALUES (1, '2026-10-05', 1)$$);
-- S-28 (v1.9) 설정 키
INSERT INTO _result
SELECT 'S-28 설정값 v1.9 (상한 20 · 계수 1.0/0.9/0.8 · 확인됨 1.2 · 타이머 240 · 호출 60 · 확신 0.6)',
       (SELECT value FROM config.balance_config WHERE key = 'self_report_max_score') = '20'::jsonb
   AND (SELECT value FROM config.balance_config WHERE key = 'exp_coef_ratio') = '1.0'::jsonb
   AND (SELECT value FROM config.balance_config WHERE key = 'exp_coef_range') = '0.9'::jsonb
   AND (SELECT value FROM config.balance_config WHERE key = 'exp_coef_binary') = '0.8'::jsonb
   AND (SELECT value FROM config.balance_config WHERE key = 'exp_coef_verified') = '1.2'::jsonb
   AND (SELECT value FROM config.balance_config WHERE key = 'timer_max_minutes') = '240'::jsonb
   AND (SELECT value FROM config.balance_config WHERE key = 'ai_daily_call_limit') = '60'::jsonb
   AND (SELECT value FROM config.balance_config WHERE key = 'ai_min_confidence') = '0.6'::jsonb
   AND (SELECT (value #>> '{}')::numeric FROM config.balance_config WHERE key = 'self_report_max_score')
       <= (SELECT (value #>> '{}')::numeric FROM config.balance_config WHERE key = 'score_max'), '';

-- ---------- api: 중복 요청 방지 키 (v1.7) ----------
SELECT pg_temp.expect_ok  ('v1.7 키 등록 (처리 중)',
  $$INSERT INTO api.idempotency_record (user_id, http_method, request_path, idempotency_key, request_hash, locked_until)
    VALUES (1,'POST','/api/v1/shop/purchases','00000000-0000-0000-0000-0000000000f1', repeat('a',64), now() + interval '30 seconds')$$);
SELECT pg_temp.expect_fail('v1.7 같은 사용자·메서드·경로·키는 한 행 (두 번째 요청은 기존 행으로 판단)',
  $$INSERT INTO api.idempotency_record (user_id, http_method, request_path, idempotency_key, request_hash, locked_until)
    VALUES (1,'POST','/api/v1/shop/purchases','00000000-0000-0000-0000-0000000000f1', repeat('b',64), now() + interval '30 seconds')$$);
SELECT pg_temp.expect_ok  ('v1.7 같은 키라도 경로가 다르면 별개 (사용자 + 메서드 + 경로 단위)',
  $$INSERT INTO api.idempotency_record (user_id, http_method, request_path, idempotency_key, request_hash, locked_until)
    VALUES (1,'POST','/api/v1/explores','00000000-0000-0000-0000-0000000000f1', repeat('a',64), now() + interval '30 seconds')$$);
SELECT pg_temp.expect_ok  ('v1.7 처리 완료 = 결과(상태 코드·본문) 저장, 업무 오류(422)도 저장',
  $$UPDATE api.idempotency_record SET status = 'COMPLETED', locked_until = NULL, completed_at = now(),
      response_status = 201, response_body = '{"purchaseId":1}'
    WHERE request_path = '/api/v1/shop/purchases';
    UPDATE api.idempotency_record SET status = 'COMPLETED', locked_until = NULL, completed_at = now(),
      response_status = 422, response_body = '{"code":"NO_EXPLORE_LEFT"}'
    WHERE request_path = '/api/v1/explores'$$);
SELECT pg_temp.expect_fail('v1.7 완료인데 결과 상태 코드 없음 불가',
  $$INSERT INTO api.idempotency_record (user_id, http_method, request_path, idempotency_key, request_hash, status, completed_at)
    VALUES (1,'PUT','/api/v1/checkins/today','00000000-0000-0000-0000-0000000000f2', repeat('a',64),'COMPLETED',now())$$);
SELECT pg_temp.expect_fail('v1.7 처리 중인데 처리 기한 없음 불가',
  $$INSERT INTO api.idempotency_record (user_id, http_method, request_path, idempotency_key, request_hash)
    VALUES (1,'PUT','/api/v1/checkins/today','00000000-0000-0000-0000-0000000000f3', repeat('a',64))$$);
SELECT pg_temp.expect_fail('v1.7 5xx 결과는 저장하지 않음',
  $$INSERT INTO api.idempotency_record (user_id, http_method, request_path, idempotency_key, request_hash, status, completed_at, response_status)
    VALUES (1,'PUT','/api/v1/checkins/today','00000000-0000-0000-0000-0000000000f4', repeat('a',64),'COMPLETED',now(),500)$$);
SELECT pg_temp.expect_fail('v1.7 조회(GET)에는 키를 쓰지 않음',
  $$INSERT INTO api.idempotency_record (user_id, http_method, request_path, idempotency_key, request_hash, locked_until)
    VALUES (1,'GET','/api/v1/me/status','00000000-0000-0000-0000-0000000000f5', repeat('a',64), now())$$);
SELECT pg_temp.expect_ok  ('v1.7 만료된 키는 물리 삭제 (원칙 7 예외)',
  $$DELETE FROM api.idempotency_record WHERE expires_at < now() + interval '25 hours'$$);

-- ---------- 권한 (v1.2: app_core / app_ai) ----------
INSERT INTO _result
SELECT 'S-9 app_ai는 경제 스키마(habit·wallet·monster)와 api에 접근 불가',
       NOT has_schema_privilege('app_ai','habit','USAGE')
       AND NOT has_schema_privilege('app_ai','wallet','USAGE')
       AND NOT has_schema_privilege('app_ai','monster','USAGE')
       AND NOT has_schema_privilege('app_ai','api','USAGE'), '';
-- S-17 (v1.3) app_ai는 habit 읽기 권한이 없어도 FK 검사는 통과 (FK 검사는 소유자 권한)
SET ROLE app_ai;
INSERT INTO ai.chat_session (user_id, session_date, partner_species_code, affection_tier, daily_checkin_id)
VALUES (1,'2026-10-05','wolf','MID',1);
INSERT INTO ai.checkin_dialogue (daily_checkin_id, revision, user_id, line_text, source)
VALUES (1, 2, 1, '다시 체크했구나!', 'TEMPLATE');
RESET ROLE;
INSERT INTO _result
SELECT 'S-17 app_ai: 읽기 권한 없이 스키마 간 FK 행 저장 가능 (대화 세션, 체크인 대사)',
       (SELECT count(*) FROM ai.chat_session WHERE daily_checkin_id = 1) = 1
   AND (SELECT count(*) FROM ai.checkin_dialogue WHERE daily_checkin_id = 1 AND revision = 2) = 1, '';
INSERT INTO _result
SELECT 'S-4 app_core는 ai 스키마 접근 불가 (탈퇴 시 삭제는 ai 모듈이 수행)',
       NOT has_schema_privilege('app_core','ai','USAGE'), '';
INSERT INTO _result
SELECT 'S-27 app_core는 중복 요청 키 읽기·쓰기·삭제 가능 (v1.7)',
       has_table_privilege('app_core','api.idempotency_record','INSERT')
   AND has_table_privilege('app_core','api.idempotency_record','UPDATE')
   AND has_table_privilege('app_core','api.idempotency_record','DELETE'), '';
INSERT INTO _result
SELECT 'S-5 app_core·app_ai는 config 읽기만 가능',
       has_table_privilege('app_core','config.balance_config','SELECT')
       AND NOT has_table_privilege('app_core','config.balance_config','UPDATE')
       AND has_table_privilege('app_ai','config.balance_config','SELECT')
       AND NOT has_table_privilege('app_ai','config.balance_config','UPDATE'), '';
CREATE TABLE habit.zz_probe (x int);   -- 마이그레이션으로 추가된 테이블 흉내
INSERT INTO _result
SELECT 'S-11 나중에 추가한 테이블에도 권한 자동 부여', has_table_privilege('app_core','habit.zz_probe','INSERT'), '';
DROP TABLE habit.zz_probe;

-- ---------- 결과 ----------
SELECT CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS r, id, note FROM _result ORDER BY ok, id;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM _result WHERE NOT ok) THEN RAISE EXCEPTION '검증 실패 항목 있음'; END IF;
END $$;
