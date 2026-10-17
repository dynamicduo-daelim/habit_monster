-- =====================================================================
-- 습관 몬스터 — 마스터·설정 시드 (프로토타입 HTML 상수 기준)
-- v1.7 2026-10-15: API 명세 v4 반영 (하루 경계 0시, 카테고리 최대 레벨 20, 꽝 0.35, 탐색 가중치,
--                  완주율·60일 리셋 삭제, 가진 종 등장은 볼 없이 골드)
-- =====================================================================

-- 카테고리 (HTML CATS)
INSERT INTO habit.category (code, name, short_name, element, glyph, color, sort_order) VALUES
 ('ex','운동','운동','불꽃','炎','#ff7a4d',1),
 ('st','공부/학습','공부','번개','雷','#ffd24d',2),
 ('fd','식습관/건강','식습관','풀','草','#7fd36b',3),
 ('md','명상/마음챙김','명상','물','水','#5fc9e8',4),
 ('sl','수면','수면','달빛','月','#a99bf5',5),
 ('mn','절약/재테크','절약','금속','金','#c9c6d8',6);

-- 측정 항목 (HTML CATS.measures + STEP / 수면 시간만 RANGE: 답변 Q-3 후속)
-- max_value: 설명서 3-1 제안(입력 상한). 물 5L 외 값은 임시 [제안]
INSERT INTO habit.measure_type
 (id, category_code, name, unit, scoring_mode, default_target, step, max_value, range_below, range_above, sort_order) VALUES
 (1,'ex','운동 시간','분','TARGET_RATIO',30,5,600,NULL,NULL,1),
 (2,'ex','운동 횟수','회','TARGET_RATIO',3,1,100,NULL,NULL,2),
 (3,'ex','자가진단','점','TARGET_RATIO',4,1,5,NULL,NULL,3),
 (4,'st','공부 시간','분','TARGET_RATIO',60,5,900,NULL,NULL,1),
 (5,'st','학습량','p','TARGET_RATIO',20,5,1000,NULL,NULL,2),
 (6,'st','자가진단','점','TARGET_RATIO',4,1,5,NULL,NULL,3),
 (7,'fd','물 섭취량','L','TARGET_RATIO',2,0.5,5,NULL,NULL,1),
 (8,'fd','준수한 끼니','끼','TARGET_RATIO',3,1,5,NULL,NULL,2),
 (9,'fd','영양제/약 섭취','OX','BINARY',1,1,1,NULL,NULL,3),
 (10,'fd','야식 안 하기','OX','BINARY',1,1,1,NULL,NULL,4),
 (11,'fd','자가진단','점','TARGET_RATIO',4,1,5,NULL,NULL,5),
 (12,'md','명상 시간','분','TARGET_RATIO',10,5,300,NULL,NULL,1),
 (13,'md','일기 쓰기','OX','BINARY',1,1,1,NULL,NULL,2),
 (14,'md','독서','OX','BINARY',1,1,1,NULL,NULL,3),
 (15,'md','자가진단','점','TARGET_RATIO',4,1,5,NULL,NULL,4),
 (16,'sl','수면 시간','h','RANGE',7,0.5,16,1,1.5,1),
 (17,'sl','미라클 모닝','OX','BINARY',1,1,1,NULL,NULL,2),
 (18,'mn','불필요한 소비 안 하기','OX','BINARY',1,1,1,NULL,NULL,1),
 (19,'mn','저축액','원','TARGET_RATIO',10000,5000,10000000,NULL,NULL,2);

-- 추천 습관 (HTML PRESETS)
INSERT INTO habit.habit_preset (id, category_code, measure_type_id, name, default_target, sort_order) VALUES
 (1,'ex',1,'아침 러닝',30,1),(2,'ex',2,'스쿼트',30,2),(3,'ex',1,'홈트 한 판',20,3),
 (4,'st',4,'전공 공부',60,1),(5,'st',5,'문제집 풀기',20,2),(6,'st',6,'오늘 복습',4,3),
 (7,'fd',7,'물 2L 마시기',2,1),(8,'fd',8,'세 끼 챙겨 먹기',3,2),(9,'fd',9,'영양제 먹기',1,3),(10,'fd',10,'야식 참기',1,4),
 (11,'md',12,'10분 명상',10,1),(12,'md',13,'감사 일기',1,2),(13,'md',14,'자기 전 독서',1,3),
 (14,'sl',16,'7시간 자기',7,1),(15,'sl',17,'6시 기상',1,2),
 (16,'mn',18,'충동구매 안 하기',1,1),(17,'mn',19,'하루 저축',10000,2);

