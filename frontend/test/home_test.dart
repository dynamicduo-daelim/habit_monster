import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/core/utils/format.dart';
import 'package:habit_monster/features/shell/main_shell.dart';
import 'game_harness.dart';

void main() {
  group('GameState 교감 · 성실도', () {
    test('쓰다듬기는 ♥+2, 최대치를 넘지 않는다', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      final spark = s.monsterByUid('m2')!; // 호감도 8
      expect(s.pet(spark), 2);
      expect(spark.affection, 10);
      expect(spark.pettedToday, isTrue);
      final sprout = s.monsterByUid('m3')!;
      sprout.affection = 10;
      expect(s.pet(sprout), 0);
    });

    test('놀아주기는 하루 1번만 ♥+1', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      final wolf = s.monsterByUid('m1')!; // 호감도 4
      expect(s.play(wolf), 1);
      expect(s.play(wolf), 0);
      expect(wolf.affection, 5);
    });

    test('오늘의 성실도는 앞 3개 습관만, 75점 만점', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      expect(s.todayScore, 0);
      s.confirmCheckin({'h1': 30, 'h3': 4}); // 러닝 30/30 → 20, 물 4/2 → 25 (최대)
      expect(s.todayScore, 45);
      expect(s.checkedCount, 2);
      expect(GameState.maxDailyScore, 75);
    });
  });

  test('이름 뒤 와/과', () {
    expect(withWa('찌릿 쥐'), '찌릿 쥐와');
    expect(withWa('새싹냥'), '새싹냥과');
    expect(josaEunNeun('전공 공부'), '는');
    expect(josaEunNeun('아침 러닝'), '은');
  });

  testWidgets('홈: 시트 · 상점 · 가방 · 교감 창', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = GameState.sample(gold: 1240, balls: 1);
    await tester.pumpWidget(withGame(state, const MaterialApp(home: MainShell())));
    await tester.pump();

    // 슬라이드 시트
    expect(find.text('위로 밀어 습관 리스트 보기'), findsOneWidget);
    await tester.tap(find.text('위로 밀어 습관 리스트 보기'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('챗봇에게 오늘 습관 체크받기'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('시트 접기'));
    await tester.pump(const Duration(milliseconds: 400));

    // 상점에서 하급 물약 사기
    await tester.tap(find.bySemanticsLabel('상점'));
    await tester.pump();
    expect(find.text('상점 주인 마루'), findsOneWidget);
    await tester.tap(find.text('20G'));
    await tester.pump();
    expect(find.text('몇 개 살까?'), findsOneWidget);
    await tester.tap(find.text('1개 사기'));
    await tester.pump();
    expect(find.text('구매 완료!'), findsOneWidget);
    expect(state.gold, 1220);
    expect(state.inventory['s'], 4);
    await tester.tap(find.text('확인'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('닫기'));
    await tester.pump();

    // 가방 → 하급 물약 → 사용하러 가기 → 교감 창(간식 열림)
    await tester.tap(find.bySemanticsLabel('내 가방'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('하급 경험치 물약 4개'));
    await tester.pump();
    await tester.tap(find.text('사용하러 가기 ▶'));
    await tester.pump();
    expect(find.text('그거 나 주는 거야?'), findsOneWidget);
    expect(find.text('어떤 간식을 줄까? (경험치 물약)'), findsOneWidget);

    // 대화 상대(m2 찌릿 쥐)가 대상. 하급 물약 먹이기 → +20 EXP
    final spark = state.monsterByUid('m2')!;
    final expBefore = spark.exp;
    await tester.tap(find.text('하급 ×4'));
    await tester.pump();
    expect(spark.exp, (expBefore + 20) % 125);
    expect(find.text('냠냠! 맛있다!'), findsOneWidget);

    // 놀아주기 → 호감도 +1
    final aff = spark.affection;
    await tester.tap(find.text('놀아주기'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(spark.affection, aff + 1);

    // 타이머 정리
    await tester.pump(const Duration(seconds: 6));
    await tester.tap(find.bySemanticsLabel('닫기').first);
    await tester.pump(const Duration(seconds: 6));
  });
}
