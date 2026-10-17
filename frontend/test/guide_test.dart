import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/features/home/attendance_popup.dart';
import 'package:habit_monster/features/shell/main_shell.dart';
import 'game_harness.dart';

/// 튜토리얼 · 도움말(?) · 출석부 · 골드 얻는 법.
void main() {
  Future<GameState> pumpShell(WidgetTester tester, {bool tutorial = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = GameState.sample(); // 어제까지 연속 11일, 오늘은 아직 체크 전
    await tester.pumpWidget(withGame(state, MaterialApp(home: MainShell(showTutorial: tutorial))));
    await tester.pump();
    return state;
  }

  Future<void> tapAndWait(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  test('출석: 앱에 들어오면 출석 (습관 체크와는 별개, 하루 1번)', () {
    final s = GameState.sample();
    final today = DateTime(2026, 10, 15);
    expect(s.attendedOn(today, today: today), isFalse);
    expect(s.attendedOn(DateTime(2026, 10, 14), today: today), isTrue);
    expect(s.attendedOn(DateTime(2026, 10, 4), today: today), isTrue); // 11일 전까지
    expect(s.attendedOn(DateTime(2026, 10, 3), today: today), isFalse);
    expect(s.attendedOn(DateTime(2026, 10, 16), today: today), isFalse); // 내일
    s.confirmCheckin({'h1': 30}); // 체크인만으로는 출석이 아니다
    expect(s.attendedOn(today, today: today), isFalse);
    expect(s.currentStreak, 11);
    expect(s.attend(), isTrue);
    expect(s.attend(), isFalse); // 같은 날 두 번 세지 않는다
    expect(s.attendedOn(today, today: today), isTrue);
    expect(s.currentStreak, 12);
  });

  testWidgets('튜토리얼: 끝까지 넘기면 닫히고, 설정에서 다시 볼 수 있다', (tester) async {
    await pumpShell(tester, tutorial: true);
    expect(find.text('루틴몬에 온 걸 환영해요!'), findsOneWidget);
    expect(find.text('1 / 8'), findsOneWidget);

    for (final title in ['나의 필드', '오늘의 성실도', '챗봇에서 습관 체크', '골드와 성실볼', '상점 · 가방 · 출석 · 습관', '목표와 도감']) {
      await tapAndWait(tester, find.text('다음 ▶'));
      expect(find.text(title), findsOneWidget);
    }
    await tapAndWait(tester, find.text('다음 ▶'));
    expect(find.text('이제 시작해 볼까요?'), findsOneWidget);
    expect(find.text('건너뛰기'), findsNothing); // 마지막 장면
    await tapAndWait(tester, find.text('시작하기!'));
    expect(find.text('이제 시작해 볼까요?'), findsNothing);

    // 설정 → 다시 보기 → 건너뛰기
    await tapAndWait(tester, find.bySemanticsLabel('설정'));
    await tapAndWait(tester, find.text('다시 보기'));
    expect(find.text('루틴몬에 온 걸 환영해요!'), findsOneWidget);
    await tapAndWait(tester, find.text('건너뛰기'));
    expect(find.text('루틴몬에 온 걸 환영해요!'), findsNothing);
  });

  testWidgets('아래 탭 순서: 홈 · 챗봇 · 목표 · 도감 · 통계', (tester) async {
    await pumpShell(tester);
    final xs = [for (final t in ['홈', '챗봇', '목표', '도감', '통계']) tester.getCenter(find.text(t)).dx];
    expect(xs, orderedEquals([...xs]..sort()));
    await tapAndWait(tester, find.text('목표'));
    expect(find.textContaining('주간 목표'), findsWidgets); // 가운데 탭이 목표 화면
  });

  testWidgets('튜토리얼 없이 들어오면 바로 홈', (tester) async {
    await pumpShell(tester);
    expect(find.text('루틴몬에 온 걸 환영해요!'), findsNothing);
  });

  testWidgets('골드 칩을 누르면 골드 얻는 법', (tester) async {
    await pumpShell(tester);
    await tapAndWait(tester, find.bySemanticsLabel('골드 얻는 법'));
    expect(find.text('습관 체크하기'), findsOneWidget);
    expect(find.text('목표 달성'), findsOneWidget);
    await tapAndWait(tester, find.text('확인'));
    expect(find.text('습관 체크하기'), findsNothing);
  });

  testWidgets('? 버튼: 성실도 · 탐색 · 필드 설명', (tester) async {
    await pumpShell(tester);
    for (final (label, head) in [
      ('성실도란? 설명', '성실도가 뭐예요?'),
      ('탐색이란? 설명', '탐색이 뭐예요?'),
      ('나의 필드 설명', '필드가 뭐예요?'),
    ]) {
      await tapAndWait(tester, find.bySemanticsLabel(label));
      expect(find.text(head), findsOneWidget);
      await tapAndWait(tester, find.text('확인'));
      expect(find.text(head), findsNothing);
    }
    // ? 를 눌러도 시트는 펼쳐지지 않는다
    expect(find.text('위로 밀어 습관 리스트 보기'), findsOneWidget);
  });

  testWidgets('출석부: 연속 출석과 이번 달 도장', (tester) async {
    final state = await pumpShell(tester);
    await tapAndWait(tester, find.bySemanticsLabel('출석부'));
    // 홈에 들어온 것만으로 오늘 출석 (체크인 전)
    expect(state.checkedInToday, isFalse);
    expect(find.text('연속 12일'), findsOneWidget);
    expect(find.text('오늘 출석 완료! 내일도 만나요.'), findsOneWidget);
    expect(find.text('DAY 12 · 연속 12일'), findsOneWidget); // 상단 바도 같은 숫자
    await tapAndWait(tester, find.text('오늘 습관 체크하러 가기')); // 닫고 챗봇 탭으로
    expect(find.text('연속 12일'), findsNothing);

    state.confirmCheckin({'h1': 30});
    await tester.pump();
    await tapAndWait(tester, find.text('홈'));
    await tapAndWait(tester, find.bySemanticsLabel('출석부'));
    expect(find.text('연속 12일'), findsOneWidget); // 체크인해도 더 오르지 않는다
    expect(find.text('오늘 습관 체크하러 가기'), findsNothing);
    expect(find.text('확인'), findsOneWidget);
  });

  testWidgets('출석부 달력: 1일의 요일에 맞춰 칸을 채운다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = GameState.sample();
    await tester.pumpWidget(withGame(
      state,
      MaterialApp(home: AttendancePopup(onGoChat: () {}, today: DateTime(2026, 10, 15))),
    ));
    expect(find.text('2026년 10월'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('32'), findsNothing);
    // 2026-10-01은 목요일 → 월요일 시작 달력에서 넷째 칸
    final first = tester.getTopLeft(find.text('1'));
    final thu = tester.getTopLeft(find.text('목'));
    final wed = tester.getTopLeft(find.text('수'));
    expect(first.dx, greaterThan(wed.dx));
    expect((first.dx - thu.dx).abs(), lessThan(24));
  });
}
