import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/data/models.dart';
import 'package:habit_monster/features/onboarding/onboarding_controller.dart';
import 'package:habit_monster/features/shell/main_shell.dart';

import 'chat_test.dart' show FixedRandom;

void _view(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _checkAllNo(WidgetTester tester) async {
  await tester.tap(find.text('챗봇'));
  await tester.pump();
  await tester.pump();
  for (var i = 0; i < 3; i++) {
    await tester.tap(find.text('못 했어'));
    await tester.pump();
  }
  await tester.pump();
}

void main() {
  group('온보딩: 고른 길의 몬스터만', () {
    test('고르지 않은 길의 샘플 몬스터는 빠진다', () {
      final s = GameState.sample(gold: 1240, balls: 1); // 늑대(운동) · 찌릿 쥐(공부) · 새싹냥(식습관)
      final c = OnboardingController(onToast: (_) {});
      c.toggleCategory('ex');
      c.toggleCategory('sl');
      c.habits.add(Habit(id: 'h', name: '7시간 자기', categoryId: 'sl', measureIndex: 0, target: 7, periodIndex: 0));
      c.commit(s);
      expect(s.monsters.map((m) => m.speciesId), ['wolf', 'moon']); // 고른 길마다 초기 몬스터
      expect(s.chatPartnerUid, 'm1');
      expect(s.pickedCategories, ['ex', 'sl']);
      expect(s.discoveredSpecies, {'wolf', 'moon'});
      c.dispose();
    });

    test('고른 길마다 초기 몬스터 1마리, 대화 상대는 고른 첫 파트너', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      final c = OnboardingController(onToast: (_) {});
      for (final id in ['ex', 'sl', 'md']) {
        c.toggleCategory(id);
      }
      c.pickStarter(1); // 수면 길의 그믐 꼬마
      c.habits.add(Habit(id: 'h', name: '7시간 자기', categoryId: 'sl', measureIndex: 0, target: 7, periodIndex: 0));
      c.commit(s);
      expect(s.monsters.map((m) => m.speciesId), ['wolf', 'moon']); // 명상 길은 아직 몬스터가 없다
      final moon = s.monsters.last;
      expect(s.chatPartnerUid, moon.uid);
      expect(moon.affection, 3);
      expect(moon.inField, isTrue);
      c.dispose();
    });

    test('나중에 새 길을 열어도 그 길의 초기 몬스터가 온다', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      s.discoveredSpecies.addAll(['chick', 'moon2']); // 도감 5종 → 칸 +1
      expect(s.openCategory('sl'), isTrue);
      expect(s.monsters.last.speciesId, 'moon');
      expect(s.discoveredSpecies, contains('moon'));
      expect(s.grantStarter('sl'), same(s.monsters.last)); // 두 번 주지 않는다
      expect(s.monsters.where((m) => m.speciesId == 'moon').length, 1);
    });

    test('데려갈 몬스터가 없고 파트너도 안 골랐으면 첫 후보가 자동으로', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      final c = OnboardingController(onToast: (_) {});
      c.toggleCategory('md');
      c.toggleCategory('sl');
      c.habits.add(Habit(id: 'h', name: '7시간 자기', categoryId: 'sl', measureIndex: 0, target: 7, periodIndex: 0));
      c.commit(s);
      expect(s.monsters.single.speciesId, 'moon');
      expect(s.chatPartnerUid, s.monsters.single.uid);
      c.dispose();
    });

    test('몬스터가 없는 길만 골라도 앱이 버틴다', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      final c = OnboardingController(onToast: (_) {});
      c.toggleCategory('md');
      c.habits.add(Habit(id: 'h', name: '10분 명상', categoryId: 'md', measureIndex: 0, target: 10, periodIndex: 0));
      c.commit(s);
      expect(s.monsters, isEmpty);
      expect(s.chatPartnerUid, isNull);
      c.dispose();
    });
  });

  testWidgets('몬스터가 하나도 없어도 챗봇이 시작된다', (tester) async {
    _view(tester);
    final s = GameState.sample(gold: 1240, balls: 1);
    s.monsters.clear();
    s.chatPartnerUid = null;
    await tester.pumpWidget(GameScope(notifier: s, child: const MaterialApp(home: MainShell())));
    await tester.tap(find.text('챗봇'));
    await tester.pump();
    await tester.pump();
    expect(find.text('안녕! 오늘 습관 체크하러 왔어. 탐색에서 첫 친구도 만나보자.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('놓치면 "놓쳤다…" 팝업, 대화창에는 안 남는다', (tester) async {
    _view(tester);
    final s = GameState.sample(gold: 1240, balls: 1, random: FixedRandom(double_: 0.9, int_: 2));
    await tester.pumpWidget(GameScope(notifier: s, child: const MaterialApp(home: MainShell())));
    await _checkAllNo(tester);
    final before = s.monsters.length;
    await tester.tap(find.text('탐색하기 (3회 남음)'));
    await tester.pump();
    await tester.tap(find.text('던지기 ×1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('놓쳤다…'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pump();
    expect(find.textContaining('도망갔어요'), findsOneWidget);
    expect(find.text('던지기 ×0'), findsNothing); // 이미 던졌으면 던지기 버튼 없음
    expect(s.monsters.length, before);
    await tester.tap(find.text('그만'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('잡았어!'), findsNothing);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('다시 탐색하면 던지지 않고 다른 몬스터를 찾는다', (tester) async {
    _view(tester);
    final s = GameState.sample(gold: 1240, balls: 1, random: FixedRandom(double_: 0.9, int_: 2));
    await tester.pumpWidget(GameScope(notifier: s, child: const MaterialApp(home: MainShell())));
    await _checkAllNo(tester);
    await tester.tap(find.text('탐색하기 (3회 남음)'));
    await tester.pump();
    await tester.tap(find.text('다시 탐색 (2회)'));
    await tester.pump();
    expect(s.encountersLeft, 1);
    expect(s.balls, 1);
    expect(find.textContaining('나타났다!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('볼이 없으면 "볼 사기" → 그 자리에서 사서 던진다', (tester) async {
    _view(tester);
    final s = GameState.sample(gold: 1240, balls: 1, random: FixedRandom(double_: 0.5, int_: 2))..balls = 0;
    await tester.pumpWidget(GameScope(notifier: s, child: const MaterialApp(home: MainShell())));
    await _checkAllNo(tester);
    await tester.tap(find.text('탐색하기 (3회 남음)'));
    await tester.pump();
    await tester.tap(find.text('볼 사기'));
    await tester.pump();
    expect(find.text('몇 개 살까?'), findsOneWidget);
    await tester.tap(find.text('5개'));
    await tester.pump();
    await tester.tap(find.text('5개 사기'));
    await tester.pump();
    expect(s.balls, 5);
    expect(s.gold, 990);
    await tester.tap(find.text('던지기 ×5'));
    await tester.pump();
    expect(s.balls, 4);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('잡았다!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });
}
