import 'package:flutter/material.dart';

import 'core/audio/bgm.dart';
import 'core/auth/auth_service.dart';
import 'core/state/game_state.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_gate.dart';

/// 앱 루트. 로그인 상태(AuthScope) · 게임 상태(GameScope) · 배경음악(BgmScope)을 하위 위젯에 내려준다.
class HabitMonsterApp extends StatefulWidget {
  const HabitMonsterApp({super.key, this.authService, this.bgm});

  /// 테스트나 서버 연결 때 다른 인증 구현을 넣는다 (기본: 앱 안에서만 동작하는 FakeAuthService).
  final AuthService? authService;

  /// 테스트에선 소리 없는 [SilentBgm] (기본: 실제로 재생하는 [AudioBgm]).
  final Bgm? bgm;

  @override
  State<HabitMonsterApp> createState() => _HabitMonsterAppState();
}

class _HabitMonsterAppState extends State<HabitMonsterApp> {
  GameState _state = GameState.sample();
  late final Bgm _bgm = widget.bgm ?? AudioBgm();
  late final AuthController _auth = AuthController(
    widget.authService ?? FakeAuthService(),
    onSignedOut: _resetGame,
  );

  @override
  void initState() {
    super.initState();
    _auth.restore();
  }

  /// 로그아웃하면 게임 상태를 새로 (다른 계정에 이전 계정 데이터가 보이지 않게).
  void _resetGame() {
    final old = _state;
    setState(() => _state = GameState.sample());
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _state.dispose();
    _bgm.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      notifier: _auth,
      child: GameScope(
        notifier: _state,
        child: BgmScope(
          notifier: _bgm,
          // 웹은 사용자가 화면을 누르기 전엔 소리를 막으므로, 첫 터치 때 배경음악을 다시 시도한다.
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _bgm.unlock(),
            child: MaterialApp(
              title: '모아루틴',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(),
              home: const AuthGate(),
            ),
          ),
        ),
      ),
    );
  }
}
