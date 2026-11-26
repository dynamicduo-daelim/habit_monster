import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/features/home/habit_manage_screen.dart';
import 'package:habit_monster/features/shell/main_shell.dart';
import 'game_harness.dart';

/// 홈의 "습관" 아이콘: 새 습관 빠른 추가 · 그만두기.
void main() {
  group('습관 추가 · 그만두기 규칙', () {
    test('열린 카테고리에 최대 5개까지 추가', () {
      final s = GameState.sample(); // 습관 3개, 열린 길: 운동 · 공부 · 식습관
      final h = s.addHabit(name: ' 스쿼트 ', categoryId: 'ex', measureIndex: 1, target: 30, periodIndex: 0)!;
      expect(h.name, '스쿼트');
      expect(s.habits.length, 4);
      expect(s.addHabit(name: '10분 명상', categoryId: 'md', measureIndex: 0, target: 10, periodIndex: 0), isNull); // 안 연 길
      expect(s.addHabit(name: '', categoryId: 'ex', measureIndex: 0, target: 30, periodIndex: 0), isNull);
      expect(s.addHabit(name: '러닝', categoryId: 'ex', measureIndex: 0, target: 0, periodIndex: 0), isNull);
      expect(s.addHabit(name: '홈트', categoryId: 'ex', measureIndex: 0, target: 20, periodIndex: 0), isNotNull);
      expect(s.canAddHabit, isFalse);
      expect(s.addHabit(name: '하나 더', categoryId: 'ex', measureIndex: 0, target: 20, periodIndex: 0), isNull);
      expect(s.habits.map((x) => x.id).toSet().length, 5); // id가 겹치지 않는다
    });

    test('마지막 1개는 그만둘 수 없다', () {
      final s = GameState.sample();
      expect(s.removeHabit(s.habits[0]), isTrue);
      expect(s.removeHabit(s.habits[0]), isTrue);
      expect(s.canRemoveHabit, isFalse);
      expect(s.removeHabit(s.habits[0]), isFalse);
      expect(s.habits.length, 1);
    });

    test('체크인 확정 뒤 그만둬도 받은 보상과 오늘의 성실도는 그대로', () {
      final s = GameState.sample(gold: 100);
      s.confirmCheckin({'h1': 30, 'h2': 0, 'h3': 2}); // 러닝 20 + 물 20 = 40
      final gold = s.gold;
      expect(s.todayScore, 40);
      expect(s.removeHabit(s.habits.firstWhere((h) => h.id == 'h1')), isTrue);
      expect(s.todayScore, 40);
      expect(s.gold, gold);
      expect(s.habits.map((h) => h.id), ['h2', 'h3']);
    });

    test('체크인 확정 뒤 추가한 습관은 오늘 보상에 들어가지 않는다', () {
      final s = GameState.sample(gold: 100);
      s.confirmCheckin({'h1': 30, 'h2': 0, 'h3': 0});
      final gold = s.gold;
      final h = s.addHabit(name: '스쿼트', categoryId: 'ex', measureIndex: 1, target: 30, periodIndex: 0)!;
      final r = s.resubmitCheckin({'h1': 30, 'h2': 0, 'h3': 0, h.id: 30})!; // 다시 체크에서 기록은 된다
      expect(r.scores.last.counted, isFalse);
      expect(s.todayRecords[h.id], 30);
      expect(s.todayScore, 20);
      expect(s.gold, gold);
    });
  });

  Future<GameState> pumpHome(WidgetTester tester, [GameState? state]) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = state ?? GameState.sample();
    await tester.pumpWidget(withGame(s, const MaterialApp(home: MainShell())));
    await tester.pump();
    return s;
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('홈 → 습관: 한 화면에서 추천을 고르고 바로 등록 → 습관 탭에 NEW (기획 2026-11-26)', (tester) async {
    final s = await pumpHome(tester);

    // 아이콘을 누르면 목록이 아니라 바로 새 습관 화면
    await tapAndSettle(tester, find.bySemanticsLabel('습관 관리'));
    expect(find.text('새 습관'), findsOneWidget);
    expect(find.text('내 습관 3/5 ›'), findsOneWidget);
    expect(find.text('+ 직접 적기'), findsOneWidget);

    // 추천을 누르면 확인 창이 올라오고, 목표 · 기간만 보고 바로 등록 (재는 방법은 "자세히" 안, 11-26)
    await tapAndSettle(tester, find.text('스쿼트'));
    expect(find.text('스쿼트 등록하기'), findsOneWidget);
    expect(find.text('운동 횟수 (회)'), findsNothing);
    expect(find.textContaining('재는 방법: 운동 횟수'), findsOneWidget);
    await tapAndSettle(tester, find.bySemanticsLabel('목표 늘리기'));
    await tapAndSettle(tester, find.text('7일'));
    await tapAndSettle(tester, find.text('스쿼트 등록하기'));

    expect(s.habits.length, 4);
    final h = s.habits.last;
    expect((h.name, h.categoryId, h.measureIndex, h.target, h.periodIndex), ('스쿼트', 'ex', 1, 31.0, 0));
    // 닫히고 습관 탭으로: 토스트 + NEW
    await tester.pump(const Duration(milliseconds: 600)); // 닫히는 화면 전환이 끝나게
    expect(find.byType(HabitManageScreen), findsNothing);
    expect(find.text('스쿼트 등록! 오늘부터 챗봇이 물어봐요'), findsOneWidget);
    expect(find.text('오늘의 습관'), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('오늘부터'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('직접 적기: 이름을 적으면 등록 버튼이 열린다', (tester) async {
    final s = await pumpHome(tester);
    await tapAndSettle(tester, find.bySemanticsLabel('습관 관리'));
    await tapAndSettle(tester, find.text('+ 직접 적기'));
    await tester.enterText(find.byType(TextField), '저녁 산책');
    await tester.pump();
    await tapAndSettle(tester, find.text('저녁 산책 등록하기'));
    expect(s.habits.last.name, '저녁 산책');
    expect(s.habits.last.periodIndex, 1); // 기본 30일
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('새 습관 화면 → 내 습관 목록에서 그만두기, ◀ 로 닫으면 챗봇은 바뀐 목록으로 묻는다', (tester) async {
    final s = await pumpHome(tester);
    await tapAndSettle(tester, find.bySemanticsLabel('습관 관리'));
    await tapAndSettle(tester, find.text('내 습관 3/5 ›'));
    expect(find.text('내 습관'), findsOneWidget);
    expect(find.text('3 / 5'), findsOneWidget);
    expect(find.text('+ 빈 자리'), findsNWidgets(2));

    await tapAndSettle(tester, find.bySemanticsLabel('아침 러닝 그만두기'));
    expect(find.text("'아침 러닝' 습관을 그만둘까요?"), findsOneWidget);
    await tapAndSettle(tester, find.bySemanticsLabel('그만두기 확인'));
    expect(s.habits.map((h) => h.name), ['전공 공부', '물 2L 마시기']);
    expect(find.text('2 / 5'), findsOneWidget);

    await tapAndSettle(tester, find.bySemanticsLabel('닫기'));
    await tester.tap(find.text('챗봇'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text("[공부/학습] '전공 공부' 오늘 했어?"), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('습관이 5개면 추가 버튼이 잠긴다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameState.sample();
    s.addHabit(name: '스쿼트', categoryId: 'ex', measureIndex: 1, target: 30, periodIndex: 0);
    s.addHabit(name: '홈트', categoryId: 'ex', measureIndex: 0, target: 20, periodIndex: 0);
    await tester.pumpWidget(withGame(s, const MaterialApp(home: MainShell())));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('습관 관리'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('5 / 5'), findsOneWidget); // 꽉 찼으면 아이콘이 목록을 연다
    expect(find.text('새 습관'), findsNothing);
    expect(find.textContaining('습관이 꽉 찼어요'), findsOneWidget);
    expect(find.text('+ 빈 자리'), findsNothing);
    await tester.pump(const Duration(seconds: 7));
  });
}