-- 상점 (HTML ITEMS + 성실볼)
INSERT INTO shop.shop_item (code, name, short_name, price, effect_type, effect_value, sort_order) VALUES
 ('POTION_S','하급 경험치 물약','하급',20,'MONSTER_EXP',20,1),
 ('POTION_M','중급 경험치 물약','중급',90,'MONSTER_EXP',100,2),
 ('POTION_L','상급 경험치 물약','상급',400,'MONSTER_EXP',500,3),
 ('BALL','성실볼','성실볼',50,'CAPTURE',1,4);   -- v1.5: 포획용

-- 몬스터 종 (HTML SPECIES 5종). v1.7: 해금 레벨은 카테고리 7종 기준 1/3/6/9/12/15/18 —
--   지금 시드는 카테고리당 1~2종뿐이라 1(스타터)·3(번쩍 병아리)만 쓰인다. 종이 확정되면 나머지 레벨을 채운다.
-- 도감 번호 = 카테고리 순서 × 6 + 슬롯 (HTML 규칙, 종 수 확정 시 재계산)
-- !! 명상(md)·절약(mn) 스타터 종은 아트·이름 미정 → 데이터 준비 전 시드 검증 쿼리가 실패해야 정상
INSERT INTO monster.monster_species
 (id, code, category_code, name, rarity, unlock_level, dex_no, description, is_starter, display_height, facing) VALUES
 (1,'wolf','ex','잿불 늑대',3,1,1,'아침마다 달리는 사람 곁에 나타난다. 꼬리 끝 불꽃은 주인의 운동량만큼 커진다.',true,76,'LEFT'),
 (2,'spark','st','찌릿 쥐',1,1,7,'책장 넘기는 소리를 좋아한다. 집중할수록 볼에서 작은 전기가 톡톡 튄다.',true,72,'LEFT'),
 (3,'chick','st','번쩍 병아리',2,3,8,'머리 위 번개 깃털은 집중력의 증거. 오래 공부한 날엔 밤새 반짝인다.',false,70,'FRONT'),
 (4,'sprout','fd','새싹냥',1,1,13,'물을 잘 마시는 사람 곁에서 잎사귀가 윤기 난다. 야식 냄새를 아주 싫어한다.',true,68,'FRONT'),
 (5,'moon','sl','그믐 꼬마',2,1,25,'일찍 잠드는 사람의 꿈속을 산책한다. 낮에는 대부분 꾸벅꾸벅 졸고 있다.',true,72,'FRONT');

-- 형태: MVP는 같은 이미지를 3단계에 사용 가능 (Q-14 가정)
INSERT INTO monster.monster_form (species_id, stage, min_level, image_url)
SELECT s.id, f.stage, f.min_level, '/monsters/' || s.code || '/' || f.stage || '.png'
FROM monster.monster_species s
CROSS JOIN (VALUES (0,1),(1,10),(2,20)) AS f(stage, min_level);

-- 대사 (HTML SPECIES.lines 일부 — 전체는 마이그레이션 스크립트로 적재)
INSERT INTO monster.species_line (species_id, affection_tier, line_text) VALUES
 (1,'LOW','…흥. 뭘 봐?'),(1,'MID','오늘도 뛸 거지? 따라갈게.'),(1,'HIGH','네가 달리면 내 불꽃도 커져!'),
 (2,'LOW','찌릿…? 누구세요?'),(2,'MID','찌릿! 오늘 공부했어?'),(2,'HIGH','집중하는 네 옆이 제일 좋아!');

-- 결제 상품은 schema_later.sql A 블록 (v1.2)

