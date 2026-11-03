import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/features/dex/dex_screen.dart';
import 'game_harness.dart';

void main() {
  testWidgets('도감: 보유 · 출현 중 · 잠김 표시', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameState.sample(gold: 1240, balls: 1); // 공부 38점 → Lv.3, 모닥이·토독·오물 보유
    await tester.pumpWidget(withGame(s, const MaterialApp(home: Scaffold(body: DexScreen()))));

    expect(find.text('발견 3/42'), findsOneWidget);
    expect(find.text('보유 중 · Lv.7 · 기본형'), findsOneWidget); // 모닥이

    await tester.tap(find.bySemanticsLabel(RegExp('^공부/학습 도감')));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('No.009 미발견')); // 번득이 (Lv.3 출현, 공부 Lv.3)
    await tester.pump();
    expect(find.text('지금 탐색하면 만날 수 있어요!'), findsOneWidget);

    // 고르지 않은 길(수면)은 레벨이 맞아도 출현하지 않는다
    await tester.tap(find.bySemanticsLabel(RegExp('^수면 도감')));
    await tester.pump();
    expect(find.text('카테고리 Lv.1에서 출현'), findsOneWidget);
    expect(find.text('미등록 · 0/7'), findsOneWidget);
  });

  testWidgets('도감: 만나기만 하고 못 잡은 몬스터도 모습 · 이름이 보인다', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameState.sample(gold: 1240, balls: 1);
    s.discoveredSpecies.add('rabbit'); // 탐색에서 만났다고 침 (잡지는 않음)
    await tester.pumpWidget(withGame(s, const MaterialApp(home: Scaffold(body: DexScreen()))));

    expect(find.text('발견 4/42'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('No.002 콩지'));
    await tester.pump();
    expect(find.text('만난 적 있음 · 다시 만나면 잡아 보세요!'), findsOneWidget);
    expect(find.text('못 잡음'), findsOneWidget);
    expect(s.monsters.any((m) => m.speciesId == 'rabbit'), isFalse);
  });
}
