import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/constants/app_assets.dart';
import 'package:habit_monster/data/catalog.dart';
import 'package:habit_monster/data/models.dart';

void main() {
  test('카테고리 레벨 곡선 10×N', () {
    expect(CategoryLevel.fromPoints(0).level, 1);
    expect(CategoryLevel.fromPoints(10).level, 2);
    expect(CategoryLevel.fromPoints(30).level, 3);
    expect(CategoryLevel.fromPoints(1900).level, 20); // 10 × (1+…+19) = 1900점에서 최대
    expect(CategoryLevel.fromPoints(99999).level, 20);
    expect(CategoryLevel.fromPoints(99999).isMax, isTrue);
    expect(CategoryLevel.fromPoints(1899).level, 19);
  });

  test('성실도 계산', () {
    const m = Measure('운동 시간', '분', 30);
    expect(sincerityScore(measure: m, target: 30, value: 30), 20);
    expect(sincerityScore(measure: m, target: 30, value: 15), 10);
    expect(sincerityScore(measure: m, target: 30, value: 90), 25);
  });

  test('경험치 125마다 레벨업', () {
    final mon = OwnedMonster(uid: 't', speciesId: 'wolf', level: 9, exp: 100);
    expect(mon.addExp(30), 1);
    expect(mon.stage, '1차 진화');
  });

  test('1차 진화부터 진화 그림 (없는 종은 기본 그림 그대로)', () {
    final monkey = Catalog.speciesById('monkey');
    expect(monkey.assetAt(9), AppAssets.monkey);
    expect(monkey.assetAt(10), AppAssets.monkey2);
    expect(monkey.assetAt(20), AppAssets.monkey2);
    expect(Catalog.speciesById('rabbit').assetAt(20), AppAssets.rabbit);
  });

  test('카테고리마다 Lv.1 첫 파트너가 있고, 도감 칸(7)을 넘지 않는다', () {
    for (final c in Catalog.categories) {
      final list = Catalog.species.where((s) => s.categoryId == c.id).toList();
      expect(list.length, inInclusiveRange(4, 7), reason: c.id);
      final starter = Catalog.speciesById(Catalog.starters[c.id]!);
      expect(starter.categoryId, c.id);
      expect(starter.unlockLevel, 1);
    }
  });
}
