import 'package:flutter/material.dart';

import '../core/constants/economy.dart';

/// 습관을 무엇으로 셀지 (예: 운동 시간 / 분 / 기본 목표 30).
/// 점수 방식 (DB `habit.measure_type.scoring_mode`): 목표 대비 비율 · O/X · 목표 ± 범위.
enum ScoringMode { targetRatio, binary, range }

class Measure {
  const Measure(this.label, this.unit, this.defaultTarget, {this.range});
  final String label;
  final String unit; // 'OX'면 했다/안 했다만 체크
  final double defaultTarget;

  /// 있으면 RANGE 방식: 목표 ± [range] 안이면 만점 (예: 수면 7시간 ± 1).
  final double? range;

  bool get isOX => unit == 'OX';
  ScoringMode get mode => isOX ? ScoringMode.binary : (range != null ? ScoringMode.range : ScoringMode.targetRatio);
}

class HabitCategory {
  const HabitCategory({
    required this.id,
    required this.name,
    required this.short,
    required this.type,
    required this.color,
    required this.measures,
  });
  final String id;
  final String name;
  final String short;
  final String type; // 몬스터 타입 이름 (불꽃, 번개 …)
  final Color color;
  final List<Measure> measures;
}

enum AffectionTier { low, mid, high }

AffectionTier tierOf(int affection) {
  if (affection >= 7) return AffectionTier.high;
  if (affection >= 4) return AffectionTier.mid;
  return AffectionTier.low;
}

/// 호감도 단계 이름: 서먹한 · 친해진 · 단짝.
String tierName(AffectionTier t) => const {
      AffectionTier.low: '서먹한',
      AffectionTier.mid: '친해진',
      AffectionTier.high: '단짝',
    }[t]!;

class MonsterSpecies {
  const MonsterSpecies({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.rarity,
    required this.unlockLevel,
    required this.asset,
    required this.description,
    required this.lines,
    this.facesLeft = false,
    this.fieldHeight = 72,
    this.evolvedAsset,
  });
  final String id;
  final String categoryId;
  final String name;
  final String rarity; // 흔함 / 보통 / 희귀
  final int unlockLevel; // 카테고리 레벨이 이 이상이면 탐색에 출현
  final String asset;
  final String description;
  final Map<AffectionTier, List<String>> lines; // 호감도 단계별 대사
  final bool facesLeft; // 걷는 방향에 따라 좌우 반전할 때 사용
  final double fieldHeight; // 홈 필드에서 그리는 높이(px)
  final String? evolvedAsset; // 1차 진화부터 쓰는 그림. 없으면 기본 그림 그대로

  /// 희귀도 별 개수 (흔함 1 · 보통 2 · 희귀 3).
  int get stars => const {'흔함': 1, '보통': 2, '희귀': 3}[rarity] ?? 1;

  /// 이 레벨일 때 보여 줄 그림: 1차 진화 레벨부터 진화 그림 (있으면).
  String assetAt(int level) =>
      evolvedAsset != null && level >= Economy.firstEvolutionLevel ? evolvedAsset! : asset;
}

/// 플레이어가 가진 몬스터 한 마리.
class OwnedMonster {
  OwnedMonster({
    required this.uid,
    required this.speciesId,
    this.level = 1,
    this.exp = 0,
    this.affection = 0,
    this.inField = true,
    this.pettedToday = false,
    this.playedToday = false,
    this.draggedToday = false,
  });
  final String uid;
  final String speciesId;
  int level;
  int exp;
  int affection;
  bool inField;
  bool pettedToday;
  bool playedToday;
  bool draggedToday; // 오늘 홈 필드에서 끌어 옮겨 호감도를 받았는지

  String get stage {
    if (level >= Economy.finalEvolutionLevel) return '최종형';
    if (level >= Economy.firstEvolutionLevel) return '1차 진화';
    return '기본형';
  }

  /// 경험치를 넣고 레벨업을 처리한다. 올라간 레벨 수를 돌려준다.
  int addExp(int amount) {
    final before = level;
    exp += amount;
    while (exp >= Economy.expPerLevel && level < Economy.finalEvolutionLevel) {
      exp -= Economy.expPerLevel;
      level += 1;
    }
    if (level >= Economy.finalEvolutionLevel) exp = 0;
    return level - before;
  }
}

class ShopItem {
  const ShopItem({
    required this.id,
    required this.name,
    required this.short,
    required this.price,
    required this.exp,
    required this.asset,
  });
  final String id;
  final String name;
  final String short;
  final int price;
  final int exp; // 성실볼은 0
  final String asset;
  double get goldEfficiency => price == 0 ? 0 : exp / price;
}

class Habit {
  Habit({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.measureIndex,
    required this.target,
    required this.periodIndex,
  });
  final String id;
  String name;
  String categoryId;
  int measureIndex;
  double target;
  int periodIndex; // 0: 7일 ×1.2, 1: 30일 ×1.5, 2: 100일 ×2.0 (DB period_code D7/D30/D100)
}

enum GoalTier { weekly, monthly }

class Goal {
  Goal({
    required this.id,
    required this.tier,
    required this.title,
    this.detail = '',
    this.done = false,
    this.paidSlot = false,
  });
  final String id;
  final GoalTier tier;
  String title;
  String detail;
  bool done;
  bool paidSlot; // 유료 슬롯은 기록용 (골드 없음)

  int get reward {
    if (paidSlot) return 0;
    return tier == GoalTier.weekly ? Economy.weeklyGoalGold : Economy.monthlyGoalGold;
  }
}

/// 카테고리 레벨 곡선: 레벨 N → N+1 에 10×N 성실도. 최대 [Economy.categoryMaxLevel].
class CategoryLevel {
  const CategoryLevel(this.level, this.current, this.needed);
  final int level;
  final int current;
  final int needed; // 최대 레벨이면 0 (API의 expToNextLevel = null)

  bool get isMax => level >= Economy.categoryMaxLevel;

  factory CategoryLevel.fromPoints(int points) {
    var lv = 1;
    var need = 10;
    var cur = points;
    while (cur >= need && lv < Economy.categoryMaxLevel) {
      cur -= need;
      lv += 1;
      need = 10 * lv;
    }
    if (lv >= Economy.categoryMaxLevel) return CategoryLevel(lv, 0, 0);
    return CategoryLevel(lv, cur, need);
  }
}

/// 습관 하나의 하루 성실도 (0~25).
int sincerityScore({required Measure measure, required double target, required double value}) {
  if (measure.isOX) return value > 0 ? 20 : 0;
  if (value <= 0 || target <= 0) return 0;
  // RANGE: 목표 ± 범위 안이면 20, 벗어나면 0 (04_논리물리모델 F3)
  if (measure.range != null) return (value - target).abs() <= measure.range! ? 20 : 0;
  final ratio = value / target;
  if (ratio >= 1) {
    return (20 + ((ratio - 1) * 10).round()).clamp(0, Economy.maxSincerityPerHabit);
  }
  return (20 * ratio).round();
}
