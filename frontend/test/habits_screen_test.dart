import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/features/habits/habits_screen.dart';
import 'package:habit_monster/features/home/habit_manage_screen.dart';

import 'game_harness.dart';

/// 가운데 습관 탭 (기획 2026-11-25-습관-탭-목표-제거).
void main() {
  Future<GameState> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameState.sample(gold: 1240, balls: 1);
    await tester.pumpWidget(withGame(s, const MaterialApp(home: Scaffold(body: HabitsScreen()))));
    await tester.pump();
    return s;
  }

  testWidgets('오늘 습관이 한 줄씩, 맨 위에 체크 수 · 성실도', (tester) async {
    final s = await pump(tester);
    expect(find.text('오늘의 습관'), findsOneWidget);
    expect(find.text('0 / ${s.activeHabits.length} 체크'), findsOneWidget);
    for (final h in s.habits) {
      expect(find.text(h.name), findsOneWidget);
    }
    // 체크 상태는 글자 대신 아이콘 (읽기 도우미에는 "미체크") — 11-26
    expect(find.bySemanticsLabel(RegExp('미체크')), findsNWidgets(s.habits.length));
    expect(find.text('미체크'), findsNothing);
  });

  testWidgets('체크인하면 값 · 점수가 보인다', (tester) async {
    final s = await pump(tester);
    s.confirmCheckin({'h1': 30});
    await tester.pump();
    expect(find.text('1 / ${s.activeHabits.length} 체크'), findsOneWidget);
    expect(find.textContaining('30분 · +'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('아침 러닝.*체크 완료')), findsOneWidget);
  });

  testWidgets('맨 위 새 습관 버튼 → 바로 새 습관 화면', (tester) async {
    await pump(tester);
    await tester.tap(find.text('새 습관'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitManageScreen), findsOneWidget);
    expect(find.text('+ 직접 적기'), findsOneWidget);
  });
}
