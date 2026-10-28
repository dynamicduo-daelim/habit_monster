import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/features/shell/main_shell.dart';
import 'game_harness.dart';

void main() {
  testWidgets('통계 탭 (시연 모드): 연속 출석 · 7일 막대 · 카테고리 6줄', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameState.sample(gold: 1240, balls: 1);
    await tester.pumpWidget(withGame(s, const MaterialApp(home: MainShell())));
    await tester.tap(find.text('통계'));
    await tester.pumpAndSettle();

    expect(find.text('연속 출석'), findsOneWidget);
    expect(find.textContaining('최장 기록'), findsOneWidget);
    expect(find.text('성실도 그래프 · 최근 7일'), findsOneWidget);
    expect(find.text('오늘'), findsOneWidget);
    expect(find.text('81'), findsOneWidget); // 샘플 값
    expect(find.text('카테고리별 레벨'), findsOneWidget);
    expect(find.text('미등록'), findsWidgets);
    expect(find.text('도감을 채우면 열려요'), findsWidgets);
    expect(find.textContaining('Lv.'), findsWidgets);
    await tester.pump(const Duration(seconds: 7));
  });
}
