import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/core/utils/format.dart';
import 'package:habit_monster/features/shell/main_shell.dart';
import 'game_harness.dart';

/// 손가락처럼 여러 번 나눠 움직여 끌기 (한 번에 옮기면 중간 프레임이 없어 놓는 곳을 못 찾는다).
Future<void> dragTo(WidgetTester tester, Offset from, Offset to) async {
  final g = await tester.startGesture(from);
  for (var k = 1; k <= 6; k++) {
    await g.moveTo(Offset.lerp(from, to, k / 6)!);
    await tester.pump();
  }
  await g.up();
  await tester.pump();
}

/// 무대를 휙 미는 스와이프 (한 번에 [step]씩 8번, 16ms 간격 → 손을 뗄 때 빠르기가 남는다).
Future<void> swipe(WidgetTester tester, Offset from, Offset step) async {
  final g = await tester.startGesture(from);
  for (var k = 0; k < 8; k++) {
    await g.moveBy(step, timeStamp: Duration(milliseconds: 16 * (k + 1)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up(timeStamp: const Duration(milliseconds: 16 * 9));
  await tester.pump();
}

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

    test('끌어 옮기기는 몬스터마다 하루 1번 ♥+1', () {
      final s = GameState.sample(gold: 1240, balls: 1);
      final monkey = s.monsterByUid('m1')!; // 호감도 4
      expect(s.drag(monkey), 1);
      expect(s.drag(monkey), 0);
      expect(monkey.affection, 5);
      expect(monkey.draggedToday, isTrue);
      final mouse = s.monsterByUid('m2')!;
      mouse.affection = 10;
      expect(s.drag(mouse), 0); // 꽉 찼으면 안 오르고, 오늘 기회도 안 쓴다
      expect(mouse.draggedToday, isFalse);
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
    expect(withWa('이끼 거북'), '이끼 거북과');
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
    expect(find.text('간식 주기'), findsOneWidget); // 기본 칸 = 간식
    expect(find.textContaining('진화까지'), findsNothing); // 진화 안내는 보여 주지 않는다

    // 대화 상대(m2 찌릿 쥐)가 대상. 물약은 누르기만 하면 안 먹고, 몬스터에게 끌어다 놓으면 먹는다 → +20 EXP
    final spark = state.monsterByUid('m2')!;
    final expBefore = spark.exp;
    await tester.tap(find.byKey(const ValueKey('feed_s')));
    await tester.pump();
    expect(spark.exp, expBefore);
    expect(find.text('그거 나 주는 거야? 이쪽으로 끌어 줘!'), findsOneWidget);
    await dragTo(tester, tester.getCenter(find.byKey(const ValueKey('feed_s'))),
        tester.getCenter(find.bySemanticsLabel('찌릿 쥐 톡 건드리기')));
    expect(spark.exp, (expBefore + 20) % 125);
    expect(find.text('냠냠! 맛있다!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));

    // 놀아주기 → 무대를 휙 밀면 공이 날아가고, 몬스터가 잡으면 호감도 +1 (오늘 처음만)
    final aff = spark.affection;
    await tester.ensureVisible(find.text('놀아주기'));
    await tester.pump();
    await tester.tap(find.text('놀아주기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // 무대가 길어진다
    await tester.ensureVisible(find.byKey(const ValueKey('play_stage')));
    await tester.pump();
    final ground = tester.getRect(find.byKey(const ValueKey('play_stage')));
    // 살짝 누르기만 하면 안 던진다
    await tester.tapAt(ground.center);
    await tester.pump();
    expect(find.text('던진 횟수 0'), findsOneWidget);
    await swipe(tester, Offset(ground.center.dx, ground.bottom - 40), const Offset(-12, -14));
    expect(spark.affection, aff); // 아직 공이 날아가는 중
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(spark.affection, aff + 1);
    expect(find.text('던진 횟수 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    // 두 번째부터는 놀기만
    await swipe(tester, Offset(ground.center.dx, ground.bottom - 40), const Offset(14, -10));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(spark.affection, aff + 1);
    expect(find.text('던진 횟수 2'), findsOneWidget);

    // 타이머 정리
    await tester.pump(const Duration(seconds: 6));
    await tester.tap(find.bySemanticsLabel('닫기').first);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('홈: 몬스터를 끌어 옮기면 따라오고, 처음 한 번 ♥+1', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = GameState.sample(gold: 1240, balls: 1);
    await tester.pumpWidget(withGame(state, const MaterialApp(home: MainShell())));
    await tester.pump();
    // 테스트에선 그림을 읽기 전엔 크기가 0이라 누를 곳이 없다 → 먼저 읽어 둔다
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pump();

    final label = find.text('불씨 원숭이 Lv.7');
    final before = tester.getTopLeft(label);
    // 실제 손가락처럼 움직일 때마다 화면을 그린다 (끄는 중엔 바로 따라옴)
    final g = await tester.startGesture(tester.getCenter(find.bySemanticsLabel('불씨 원숭이 정보 보기')));
    for (var k = 0; k < 4; k++) {
      await g.moveBy(const Offset(20, 8));
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    final after = tester.getTopLeft(label);
    expect(after.dx, greaterThan(before.dx + 20));
    expect(state.monsterByUid('m1')!.affection, 5);
    expect(find.byKey(const ValueKey('hearts_m1_1')), findsOneWidget); // 하트 뿅뿅
    expect(
        find.byWidgetPredicate((w) => w is Text && const ['여기도 괜찮네!', '우와, 높다!', '새 자리 좋아!'].contains(w.data)),
        findsOneWidget); // 놓으면 한마디 (친해진 사이 대사)
    expect(find.text('상점 주인 마루'), findsNothing); // 끌기는 창을 열지 않는다

    // 두 번째부터는 옮기기만
    await tester.drag(find.bySemanticsLabel('불씨 원숭이 정보 보기'), const Offset(-60, 0));
    await tester.pump();
    expect(state.monsterByUid('m1')!.affection, 5);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.byKey(const ValueKey('hearts_m1_1')), findsNothing); // 두 번째엔 하트 없음
    await tester.pump(const Duration(seconds: 4)); // 쉬는 시간 · 토스트가 끝나게
  });

  testWidgets('홈: 아이콘 줄을 오른쪽으로 밀면 숨고, 손잡이를 누르면 다시 나온다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = GameState.sample(gold: 1240, balls: 1);
    await tester.pumpWidget(withGame(state, const MaterialApp(home: MainShell())));
    await tester.pump();

    final shop = find.text('상점'); // 아이콘 이름표
    final shown = tester.getCenter(shop).dx;
    final g = await tester.startGesture(tester.getCenter(shop));
    for (var k = 0; k < 5; k++) {
      await g.moveBy(const Offset(16, 0)); // 손가락처럼 여러 번 나눠 민다
      await tester.pump();
    }
    await g.up();
    await tester.pump(); // 숨기기 시작
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getTopLeft(shop).dx, greaterThanOrEqualTo(390)); // 화면 밖으로
    expect(find.bySemanticsLabel('아이콘 보이기'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('아이콘 보이기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getCenter(shop).dx, shown);
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgets('교감 창: 물약을 몬스터에게 끌어다 놓으면 먹는다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = GameState.sample(gold: 1240, balls: 1);
    await tester.pumpWidget(withGame(state, const MaterialApp(home: MainShell())));
    await tester.pump();
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('불씨 원숭이 정보 보기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pump();

    final monkey = state.monsterByUid('m1')!;
    final expBefore = monkey.exp;
    final potions = state.inventory['s']!;
    expect(find.text('간식 주기'), findsOneWidget);
    final start = tester.getCenter(find.byKey(const ValueKey('feed_s')));
    final g = await tester.startGesture(start);
    await g.moveBy(const Offset(0, -20));
    await tester.pump();
    expect(find.text('여기로 끌어다 놓아요'), findsOneWidget);
    final target = tester.getCenter(find.bySemanticsLabel('불씨 원숭이 톡 건드리기'));
    for (var k = 0; k < 6; k++) {
      await g.moveTo(Offset.lerp(start, target, (k + 1) / 6)!);
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    expect(state.inventory['s'], potions - 1);
    expect(monkey.exp, (expBefore + 20) % 125);
    expect(find.text('여기로 끌어다 놓아요'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });
}
