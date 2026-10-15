import 'package:flutter/material.dart';

import '../core/constants/app_assets.dart';
import 'models.dart';

/// 고정 데이터: 카테고리, 몬스터 도감, 상점 아이템, 기간 배수.
/// 나중에 백엔드에서 내려받도록 바꿔도 모델은 그대로 쓸 수 있다.
class Catalog {
  Catalog._();

  static const List<HabitCategory> categories = [
    HabitCategory(id: 'ex', name: '운동', short: '운동', type: '불꽃', color: Color(0xFFFF7A4D), measures: [
      Measure('운동 시간', '분', 30),
      Measure('운동 횟수', '회', 3),
      Measure('자가진단', '점', 4),
    ]),
    HabitCategory(id: 'st', name: '공부/학습', short: '공부', type: '번개', color: Color(0xFFFFD24D), measures: [
      Measure('공부 시간', '분', 60),
      Measure('학습량', 'p', 20),
      Measure('자가진단', '점', 4),
    ]),
    HabitCategory(id: 'fd', name: '식습관/건강', short: '식습관', type: '풀', color: Color(0xFF7FD36B), measures: [
      Measure('물 섭취량', 'L', 2),
      Measure('준수한 끼니', '끼', 3),
      Measure('영양제/약 섭취', 'OX', 1),
      Measure('야식 안 하기', 'OX', 1),
      Measure('자가진단', '점', 4),
    ]),
    HabitCategory(id: 'md', name: '명상/마음챙김', short: '명상', type: '물', color: Color(0xFF5FC9E8), measures: [
      Measure('명상 시간', '분', 10),
      Measure('일기 쓰기', 'OX', 1),
      Measure('독서', 'OX', 1),
      Measure('자가진단', '점', 4),
    ]),
    HabitCategory(id: 'sl', name: '수면', short: '수면', type: '달빛', color: Color(0xFFA99BF5), measures: [
      Measure('수면 시간', 'h', 7, range: 1),
      Measure('미라클 모닝', 'OX', 1),
    ]),
    HabitCategory(id: 'mn', name: '절약/재테크', short: '절약', type: '금속', color: Color(0xFFC9C6D8), measures: [
      Measure('불필요한 소비 안 하기', 'OX', 1),
      Measure('저축액', '원', 10000),
    ]),
  ];

  static HabitCategory category(String id) => categories.firstWhere((c) => c.id == id);

  static const List<MonsterSpecies> species = [
    MonsterSpecies(
      id: 'wolf', categoryId: 'ex', name: '잿불 늑대', rarity: '희귀', unlockLevel: 1, asset: AppAssets.wolf, fieldHeight: 76, facesLeft: true,
      description: '아침마다 달리는 사람 곁에 나타난다. 꼬리 끝 불꽃은 주인의 운동량만큼 커진다.',
      lines: {
        AffectionTier.low: ['…흥. 뭘 봐?', '네가 달리는 건 아직 못 봤는데.', '가까이 오지 마. 뜨거우니까.'],
        AffectionTier.mid: ['오늘도 뛸 거지? 따라갈게.', '땀 냄새, 나쁘지 않아.', '어제보다 발소리가 가벼워졌네.'],
        AffectionTier.high: ['네가 달리면 내 불꽃도 커져!', '같이라면 어디까지든 달릴 수 있어.', '…쓰다듬어 줘도 돼. 특별히.'],
      },
    ),
    MonsterSpecies(
      id: 'spark', categoryId: 'st', name: '찌릿 쥐', rarity: '흔함', unlockLevel: 1, asset: AppAssets.spark, fieldHeight: 72, facesLeft: true,
      description: '책장 넘기는 소리를 좋아한다. 집중할수록 볼에서 작은 전기가 톡톡 튄다.',
      lines: {
        AffectionTier.low: ['찌릿…? 누구세요?', '책은… 펴긴 했어?', '(볼이 조금 찌릿거린다)'],
        AffectionTier.mid: ['찌릿! 오늘 공부했어?', '책장 넘기는 소리 좋아.', '집중하면 볼이 찌릿찌릿해져!'],
        AffectionTier.high: ['집중하는 네 옆이 제일 좋아!', '우리 오늘도 찌릿하게 해보자!', '너 오면 꼬리가 저절로 흔들려!'],
      },
    ),
    MonsterSpecies(
      id: 'chick', categoryId: 'st', name: '번쩍 병아리', rarity: '보통', unlockLevel: 3, asset: AppAssets.chick, fieldHeight: 70,
      description: '머리 위 번개 깃털은 집중력의 증거. 오래 공부한 날엔 밤새 반짝인다.',
      lines: {
        AffectionTier.low: ['삐약…?', '(경계 중)', '…번쩍?'],
        AffectionTier.mid: ['삐약! 번쩍!', '오늘 몇 페이지 읽었어?', '머리 위 번개는 집중력의 증거야.'],
        AffectionTier.high: ['너 덕분에 번개가 밝아졌어!', '삐약삐약! 최고야!', '계속 옆에 있을래!'],
      },
    ),
    MonsterSpecies(
      id: 'sprout', categoryId: 'fd', name: '새싹냥', rarity: '흔함', unlockLevel: 1, asset: AppAssets.sprout, fieldHeight: 68,
      description: '물을 잘 마시는 사람 곁에서 잎사귀가 윤기 난다. 야식 냄새를 아주 싫어한다.',
      lines: {
        AffectionTier.low: ['냥.', '물… 마셨어?', '(잎사귀를 숨긴다)'],
        AffectionTier.mid: ['야식 참았지? 기특해.', '잎사귀가 반짝반짝, 냥.', '오늘 물 몇 잔 마셨어?'],
        AffectionTier.high: ['건강한 네가 좋아, 냥!', '오늘도 같이 잘 먹자, 냥~', '네 옆이면 잎이 쑥쑥 자라!'],
      },
    ),
    MonsterSpecies(
      id: 'moon', categoryId: 'sl', name: '그믐 꼬마', rarity: '보통', unlockLevel: 1, asset: AppAssets.moon, fieldHeight: 72,
      description: '일찍 잠드는 사람의 꿈속을 산책한다. 낮에는 대부분 꾸벅꾸벅 졸고 있다.',
      lines: {
        AffectionTier.low: ['…졸려.', '…', '(하품)'],
        AffectionTier.mid: ['일찍 자면 달이 커져.', '어젯밤 푹 잤어?', '오늘은 몇 시에 잘 거야?'],
        AffectionTier.high: ['네 꿈속에 놀러 갈게.', '오늘 밤도 같이 자자.', '네 옆이 제일 포근해.'],
      },
    ),
  ];

