import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/features/chat/chat_controller.dart';
import 'package:habit_monster/features/shell/main_shell.dart';

import 'game_harness.dart';

/// 챗봇 "입력 중" (11-26): 대답 전에 점 세 개 말풍선이 잠깐 보이고, 대답이 오면 사라진다.
void main() {
  testWidgets('대답 전에 "입력 중"이 최소 시간 동안 보인다', (tester) async {
    ChatController.minThinkTime = const Duration(milliseconds: 700);
    addTearDown(() => ChatController.minThinkTime = Duration.zero);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(withGame(GameState.sample(), const MaterialApp(home: MainShell())));
    await tester.tap(find.text('챗봇'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.bySemanticsLabel('입력 중'), findsOneWidget);
    expect(find.text('안녕! 나 찌릿 쥐. 오늘 습관 체크하러 왔어.'), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('안녕! 나 찌릿 쥐. 오늘 습관 체크하러 왔어.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 7));
  });
}
