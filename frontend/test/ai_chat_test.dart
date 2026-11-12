import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/core/state/local_game_repository.dart';
import 'package:habit_monster/core/state/study_timer.dart';
import 'package:habit_monster/data/results.dart';
import 'package:habit_monster/features/chat/chat_controller.dart';
import 'package:habit_monster/features/chat/study_timer_view.dart';
import 'package:habit_monster/features/shell/main_shell.dart';
import 'game_harness.dart';

/// 서버 체크인 대사(D-64)만 정해 둔 값으로 돌려주는 저장소 (규칙 계산은 앱 그대로).
class _FakeDialogueRepo extends LocalGameRepository {
  _FakeDialogueRepo(super.state, this.lines);
  final List<String?> lines;
  int calls = 0;

  @override
  Future<String?> checkinDialogue() async => lines[calls++];
}

/// 서버 AI 해석 대신 정해 둔 답을 돌려주는 저장소 (규칙 계산은 앱 그대로).
class _FakeAiRepo extends LocalGameRepository {
  _FakeAiRepo(super.state, this.reply);
  final InterpretResult? Function(String message) reply;
  final calls = <(String, List<(String, String)>, String?)>[];

  @override
  Future<InterpretResult?> interpret({
    required String message,
    required List<(String, String)> history,
    required Map<String, double> draft,
    String? askingHabitId,
  }) async {
    calls.add((message, history, askingHabitId));
    return reply(message);
  }
}

