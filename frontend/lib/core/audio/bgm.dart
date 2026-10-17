import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

/// 배경음악 곡. 파일은 `assets/audio/bgm/<이름>.mp3`.
enum BgmTrack { intro, home, chat, explore, shop }

/// 배경음악. 화면이 "지금 이 곡"을 요청하면 이전 곡을 줄이고 새 곡을 키운다(크로스페이드).
abstract class Bgm extends ChangeNotifier {
  /// 켜져 있는지 (상단 바 스피커 버튼).
  bool get enabled;
  void setEnabled(bool on);

  /// 이 곡을 반복 재생한다 (이미 그 곡이면 그대로).
  void play(BgmTrack track);

  /// 첫 터치 때 다시 시도 (웹 브라우저는 사용자가 누르기 전엔 소리를 막는다).
  void unlock();
}

/// 소리 없는 버전 (테스트 · BgmScope 밖).
class SilentBgm extends Bgm {
  bool _on = true;
  BgmTrack? lastRequested;

  @override
  bool get enabled => _on;

  @override
  void setEnabled(bool on) {
    _on = on;
    notifyListeners();
  }

  @override
  void play(BgmTrack track) => lastRequested = track;

  @override
  void unlock() {}
}

/// 실제 재생 (audioplayers).
/// 앱이 화면에서 벗어나면(홈 버튼 · 다른 앱 · 브라우저 탭 숨김) 멈추고, 돌아오면 이어서 튼다.
class AudioBgm extends Bgm with WidgetsBindingObserver {
  AudioBgm() {
    WidgetsBinding.instance.addObserver(this);
  }

  static const double _volume = 0.45;
  static const int _fadeSteps = 8;
  static const Duration _fadeStep = Duration(milliseconds: 40); // 페이드 약 0.3초

  final AudioPlayer _player = AudioPlayer(playerId: 'bgm');
  BgmTrack? _want;
  BgmTrack? _playing;
  bool _on = true;
  bool _busy = false;
  bool _away = false; // 앱이 화면에 안 보이는 중
  double _vol = 0;

  /// 앱 상태(라이프사이클)가 바뀔 때 Flutter가 부른다.
  /// 안 보이면(hidden · paused · detached) 일시정지, 다시 보이면(resumed) 이어서 재생.
  /// inactive(알림창을 내리거나 창이 포커스만 잃은 상태)는 아직 보이므로 그대로 둔다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _setAway(false);
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _setAway(true);
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _setAway(bool away) {
    if (_away == away) return;
    _away = away;
    if (away) {
      _player.pause();
    } else {
      if (_playing != null) {
        _player.resume();
        final same = (_on ? _want : null) == _playing;
        if (same && !_busy && _vol < _volume) _fadeTo(_volume); // 키우던 중에 나갔으면 마저 키운다
      }
      _sync(); // 나가 있는 동안 곡 요청이 바뀌었으면 맞춘다 (같은 곡이면 아무것도 안 함)
    }
  }

  @override
  bool get enabled => _on;

  @override
  void setEnabled(bool on) {
    _on = on;
    notifyListeners();
    _sync();
  }

  @override
  void play(BgmTrack track) {
    _want = track;
    _sync();
  }

  @override
  void unlock() {
    if (_playing != _want) _sync();
  }

  /// 원하는 곡과 실제 재생 곡을 맞춘다. 페이드 중에 요청이 바뀌면 끝난 뒤 다시 맞춘다.
  Future<void> _sync() async {
    if (_busy) return;
    _busy = true;
    try {
      while (!_away) {
        final target = _on ? _want : null;
        if (target == _playing) break;
        if (_playing != null) {
          await _fadeTo(0);
          await _player.stop();
          _playing = null;
        }
        if (target != null) {
          await _player.setReleaseMode(ReleaseMode.loop);
          await _player.play(AssetSource('audio/bgm/${target.name}.mp3'), volume: 0);
          _playing = target;
          if (_away) {
            await _player.pause(); // 재생을 시작하는 사이에 앱을 벗어났으면
            break;
          }
          await _fadeTo(_volume);
        }
      }
    } catch (_) {
      // 웹 자동재생 차단 등: 다음 터치(unlock) 때 다시 시도
      _playing = null;
    } finally {
      _busy = false;
    }
  }

  Future<void> _fadeTo(double to) async {
    final from = _vol;
    for (var i = 1; i <= _fadeSteps; i++) {
      _vol = from + (to - from) * i / _fadeSteps;
      await _player.setVolume(_vol);
      await Future<void>.delayed(_fadeStep);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }
}

/// 위젯 트리에서 `BgmScope.of(context)`로 배경음악을 꺼내 쓴다. 없으면 소리 없는 버전.
class BgmScope extends InheritedNotifier<Bgm> {
  const BgmScope({super.key, required Bgm super.notifier, required super.child});

  static final Bgm _silent = SilentBgm();

  /// 스피커 버튼처럼 켜짐/꺼짐이 바뀌면 다시 그려야 할 때.
  static Bgm of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BgmScope>()?.notifier ?? _silent;

  /// 곡만 바꿀 때 (다시 그리기 구독 없음).
  static Bgm read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BgmScope>()?.notifier ?? _silent;
}
