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
    final s = GameState.sample(gold: 1240, balls: 1); // 공부 38점 → Lv.3, 늑대·찌릿 쥐·새싹냥 보유
    await tester.pumpWidget(withGame(s, const MaterialApp(home: Scaffold(body: DexScreen()))));

    expect(find.text('발견 3/36'), findsOneWidget);
    expect(find.text('보유 중 · Lv.7 · 기본형'), findsOneWidget); // 잿불 늑대

    await tester.tap(find.bySemanticsLabel(RegExp('^공부/학습 도감')));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('No.008 미발견')); // 번쩍 병아리 (Lv.3 출현)
    await tester.pump();
    expect(find.text('지금 탐색하면 만날 수 있어요!'), findsOneWidget);

    // 고르지 않은 길(수면)은 레벨이 맞아도 출현하지 않는다
    await tester.tap(find.bySemanticsLabel(RegExp('^수면 도감')));
    await tester.pump();
    expect(find.text('카테고리 Lv.1에서 출현'), findsOneWidget);
    expect(find.text('미등록 · 0/6'), findsOneWidget);
  });
}
