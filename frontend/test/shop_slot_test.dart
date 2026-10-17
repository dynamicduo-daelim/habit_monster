import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/data/catalog.dart';
import 'package:habit_monster/data/models.dart';
import 'package:habit_monster/features/dex/dex_screen.dart';
import 'package:habit_monster/features/shell/main_shell.dart';
import 'game_harness.dart';

void main() {
  group('여러 개 사기', () {
    test('합계만큼 골드가 빠지고 개수만큼 들어온다', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      expect(s.buy(Catalog.items.first, count: 5), isTrue); // 하급 20G × 5
      expect(s.gold, 1140);
      expect(s.inventory['s'], 8);
      expect(s.buy(Catalog.items.last, count: 3), isFalse); // 상급 400G × 3 = 1200 > 1140
      expect(s.gold, 1140);
    });
  });

  group('카테고리 슬롯', () {
    test('도감 5마리부터 슬롯 +1, 새 길을 열 수 있다', () {
      final s = GameState.sample(gold: 1240, balls: 1); // 3마리 발견, 길 3개
      expect(s.categorySlotCount, 3);
      expect(s.canOpenCategory, isFalse);
      expect(s.openCategory('sl'), isFalse);
      s.monsters.addAll([
        OwnedMonster(uid: 'x1', speciesId: 'chicken'),
        OwnedMonster(uid: 'x2', speciesId: 'squirrel'),
      ]);
      s.discoveredSpecies.addAll(['chicken', 'squirrel']); // 잡으면 도감 · 가진 종에 기록됨 (throwBall이 하는 일)
      s.caughtSpecies.addAll(['chicken', 'squirrel']);
      expect(s.caughtCount, 5);
      expect(s.categorySlotCount, 4);
      expect(s.openCategory('sl'), isTrue);
      expect(s.pickedCategories, contains('sl'));
      expect(s.canOpenCategory, isFalse);
    });
  });

  testWidgets('상점: 5개 사기 → 몬스터에게 주기', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameState.sample(gold: 1240, balls: 1);
    await tester.pumpWidget(withGame(s, const MaterialApp(home: MainShell())));
    await tester.tap(find.bySemanticsLabel('상점'));
    await tester.pump();
    await tester.tap(find.text('90G')); // 중급
    await tester.pump();
    await tester.tap(find.text('5개'));
    await tester.pump();
    expect(find.text('450'), findsOneWidget); // 합계
    await tester.tap(find.text('5개 사기'));
    await tester.pump();
    expect(find.text('중급 경험치 물약 ×5'), findsOneWidget);
    expect(find.text('가방에 넣었어요 · 보유 6개'), findsOneWidget);
    expect(s.gold, 790);
    await tester.tap(find.text('몬스터에게 주기'));
    await tester.pump();
    expect(find.text('방금 산 거 나 주는 거야?'), findsOneWidget);
    expect(find.text('어떤 간식을 줄까? (경험치 물약)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('수량 팝업: 골드가 모자라면 못 산다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameState.sample(gold: 1240, balls: 1)..gold = 500;
    await tester.pumpWidget(withGame(s, const MaterialApp(home: MainShell())));
    await tester.tap(find.bySemanticsLabel('상점'));
    await tester.pump();
    await tester.tap(find.text('400G'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('하나 늘리기'));
    await tester.pump();
    expect(find.text('골드가 부족해요'), findsOneWidget);
    await tester.tap(find.text('최대'));
    await tester.pump();
    expect(find.text('1개 사기'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pump();
    expect(find.text('몇 개 살까?'), findsNothing);
    expect(s.gold, 500);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('도감: 슬롯이 늘면 새 카테고리 열기', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameState.sample(gold: 1240, balls: 1);
    s.monsters.addAll([OwnedMonster(uid: 'x1', speciesId: 'chicken'), OwnedMonster(uid: 'x2', speciesId: 'squirrel')]);
    s.discoveredSpecies.addAll(['chicken', 'squirrel']);
    s.caughtSpecies.addAll(['chicken', 'squirrel']);
    await tester.pumpWidget(withGame(s, const MaterialApp(home: MainShell())));
    await tester.tap(find.text('도감'));
    await tester.pump();
    expect(find.text('카테고리 슬롯 3/4'), findsOneWidget);
    expect(find.text('몬스터 5/10마리 모으면 +1'), findsOneWidget);
    await tester.tap(find.text('새 카테고리 열기! ▶'));
    await tester.pump();
    expect(find.text('새로운 길이 열렸다!'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^수면 길 열기')));
    await tester.pump();
    expect(s.pickedCategories, contains('sl'));
    expect(find.text('수면 길이 열렸어요!'), findsOneWidget);
    expect(find.text('카테고리 슬롯 4/4'), findsOneWidget);
    expect(find.text('새 카테고리 열기! ▶'), findsNothing);
    expect(find.byType(DexScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });
}
