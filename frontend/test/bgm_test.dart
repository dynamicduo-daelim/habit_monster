import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/audio/bgm.dart';
import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/features/onboarding/onboarding_screen.dart';
import 'package:habit_monster/features/shell/main_shell.dart';

void main() {
  void view(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('온보딩은 인트로 곡', (tester) async {
    view(tester);
    final bgm = SilentBgm();
    await tester.pumpWidget(GameScope(
      notifier: GameState.sample(gold: 1240, balls: 1),
      child: BgmScope(notifier: bgm, child: const MaterialApp(home: OnboardingScreen())),
    ));
    await tester.pump();
    expect(bgm.lastRequested, BgmTrack.intro);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('탭 · 상점 · 탐색에 따라 곡이 바뀌고, 설정에서 끈다', (tester) async {
    view(tester);
    final bgm = SilentBgm();
    final s = GameState.sample(gold: 1240, balls: 1);
    await tester.pumpWidget(GameScope(
      notifier: s,
      child: BgmScope(notifier: bgm, child: const MaterialApp(home: MainShell())),
    ));
    await tester.pump();
    expect(bgm.lastRequested, BgmTrack.home);

    // 상점 열면 상점 곡 → 닫으면 홈 곡
    await tester.tap(find.bySemanticsLabel('상점'));
    await tester.pump();
    await tester.pump();
    expect(bgm.lastRequested, BgmTrack.shop);
    await tester.tap(find.bySemanticsLabel('닫기'));
    await tester.pump();
    await tester.pump();
    expect(bgm.lastRequested, BgmTrack.home);

    // 챗봇 탭 → 챗봇 곡, 체크인 후 탐색 → 탐색 곡, 그만 → 챗봇 곡
    await tester.tap(find.text('챗봇'));
    await tester.pump();
    await tester.pump();
    expect(bgm.lastRequested, BgmTrack.chat);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('못 했어'));
      await tester.pump();
    }
    await tester.tap(find.text('탐색하기 (1회 남음)')); // 전부 "못 했어"인 날은 탐색 1회
    await tester.pump();
    await tester.pump();
    expect(bgm.lastRequested, BgmTrack.explore);
    // 탐색 중에 다른 탭으로 가면 그 탭 곡 (탐색 곡은 챗봇 탭에서만)
    await tester.tap(find.text('도감'));
    await tester.pump();
    expect(bgm.lastRequested, BgmTrack.home);
    await tester.tap(find.text('챗봇'));
    await tester.pump();
    expect(bgm.lastRequested, BgmTrack.explore);
    await tester.tap(find.text('그만'));
    await tester.pump();
    await tester.pump();
    expect(bgm.lastRequested, BgmTrack.chat);

    // 설정 창의 배경음악 버튼
    expect(bgm.enabled, isTrue);
    await tester.tap(find.bySemanticsLabel('설정'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.bySemanticsLabel('배경음악 끄기'));
    await tester.pump();
    expect(bgm.enabled, isFalse);
    expect(find.bySemanticsLabel('배경음악 켜기'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });
}