-- 밸런스 상수 (설명서 10장 + API 명세 v4)
-- v1.7 삭제: period_completion_rate (기간은 채운 날 수 기준), period_reset_days (미접속해도 채운 날 유지)
INSERT INTO config.balance_config (key, value, description) VALUES
 ('service_timezone',           '"Asia/Seoul"', '업무 날짜 계산 시간대 (사용자별 시간대 없음, v1.1)'),
 ('day_boundary_hour',          '0',          '하루 경계 시각 (Asia/Seoul). 주는 월요일, 월은 1일 같은 시각 시작 (v1.7: 4 → 0)'),
 ('category_select_min',        '1',          '온보딩 카테고리 최소 선택 수 (HTML)'),
 ('category_select_max',        '3',          '온보딩 카테고리 최대 선택 수'),
 ('category_exp_base',          '10',         '카테고리 레벨업 필요 EXP = base × 현재 레벨'),
 ('category_max_level',         '20',         '카테고리 최대 레벨 (v1.7: 7 → 20, 수치 설계 v1 전제)'),
 ('levelup_gold',               '20',         '카테고리 레벨업 골드'),
 ('dex_unlock_thresholds',      '[5,10,15]',  '도감 등록 수가 이 값에 도달할 때마다 해금권 1장'),
 ('max_active_habits',          '5',          '습관 개수 상한 (ACTIVE + ENDED 합계, v1.7)'),
 ('daily_counted_habits',       '3',          '하루 반영 습관 수 (점수 상위 N개, 동점은 등록 순서). 골드·카테고리 EXP·기간 점수 모두 적용'),
 ('score_target_hit',           '20',         'HTML 공식: 목표 달성 점수'),
 ('score_max',                  '25',         'HTML 공식: 최대 점수'),
 ('score_over_slope',           '10',         'HTML 공식: 초과 비율 1.0당 가산점'),
 ('score_binary_done',          '20',         'O/X 달성'),
 ('score_binary_miss',          '0',          'O/X 미달성 (HTML)'),
 ('gold_per_score',             '1',          '점수 1 = 1G'),
 ('period_multiplier',          '{"D7":1.2,"D30":1.5,"D100":2.0}', '기간 배수. 보너스 골드 = 기간 중 반영 점수 합 × (배수 − 1)'),
 ('period_days',                '{"D7":7,"D30":30,"D100":100}', '채워야 할 날 수 (habit.ck_period_days와 일치해야 함)'),
 ('weekly_goal_slots',          '3',          '주간 목표 기본 슬롯'),
 ('monthly_goal_slots',         '1',          '월간 목표 슬롯'),
 ('weekly_goal_gold',           '40',         '주간 목표 보상'),
 ('monthly_goal_gold',          '150',        '월간 목표 보상'),
 ('explore_daily_free',         '3',          '하루 기본 탐색'),
 ('explore_daily_all_missed',   '1',          '첫 제출이 전부 "못했어"인 날의 탐색 횟수 (v1.7)'),
 ('explore_miss_rate',          '0.35',       '탐색 꽝 확률 (v1.7 확정, 베타에서 튜닝)'),
 ('explore_rarity_weight',      '{"1":60,"2":30,"3":10}', '희귀도별 등장 가중치 [임시값, 베타 튜닝] (v1.7)'),
 ('explore_unowned_multiplier', '2.0',        '안 가진 종 등장 가중치 배수 [임시값, 베타 튜닝] (v1.7)'),
 ('duplicate_gold',             '15',         '탐색에서 가진 종이 등장하면 볼 없이 지급하는 골드 (v1.7)'),
 ('capture_rate',               '{"1":0.8,"2":0.6,"3":0.4}', '희귀도별 포획 확률, 실패 시 도망 (볼 사용 하루 상한 없음)'),
 ('monster_exp_per_level',      '125',        '개체 레벨당 EXP'),
 ('monster_max_level',          '20',         '개체 최대 레벨'),
 ('evolve_levels',              '[10,20]',    '1차·최종 진화 레벨'),
 ('field_max',                  '5',          '필드 최대 마리 수'),
 ('field_min',                  '1',          '필드 최소 마리 수'),
 ('affection_max',              '10',         '호감도 최대'),
 ('affection_tiers',            '{"MID":4,"HIGH":7}', '호감도 단계 하한'),
 ('affection_pet_gain',         '2',          '쓰다듬기 (하루 1회)'),
 ('affection_play_gain',        '1',          '놀아주기 (하루 1회)'),
 ('starter_affection',          '3',          '초기 몬스터 시작 호감도 (카테고리마다 1마리)'),
 ('freeze_after_days',          '7',          '동결 전환 미접속 일수 (동결 시 하락 대상은 I-07 미결)'),
 ('idempotency_ttl_hours',      '24',         '중복 요청 방지 키 보관 시간 (v1.7)'),
 ('idempotency_lock_seconds',   '30',         '처리 중(IN_PROGRESS) 키를 다른 요청이 다시 잡을 수 있게 되는 시간 [임시값] (v1.7)'),
 ('chat_message_retention_days','30',         '챗봇 대화 원문 보관 일수 (A-2)'),
 ('llm_timeout_ms',             '3000',       'Gemini 대사 생성 제한 시간, 초과 시 템플릿 대사'),
 ('llm_model',                  '"gemini"',   '대사 생성 모델 식별자 (배포 시 확정)');
-- memory_prompt_max_items는 schema_later.sql C 블록 (v1.2)
