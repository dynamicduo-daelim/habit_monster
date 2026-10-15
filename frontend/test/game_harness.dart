import 'package:flutter/widgets.dart';

import 'package:habit_monster/core/state/game_repository.dart';
import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/core/state/local_game_repository.dart';

/// 테스트용: 게임 상태(읽기) + 앱 안에서 계산하는 게임 동작(바꾸기)을 함께 내려준다 — 앱 루트(`app.dart`)와 같은 구성.
Widget withGame(GameState state, Widget child) => GameScope(
      notifier: state,
      child: GameRepositoryScope(repository: LocalGameRepository(state), child: child),
    );
