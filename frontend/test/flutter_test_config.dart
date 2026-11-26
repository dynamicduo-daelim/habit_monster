import 'dart:async';

import 'package:habit_monster/features/chat/chat_controller.dart';

/// 모든 테스트 전에: 챗봇 "입력 중" 최소 시간을 0으로 (대답을 기다리느라 테스트마다 시간을 흘리지 않게).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ChatController.minThinkTime = Duration.zero;
  await testMain();
}