void main() {
  group('챗봇: 말로 답하기 (AI 해석, D-57)', () {
    test('한 문장에서 여러 습관 → 남은 습관을 묻고 → 다 모이면 바로 제출 (확인 카드 없음, 11-12)', () async {
      final s = GameState.sample(gold: 1240, balls: 1);
      final repo = _FakeAiRepo(
        s,
        (m) => m.contains('뛰었')
            ? const InterpretResult(reply: '와, 30분이나!', answers: {'h1': 30, 'h3': 2})
            : const InterpretResult(reply: '공부도 했구나!', answers: {'h2': 60}),
      );
      final c = ChatController(state: s, repository: repo);
      await c.start();
      expect(c.currentHabit!.id, 'h1');

      await c.sendText('아침에 30분 뛰었고 물도 2리터 마셨어');
      expect(repo.calls.single.$3, 'h1'); // 방금 묻던 습관을 같이 보낸다
      expect(repo.calls.single.$2.first.$1, 'BOT'); // 직전 대화 (몬스터의 질문)
      expect(c.currentHabit!.id, 'h2'); // 아직 안 들은 공부를 묻는다
      expect(c.step, ChatStep.yesNo);
      expect(s.checkedInToday, isFalse);

      await c.sendText('공부는 1시간 했어');
      expect(s.checkedInToday, isTrue); // 마지막 답이면 바로 제출
      expect(s.todayRecords, {'h1': 30.0, 'h2': 60.0, 'h3': 2.0});
      expect(c.step, ChatStep.done);
    });

    test('AI가 다시 물으면 그 습관 숫자 입력으로', () async {
      final s = GameState.sample(gold: 1240, balls: 1);
      final repo = _FakeAiRepo(
        s,
        (_) => const InterpretResult(
            reply: '오, 공부도?', answers: {'h1': 30}, askAgainHabitId: 'h2', askAgainQuestion: '공부는 몇 분 했어?'),
      );
      final c = ChatController(state: s, repository: repo);
      await c.start();
      await c.sendText('뛰었고 공부도 좀 했어');
      expect(c.currentHabit!.id, 'h2');
      expect(c.step, ChatStep.amount);
      expect(c.messages.last.text, '공부는 몇 분 했어?');

      await c.sendValue(60);
      await c.answer(true); // 물
      await c.sendValue(2);
      expect(s.checkedInToday, isTrue);
      expect(s.todayRecords, {'h1': 30.0, 'h2': 60.0, 'h3': 2.0});
    });

    test('위기 신호(safety)면 다음 습관으로 넘어가지 않는다', () async {
      final s = GameState.sample(gold: 1240, balls: 1);
      final repo = _FakeAiRepo(
          s, (_) => const InterpretResult(reply: '많이 힘들구나. 주변에 꼭 도움을 청해.', answers: {}, safety: true));
      final c = ChatController(state: s, repository: repo);
      await c.start();
      await c.sendText('요즘 너무 힘들어');
      expect(c.messages.last.text, contains('도움'));
      expect(c.currentHabit!.id, 'h1');
      expect(c.step, ChatStep.yesNo);
    });

    test('시연 모드(AI 없음): 말 속 숫자 · "못 했어"만 읽고, 모르면 말하는 법을 알려 준다', () async {
      final s = GameState.sample(gold: 1240, balls: 1);
      final c = ChatController(state: s, repository: LocalGameRepository(s));
      await c.start();
      await c.sendText('오늘은 그냥 그랬어');
      expect(c.messages.last.text, contains('말해 줄래'));
      expect(c.currentHabit!.id, 'h1');

      await c.sendText('30분 뛰었어');
      expect(c.currentHabit!.id, 'h2');
      await c.sendText('공부 못 했어');
      expect(c.currentHabit!.id, 'h3');
      await c.sendText('2리터');
      expect(s.checkedInToday, isTrue);
      expect(s.todayRecords, {'h1': 30.0, 'h2': 0.0, 'h3': 2.0});
    });

    test('공부 타이머로 잰 분은 공부 습관을 물을 때 미리 채운다', () async {
      final s = GameState.sample(gold: 1240, balls: 1);
      final c = ChatController(
          state: s, repository: LocalGameRepository(s), timerMinutes: (id) => id == 'h2' ? 45 : 0);
      await c.start();
      await c.answer(true);
      await c.sendValue(30); // 러닝
      expect(c.currentHabit!.id, 'h2');
      expect(c.messages.last.text, contains('타이머로 45분'));
      await c.answer(true);
      expect(c.quickAmounts.first, s.recordableValue(s.habits[1], 45));
    });
  });

  group('공부 타이머', () {
    test('시작 · 일시정지 · 이어서 · 끝내기 → 일시정지를 뺀 분이 그날 쌓인다', () async {
      var now = DateTime(2026, 10, 30, 19, 0);
      final store = MemoryStudyTimerStore();
      final t = StudyTimer(store: store, clock: () => now)..setFree(true); // 자유 모드: 쉬는 시간 없이 다 센다
      t.start('h2');
      now = now.add(const Duration(minutes: 20));
      t.pause();
      now = now.add(const Duration(minutes: 10)); // 쉬는 시간은 안 센다
      t.resume();
      now = now.add(const Duration(minutes: 25, seconds: 40));
      expect(t.stop(), 45);
      expect(t.todayMinutes('h2'), 45);
      expect(t.idle, isTrue);

      // 앱을 다시 켜도 남아 있다
      final again = StudyTimer(store: store, clock: () => now);
      await again.restore();
      expect(again.todayMinutes('h2'), 45);
    });

    test('재는 중에 앱을 닫았다 열어도 이어서 잰다 · 최대 4시간', () async {
      var now = DateTime(2026, 10, 30, 9, 0);
      final store = MemoryStudyTimerStore();
      StudyTimer(store: store, clock: () => now)
        ..setFree(true)
        ..start('h2');
      now = now.add(const Duration(hours: 5));
      final t = StudyTimer(store: store, clock: () => now);
      await t.restore();
      expect(t.running, isTrue);
      expect(t.overLimit, isTrue);
      expect(t.stop(), StudyTimer.maxMinutes);
    });

    test('자정을 넘기면 00시 기준으로 나눈다', () {
      var now = DateTime(2026, 10, 30, 23, 30);
      final t = StudyTimer(clock: () => now)..setFree(true);
      t.start('h2');
      now = DateTime(2026, 10, 31, 0, 20);
      expect(t.stop(), 50);
      expect(t.todayMinutes('h2', day: DateTime(2026, 10, 30)), 30);
      expect(t.todayMinutes('h2', day: DateTime(2026, 10, 31)), 20);
    });

    test('뽀모도로: 25분 집중 → 5분 쉼을 반복하고, 집중한 분만 쌓이고 토마토가 생긴다', () async {
      var now = DateTime(2026, 11, 2, 19, 0);
      final store = MemoryStudyTimerStore();
      final t = StudyTimer(store: store, clock: () => now);
      t.start('h2');
      expect(t.phase, StudyPhase.focus);
      expect(t.display, const Duration(minutes: 25));
      now = now.add(const Duration(minutes: 27));
      expect(t.phase, StudyPhase.rest);
      expect(t.display, const Duration(minutes: 3)); // 쉬는 시간 남은 3분
      expect(t.sessionTomatoes, 1);
      now = now.add(const Duration(minutes: 35)); // 62분: 집중 25 + 25 + 2
      expect(t.phase, StudyPhase.focus);
      expect(t.round, 3);
      expect(t.stop(), 52);
      expect(t.todayMinutes('h2'), 52);
      expect(t.todayTomatoes(), 2);

      // 설정 · 친구도 다시 켜면 남는다
      t
        ..setFocusMinutes(50)
        ..setBreakMinutes(10)
        ..setSound(StudySound.cafe)
        ..setFriends(['m2', 'm3']);
      final again = StudyTimer(store: store, clock: () => now);
      await again.restore();
      expect((again.focusMinutes, again.breakMinutes, again.sound), (50, 10, StudySound.cafe));
      expect(again.friends, ['m2', 'm3']);
      expect(again.todayTomatoes(), 2);
    });

    test('친구는 최대 3마리, 한 마리는 남는다 · 재는 중엔 시간 설정을 못 바꾼다', () {
      final t = StudyTimer()..setFriends(['m1']);
      t
        ..toggleFriend('m1')
        ..toggleFriend('m2')
        ..toggleFriend('m3')
        ..toggleFriend('m4');
      expect(t.friends, ['m1', 'm2', 'm3']);
      t.start('h2');
      t.setFocusMinutes(50);
      expect(t.focusMinutes, 25);
    });

    testWidgets('챗봇 탭 옆 [공부 타이머] 칸에서 시작 · 끝내기', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var now = DateTime(2026, 10, 30, 19, 0);
      final timer = StudyTimer(clock: () => now);
      final s = GameState.sample(gold: 1240, balls: 1);
      await tester.pumpWidget(StudyTimerScope(notifier: timer, child: withGame(s, const MaterialApp(home: MainShell()))));
      await tester.tap(find.text('챗봇'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('공부 타이머'));
      await tester.pump();
      expect(find.byType(StudyTimerView), findsOneWidget);
      // 내리지 않아도 시작 버튼까지 한 화면에 (11-02)
      expect(find.descendant(of: find.byType(StudyTimerView), matching: find.byType(ListView)), findsNothing);
      expect(find.text('25:00'), findsOneWidget);
      expect(find.text('준비 · 25분 집중'), findsOneWidget);
      await tester.tap(find.text('같이 집중 시작'));
      await tester.pump();
      now = now.add(const Duration(minutes: 12, seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('12:57'), findsOneWidget); // 남은 시간
      expect(find.text('1번째 집중'), findsOneWidget);
      await tester.tap(find.text('끝내기'));
      await tester.pump();
      expect(timer.todayMinutes('h2'), 12);
      expect(find.textContaining('· 오늘 12분'), findsOneWidget);
      expect(find.text('수고했어!'), findsOneWidget);
      expect(find.text('챗봇에 기록하러'), findsOneWidget);

      // 챗봇으로 돌아가면 대화가 그대로 있다
      await tester.tap(find.text('챗봇에 기록하러'));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget); // 채팅 입력칸이 그대로
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('톱니바퀴 설정 · 내 루틴몬에서 같이 공부할 친구 고르기', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final timer = StudyTimer();
      final s = GameState.sample(gold: 1240, balls: 1);
      await tester.pumpWidget(withGame(s, MaterialApp(home: Scaffold(body: StudyTimerView(timer: timer)))));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('timer_settings')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('타이머 설정'), findsOneWidget);
      await tester.tap(find.text('+').first);
      await tester.tap(find.text('카페'));
      await tester.pump();
      expect(timer.focusMinutes, 30);
      expect(timer.sound, StudySound.cafe);
      await tester.tap(find.text('완료'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('30:00'), findsOneWidget);

      // 처음엔 대화 상대 한 마리 → 한 마리 더
      await tester.tap(find.text('바꾸기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('내 루틴몬'), findsOneWidget);
      final other = s.monsters.firstWhere((m) => m.uid != s.chatPartnerUid);
      await tester.tap(find.byKey(ValueKey('friend_${other.uid}')));
      await tester.pump();
      expect(timer.friends, [s.chatPartnerUid, other.uid]);
      expect(find.text('2마리 골랐어요'), findsOneWidget);
      await tester.tap(find.text('완료'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(StudyTimerView.friendsOf(s, timer).length, 2);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('체크인 대사 (서버, D-64)', () {
    Future<void> checkAll(ChatController c) async {
      await c.answer(true);
      await c.sendValue(30);
      await c.answer(true);
      await c.sendValue(60);
      await c.answer(true);
      await c.sendValue(2);
    }

    test('확정 · 다시 체크 뒤 서버 대사가 있으면 그 말, 보상 칩은 그대로', () async {
      final s = GameState.sample(gold: 1240, balls: 1);
      final repo = _FakeDialogueRepo(s, ['30분이나 뛰었구나, 멋져!', '기록 고쳐 줘서 고마워!']);
      final c = ChatController(state: s, repository: repo);
      await c.start();
      await checkAll(c);
      expect(s.checkedInToday, isTrue);
      final done = c.messages.firstWhere((m) => m.text == '30분이나 뛰었구나, 멋져!');
      expect(done.reward, isNotNull); // 성실도 · 골드 칩은 대사와 상관없이 그대로
      expect(c.messages.any((m) => m.text.contains('오늘 체크 끝!')), isFalse);

      await c.recheck();
      await checkAll(c);
      expect(c.messages.last.text, '기록 고쳐 줘서 고마워!');
      expect(repo.calls, 2);
    });

    test('서버 대사가 없으면(null) 지금 대본 대사', () async {
      final s = GameState.sample(gold: 1240, balls: 1);
      final c = ChatController(state: s, repository: _FakeDialogueRepo(s, [null]));
      await c.start();
      await checkAll(c);
      expect(c.messages.any((m) => m.text.contains('오늘 체크 끝!')), isTrue);
    });
  });
}