  static MonsterSpecies speciesById(String id) => species.firstWhere((s) => s.id == id);

  /// 카테고리별 첫 파트너 후보 (그림이 없는 카테고리는 null).
  static const Map<String, String?> starters = {
    'ex': 'wolf', 'st': 'spark', 'fd': 'sprout', 'sl': 'moon', 'md': null, 'mn': null,
  };

  static const List<ShopItem> items = [
    ShopItem(id: 's', name: '하급 경험치 물약', short: '하급', price: 20, exp: 20, asset: AppAssets.potionSmall),
    ShopItem(id: 'm', name: '중급 경험치 물약', short: '중급', price: 90, exp: 100, asset: AppAssets.potionMedium),
    ShopItem(id: 'l', name: '상급 경험치 물약', short: '상급', price: 400, exp: 500, asset: AppAssets.potionLarge),
  ];

  static const ShopItem seongsilBall =
      ShopItem(id: 'ball', name: '성실볼', short: '성실볼', price: 50, exp: 0, asset: AppAssets.seongsilBall);

  // ---------- 서버 코드 ↔ 앱 id (결정 D2) ----------
  // 카테고리(ex · st …) · 몬스터 종(wolf · spark …)은 앱 id가 DB 코드와 같다 (seed.sql).
  // 측정 항목은 카테고리 안 순서(measureIndex)가 DB `measure_type.sort_order − 1`과 같다.
  // 상점 아이템만 이름이 달라서 여기서 잇는다.

  /// DB `shop.shop_item.code` → 앱 아이템 id.
  static const Map<String, String> itemIdByServerCode = {'POTION_S': 's', 'POTION_M': 'm', 'POTION_L': 'l', 'BALL': 'ball'};

  /// 서버에 보낼 아이템 코드 (예: 하급 물약 → POTION_S).
  static String serverCodeOf(ShopItem item) =>
      itemIdByServerCode.entries.firstWhere((e) => e.value == item.id).key;

  /// 서버 아이템 코드 → 앱 아이템. 모르는 코드면 null.
  static ShopItem? itemByServerCode(String code) {
    final id = itemIdByServerCode[code];
    if (id == null) return null;
    return id == seongsilBall.id ? seongsilBall : items.where((i) => i.id == id).firstOrNull;
  }

  /// 습관 기간과 끝까지 지켰을 때의 보상 배수.
  // DB v1.4: 7일/30일/100일 (period_code D7/D30/D100, 배수는 config.period_multiplier)
  static const List<(String, double)> periods = [('7일', 1.2), ('30일', 1.5), ('100일', 2.0)];

  /// 기간 배수 표시 (예: ×1.2).
  static String periodMult(int i) => '×${periods[i].$2.toStringAsFixed(1)}';

  /// 온보딩 습관 추천: (이름, 측정 방식 index, 하루 목표).
  static const Map<String, List<(String, int, double)>> habitPresets = {
    'ex': [('아침 러닝', 0, 30), ('스쿼트', 1, 30), ('홈트 한 판', 0, 20)],
    'st': [('전공 공부', 0, 60), ('문제집 풀기', 1, 20), ('오늘 복습', 2, 4)],
    'fd': [('물 2L 마시기', 0, 2), ('세 끼 챙겨 먹기', 1, 3), ('영양제 먹기', 2, 1), ('야식 참기', 3, 1)],
    'md': [('10분 명상', 0, 10), ('감사 일기', 1, 1), ('자기 전 독서', 2, 1)],
    'sl': [('7시간 자기', 0, 7), ('6시 기상', 1, 1)],
    'mn': [('충동구매 안 하기', 0, 1), ('하루 저축', 1, 10000)],
  };

  /// 하루 목표 −/+ 버튼 한 번에 바뀌는 양 (단위별).
  static const Map<String, double> targetSteps = {
    '분': 5, '회': 1, '점': 1, 'L': 0.5, 'p': 5, '끼': 1, 'h': 0.5, '원': 5000,
  };

  /// 첫 파트너를 안 고르고 넘어갔을 때 쓰는 기본 길.
  static const List<String> defaultCategories = ['ex', 'st', 'fd'];

  static const List<String> professorIntro = [
    '어서 오게! 나는 몬스터의 습성을 연구하는 대림대 박사라네.',
    "이 세계의 몬스터들은 사람의 '성실함'에 반응해서 모습을 드러낸다네.",
    '매일 습관을 지키면 성실도가 쌓이고, 골드와 새로운 몬스터를 만날 수 있지.',
    '자, 먼저 어떤 길을 걸을지, 어떤 습관을 지킬지 정해보겠나?',
  ];
}
