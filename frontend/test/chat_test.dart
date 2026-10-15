import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/data/catalog.dart';
import 'package:habit_monster/data/models.dart';
import 'package:habit_monster/data/results.dart';
import 'package:habit_monster/features/shell/main_shell.dart';

/// 정해진 값을 돌려주는 Random (탐색 결과 고정용).
class FixedRandom implements Random {
  FixedRandom({required this.double_, this.int_ = 0, this.doubles});
  final double double_;
  final int int_;

  /// 있으면 nextDouble이 이 순서대로 나오고, 다 쓰면 [double_]가 나온다.
  final List<double>? doubles;
  int _used = 0;

  @override
  double nextDouble() {
    final d = doubles;
    return d != null && _used < d.length ? d[_used++] : double_;
  }
  @override
  int nextInt(int max) => int_ % max;
  @override
  bool nextBool() => false;
}

void main() {
  group('체크인 규칙 (하루 1번 일괄 확정)', () {
    test('점수 상위 3개만 골드 · 카테고리 포인트에 반영', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      s.habits.add(Habit(id: 'h4', name: '스쿼트', categoryId: 'ex', measureIndex: 1, target: 30, periodIndex: 0));
      // 러닝 30/30 → 20, 공부 0 → 0, 물 3/2 → 25, 스쿼트 15/30 → 10 → 상위 3개: 물 25 · 러닝 20 · 스쿼트 10
      final r = s.confirmCheckin({'h1': 30, 'h2': 0, 'h3': 3, 'h4': 15})!;
      expect(r.totalScore, 55);
      expect(r.countedScore, 55);
      expect(r.scores.firstWhere((x) => x.habit.id == 'h2').counted, isFalse);
      expect(s.todayScore, 55);
      expect(s.categoryPoints['ex'], 64 + 20 + 10);
      expect(s.categoryPoints['st'], 38);
      expect(s.gold, 1240 + r.goldEarned);
    });

    test('카테고리 레벨이 오르면 레벨당 +20G', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      s.categoryPoints['ex'] = 95; // Lv.4, Lv.5까지 5 남음
      final r = s.confirmCheckin({'h1': 30, 'h2': 0, 'h3': 0})!;
      expect(r.levelUps, {'ex': 5});
      expect(r.goldEarned, 20 + 20);
    });

    test('확정은 하루 1번 (두 번째 확정은 무시)', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      s.confirmCheckin({'h1': 30, 'h2': 0, 'h3': 0});
      final gold = s.gold;
      expect(s.confirmCheckin({'h1': 60, 'h2': 60, 'h3': 2}), isNull);
      expect(s.gold, gold);
      expect(s.todayRecords['h1'], 30);
    });

    test('다시 제출하면 기록만 바뀌고 보상은 첫 확정 그대로', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      expect(s.resubmitCheckin({'h1': 30}), isNull); // 확정 전엔 다시 제출할 게 없다
      s.confirmCheckin({'h1': 30, 'h2': 0, 'h3': 0}); // 러닝 20점만
      final gold = s.gold;
      final exPoints = s.categoryPoints['ex'];
      s.encountersLeft = 1; // 탐색을 두 번 쓴 뒤

      final r = s.resubmitCheckin({'h1': 45, 'h2': 60, 'h3': 2})!; // 러닝 25 · 공부 20 · 물 20으로 고침
      expect(r.goldEarned, 0);
      expect(r.scores.map((x) => x.score), [25, 20, 20]);
      expect(s.todayRecords, {'h1': 45, 'h2': 60, 'h3': 2});
      expect(s.scoreOf(s.habits[0]), 25); // 최신 점수
      expect(s.rewardedScoreOf(s.habits[0]), 20); // 보상 기준은 그대로
      expect(s.todayScore, 20);
      expect(s.gold, gold);
      expect(s.categoryPoints['ex'], exPoints);
      expect(s.encountersLeft, 1); // 탐색 횟수도 다시 생기지 않는다
      expect(s.currentStreak, 12);
    });

    test('확정하면 탐색 3회 + 오늘 체크인한 카테고리가 탐색 풀', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      expect(s.encountersLeft, 0);
      expect(s.explore(), isNull); // 체크인 전엔 탐색 불가
      s.confirmCheckin({'h1': 30}); // 운동만 체크인
      expect(s.encountersLeft, 3);
      expect(s.encounterPool.map((sp) => sp.categoryId).toSet(), {'ex'});
      expect(s.currentStreak, 12);
    });

    test('수면 시간은 목표 ± 1시간이면 20점 (RANGE)', () {
      final sleep = Catalog.category('sl').measures.first;
      expect(sincerityScore(measure: sleep, target: 7, value: 7.5), 20);
      expect(sincerityScore(measure: sleep, target: 7, value: 6), 20);
      expect(sincerityScore(measure: sleep, target: 7, value: 9), 0);
      expect(sincerityScore(measure: sleep, target: 7, value: 0), 0);
    });
  });

  group('탐색 · 잡기 규칙', () {
    test('탐색하면 몬스터가 나타나기만 한다 (아직 안 잡음)', () {
      final s = _checkedIn(GameState.sample(gold: 1240, balls: 1, random: FixedRandom(double_: 0.9, int_: 2))); // 풀: 늑대, 쥐, 병아리, 새싹냥
      final e = s.explore()!;
      expect(e.species!.id, 'chick');
      expect(e.alreadyOwned, isFalse);
      expect(s.monsters.length, 3);
      expect(s.encountersLeft, 2);
    });

    test('만날 몬스터가 없는 길만 열었으면 아무도 없음', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      s.habits.add(Habit(id: 'h9', name: '10분 명상', categoryId: 'md', measureIndex: 0, target: 10, periodIndex: 0));
      s.pickedCategories.add('md');
      s.confirmCheckin({'h9': 10}); // 명상만 체크인 → 명상 몬스터 없음
      expect(s.explore()!.found, isFalse);
    });

    test('탐색은 40% 확률로 아무도 안 나온다 (횟수는 쓴다)', () {
      final s = _checkedIn(GameState.sample(gold: 1240, balls: 1, random: FixedRandom(double_: 0.39, int_: 2)));
      final e = s.explore()!;
      expect(e.found, isFalse);
      expect(e.emptyPool, isFalse); // 만날 몬스터는 있는데 이번에만 안 나옴
      expect(s.encountersLeft, 2);
      final s2 = _checkedIn(GameState.sample(gold: 1240, balls: 1, random: FixedRandom(double_: 0.4, int_: 2)));
      expect(s2.explore()!.found, isTrue);
    });

    test('잡힐 확률은 희귀도별 80 · 60 · 40%', () {
      final s = GameState.sample(gold: 1240, balls: 10);
      expect(s.captureRateOf(Catalog.speciesById('spark')), 0.8); // 흔함
      expect(s.captureRateOf(Catalog.speciesById('chick')), 0.6); // 보통
      expect(s.captureRateOf(Catalog.speciesById('wolf')), 0.4); // 희귀
      // 같은 운(0.5)이면 보통은 잡히고 희귀는 도망간다
      final lucky = GameState.sample(gold: 1240, balls: 10, random: FixedRandom(double_: 0.5));
      expect(lucky.throwBall(Catalog.speciesById('chick'))!.caught, isTrue);
      expect(lucky.throwBall(Catalog.speciesById('wolf'))!.caught, isFalse);
    });

    test('던지면 볼 1개를 쓰고 잡으면 새 몬스터', () {
      final s = _checkedIn(GameState.sample(gold: 1240, balls: 1, random: FixedRandom(double_: 0.5, int_: 2)));
      final e = s.explore()!;
      final r = s.throwBall(e.species!)!;
      expect(r.kind, CatchKind.newMonster);
      expect(r.toField, isTrue);
      expect(s.balls, 0);
      expect(s.monsters.length, 4);
      expect(s.discoveredSpecies, contains('chick'));
    });

    test('놓치면 볼만 쓰고 몬스터는 안 생긴다', () {
      final s = _checkedIn(GameState.sample(gold: 1240, balls: 1, random: FixedRandom(double_: 0.9, int_: 2)));
      final r = s.throwBall(s.explore()!.species!)!;
      expect(r.kind, CatchKind.escaped);
      expect(r.caught, isFalse);
      expect(s.balls, 0);
      expect(s.monsters.length, 3);
    });

    test('이미 있는 몬스터를 잡으면 +15G', () {
      final s = _checkedIn(GameState.sample(gold: 1240, balls: 1, random: FixedRandom(double_: 0.9, int_: 0, doubles: [0.9, 0.1]))); // 잿불 늑대(희귀): 등장 → 포획
      final e = s.explore()!;
      expect(e.alreadyOwned, isTrue);
      final before = s.gold;
      expect(s.throwBall(e.species!)!.kind, CatchKind.duplicate);
      expect(s.gold, before + 15);
    });

    test('볼이 없으면 못 던지고, 탐색 횟수가 없으면 탐색 못 함', () {
      final s = _checkedIn(GameState.sample(gold: 1240, balls: 1, random: FixedRandom(double_: 0.9)));
      s.balls = 0;
      expect(s.throwBall(Catalog.speciesById('chick')), isNull);
      s.encountersLeft = 0;
      expect(s.explore(), isNull);
    });
  });

  testWidgets('챗봇: 습관 3개 체크 → 탐색', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameState.sample(gold: 1240, balls: 1, random: FixedRandom(double_: 0.5, int_: 2));
    await tester.pumpWidget(GameScope(notifier: s, child: const MaterialApp(home: MainShell())));
    await tester.tap(find.text('챗봇'));
    await tester.pump();
    await tester.pump();

    expect(find.text('안녕! 나 찌릿 쥐. 오늘 습관 체크하러 왔어.'), findsOneWidget);
    expect(find.text("[운동] '아침 러닝' 오늘 했어?"), findsOneWidget);

    // 체크인 전: 탐색 횟수 없음
    expect(find.text('체크인하면 탐색 3회'), findsOneWidget);

    // 아침 러닝: 했어 → 빠른 선택 30분 (보상은 아직 — 마지막에 한 번에 확정)
    await tester.tap(find.text('했어!').last); // 말풍선이 아닌 버튼
    await tester.pump();
    expect(find.text('좋아! 운동 시간은 얼마나 했어? 목표는 30분이야.'), findsOneWidget);
    await tester.tap(find.text('30분'));
    await tester.pump();
    expect(s.gold, 1240);
    expect(s.todayRecords, isEmpty);

    // 전공 공부: 못 했어
    await tester.tap(find.text('못 했어'));
    await tester.pump();

    // 물 2L: 직접 입력 3 → 마지막 답이라 확정
    await tester.tap(find.text('했어!').last);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.text('전송'));
    await tester.pump();
    await tester.pump(); // 맨 아래로 스크롤된 프레임
    expect(find.textContaining('오늘 체크 끝! 오늘의 성실도는 45/75야.'), findsOneWidget);
    expect(find.text('성실도 +45 · +45G'), findsOneWidget);
    expect(s.todayScore, 45);
    expect(s.todayRecords['h2'], 0);
    expect(find.text('식습관/건강 Lv.3 달성! +20G'), findsOneWidget); // 물 25점으로 21 → 46점
    expect(s.gold, 1240 + 45 + 20);
    expect(find.text('DAY 12 · 연속 12일'), findsOneWidget);
    expect(find.text('다시 체크'), findsOneWidget); // 기록은 고칠 수 있다 (보상은 그대로)

    await tester.tap(find.text('탐색하기 (3회 남음)'));
    await tester.pump();
    expect(find.textContaining('야생의 번쩍 병아리가 나타났다!'), findsOneWidget);
    expect(find.text('던지기 ×1'), findsOneWidget);
    await tester.tap(find.text('던지기 ×1'));
    await tester.pump();
    expect(find.text('성실볼을 던졌다! 과연…'), findsOneWidget);
    expect(s.balls, 0);
    // 결과 팝업을 닫기 전엔 대화 상대 줄에 안 보인다
    expect(find.bySemanticsLabel(RegExp('^번쩍 병아리와 대화')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('잡았다!'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pump();
    expect(find.text('NEW!'), findsOneWidget);
    expect(find.textContaining('번쩍 병아리(보통)를 잡았어요!'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^번쩍 병아리와 대화')), findsOneWidget);
    await tester.tap(find.text('그만'));
    await tester.pump();
    await tester.pump();
    expect(find.text('탐색하기 (2회 남음)'), findsOneWidget);
    expect(find.textContaining('번쩍 병아리를 잡았어! 새 친구가 생겼네.'), findsOneWidget);

    // 다시 체크: 기록만 고치고 보상 · 탐색 횟수는 그대로
    final goldBefore = s.gold;
    await tester.tap(find.text('다시 체크'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('처음부터 다시 물어볼게'), findsOneWidget);
    await tester.tap(find.text('했어!').last); // 아침 러닝 30 → 45분
    await tester.pump();
    await tester.tap(find.text('45분'));
    await tester.pump();
    await tester.tap(find.text('못 했어')); // 전공 공부
    await tester.pump();
    await tester.tap(find.text('못 했어')); // 물 3L → 못 함
    await tester.pump();
    await tester.pump();
    expect(find.text('기록을 고쳐 뒀어! 보상은 처음 확정한 그대로야.'), findsOneWidget);
    expect(s.todayRecords, {'h1': 45, 'h2': 0, 'h3': 0});
    expect(s.todayScore, 45);
    expect(s.gold, goldBefore);
    expect(find.text('탐색하기 (2회 남음)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });
}


/// 체크인 확정 (탐색하려면 먼저 필요): 샘플 습관 3개 모두 응답.
GameState _checkedIn(GameState s) {
  s.confirmCheckin({'h1': 30, 'h2': 60, 'h3': 2});
  return s;
}
