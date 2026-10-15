import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/game_repository.dart';
import 'main_shell.dart';

/// 게임 동작 하나를 실행한다: `final ok = await runGameAction(context, (repo) => repo.buy(item));`
///
/// 서버 오류(`ApiException`)가 나면 그 문구를 토스트로 보여주고 null을 돌려준다 — 화면마다 try/catch를 쓰지 않게.
/// 토스트는 홈 셸([MainShell])의 것을 쓰고, 셸 밖(따로 띄운 화면)에서는 [onError]를 넘기거나 SnackBar로 보여준다.
Future<T?> runGameAction<T>(
  BuildContext context,
  Future<T> Function(GameRepository repo) action, {
  void Function(String message)? onError,
}) async {
  final repo = GameRepositoryScope.of(context);
  try {
    return await action(repo);
  } on ApiException catch (e) {
    if (context.mounted) (onError ?? (m) => _toast(context, m))(e.message);
    return null;
  }
}

void _toast(BuildContext context, String message) {
  final shell = context.findAncestorStateOfType<MainShellState>();
  if (shell != null) {
    shell.toast(message);
  } else {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }
}
