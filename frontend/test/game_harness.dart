import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/state/game_repository.dart';
import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/core/state/local_game_repository.dart';

/// 테스트용: 게임 상태(읽기) + 앱 안에서 계산하는 게임 동작(바꾸기)을 함께 내려준다 — 앱 루트(`app.dart`)와 같은 구성.
Widget withGame(GameState state, Widget child) => GameScope(
      notifier: state,
      child: GameRepositoryScope(repository: LocalGameRepository(state), child: child),
    );

/// 챗봇 채팅방에서 말 보내기 (11-12: 빠른 답장 버튼을 없애고 말로만 답한다).
Future<void> say(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.text('보내기'));
  await tester.pump();
  await tester.pump();
}
