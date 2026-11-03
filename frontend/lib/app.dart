import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'core/audio/bgm.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/login_prefs.dart';
import 'core/state/game_repository.dart';
import 'core/state/game_state.dart';
import 'core/state/http_game_repository.dart';
import 'core/state/local_game_repository.dart';
import 'core/state/study_timer.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_gate.dart';

/// 앱 루트. 로그인 상태(AuthScope) · 게임 상태(GameScope, 읽기) · 게임 동작(GameRepositoryScope, 바꾸기) ·
/// 배경음악(BgmScope)을 하위 위젯에 내려준다.
class HabitMonsterApp extends StatefulWidget {
  const HabitMonsterApp({super.key, this.authService, this.bgm, this.api, this.loginPrefs, this.timerStore});

  /// 테스트나 서버 연결 때 다른 인증 구현을 넣는다 (기본: 앱 안에서만 동작하는 FakeAuthService).
  final AuthService? authService;

  /// 게임 API 통신기. 있으면 **서버 모드**: 빈 상태로 시작해 서버 데이터를 불러오고([HttpGameRepository]),
  /// 없으면 샘플 데이터 + 앱 안 계산([LocalGameRepository]).
  final ApiClient? api;

  /// 최근 로그인 · 아이디 저장 · 자동 로그인 보관함 (기본: 메모리 — 앱에선 `main.dart`가 기기 저장소를 넣는다).
  final LoginPrefsStore? loginPrefs;

  /// 공부 타이머 보관함 (기본: 메모리 — 앱에선 `main.dart`가 기기 저장소를 넣는다).
  final StudyTimerStore? timerStore;

  /// 테스트에선 소리 없는 [SilentBgm] (기본: 실제로 재생하는 [AudioBgm]).
  final Bgm? bgm;

  @override
  State<HabitMonsterApp> createState() => _HabitMonsterAppState();
}

class _HabitMonsterAppState extends State<HabitMonsterApp> {
  late GameState _state = _newState();

  /// 화면이 게임 상태를 바꿀 때 쓰는 쪽. 서버 모드면 서버 API, 아니면 앱 안에서 계산.
  late GameRepository _repository = _repositoryFor(_state);
  late final Bgm _bgm = widget.bgm ?? AudioBgm();
  late final AuthController _auth = AuthController(
    widget.authService ?? FakeAuthService(),
    onSignedOut: _resetGame,
    prefsStore: widget.loginPrefs,
  );
  late final StudyTimer _timer = StudyTimer(store: widget.timerStore);

  GameState _newState() => widget.api != null ? GameState.empty() : GameState.sample();

  GameRepository _repositoryFor(GameState s) {
    final api = widget.api;
    return api != null ? HttpGameRepository(s, api) : LocalGameRepository(s);
  }

  @override
  void initState() {
    super.initState();
    // 서버가 "날짜가 바뀌었다"고 거절하면 오늘 데이터를 다시 불러온다
    widget.api?.onBusinessDateChanged = () => _repository.load();
    _auth.restore();
    _timer.restore();
  }

  /// 로그아웃하면 게임 상태를 새로 (다른 계정에 이전 계정 데이터가 보이지 않게). 서버 모드면 다시 빈 상태.
  void _resetGame() {
    final old = _state;
    setState(() {
      _state = _newState();
      _repository = _repositoryFor(_state);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _state.dispose();
    _bgm.dispose();
    _auth.dispose();
    _timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StudyTimerScope(
      notifier: _timer,
      child: AuthScope(
      notifier: _auth,
      child: GameScope(
        notifier: _state,
        child: GameRepositoryScope(
          repository: _repository,
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
      ),
    ),
    );
  }
}
