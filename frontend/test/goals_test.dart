import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/data/models.dart';
import 'package:habit_monster/features/shell/main_shell.dart';
import 'game_harness.dart';

void main() {
  group('GameState 목표', () {
    test('달성 체크 시 골드 지급, 완료한 목표는 되돌릴 수 없다 (Q-5)', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      final g = s.goalsOf(GoalTier.monthly).single;
      expect(s.toggleGoal(g), isTrue);
      expect(s.gold, 1240 + 150);
      expect(s.toggleGoal(g), isFalse);
      expect(g.done, isTrue);
      expect(s.gold, 1240 + 150);
    });

    test('완료한 목표는 지울 수 없고, 진행 중인 목표는 지울 수 있다', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      final done = s.goals.firstWhere((g) => g.done); // 주 3회 러닝
      expect(s.deleteGoal(done), isFalse);
      expect(s.goals, contains(done));
      final active = s.goals.firstWhere((g) => !g.done);
      expect(s.deleteGoal(active), isTrue);
      expect(s.gold, 1240);
    });

    test('무료 3칸 뒤의 주간 목표는 유료 슬롯 · 보상 0', () {
      final s = GameState.sample(gold: 1240, balls: 1); // 주간 2개
      final third = s.addGoal(GoalTier.weekly, '세 번째', '');
      expect(third.reward, 40);
      expect(s.capOf(GoalTier.weekly), 3);
      s.unlockExtraWeeklySlot();
      expect(s.capOf(GoalTier.weekly), 4);
      final fourth = s.addGoal(GoalTier.weekly, '네 번째', '');
      expect(fourth.paidSlot, isTrue);
      expect(fourth.reward, 0);
    });
  });

  testWidgets('목표 탭: 체크 · 추가 · 수정 · 삭제', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameState.sample(gold: 1240, balls: 1);
    await tester.pumpWidget(withGame(s, const MaterialApp(home: MainShell())));
    await tester.tap(find.text('목표'));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('책 2권 완독 달성 체크'));
    await tester.pump();
    expect(s.gold, 1390);

    // 빈 제목은 저장 안 됨
    await tester.tap(find.textContaining('+ 목표 추가'));
    await tester.pump();
    await tester.tap(find.text('저장'));
    await tester.pump();
    expect(find.text('목표를 적어주세요'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '매일 스트레칭');
    await tester.tap(find.text('저장'));
    await tester.pump();
    expect(find.text('매일 스트레칭'), findsOneWidget);
    expect(find.text('슬롯 추가 열기 (유료 · 기록용)'), findsOneWidget);

    // 수정 → 삭제
    await tester.tap(find.bySemanticsLabel('목표 수정').at(2));
    await tester.pump();
    expect(find.text('목표 수정'), findsOneWidget);
    await tester.tap(find.text('삭제'));
    await tester.pump();
    expect(find.text('매일 스트레칭'), findsNothing);
    await tester.pump(const Duration(seconds: 7));
  });
}
