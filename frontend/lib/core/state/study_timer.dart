import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../audio/bgm.dart';

/// 공부 소리 (집중하는 동안 배경음악 대신).
enum StudySound {
  rain('빗소리', '잔잔한 비', BgmTrack.studyRain),
  pencil('사각사각', '연필로 필기', BgmTrack.studyPencil),
  cafe('카페', '웅성웅성 백색소음', BgmTrack.studyCafe),
  off('소리 끄기', '조용히', BgmTrack.quiet);

  const StudySound(this.label, this.hint, this.track);
  final String label;
  final String hint;
  final BgmTrack track;
}

/// 뽀모도로 단계.
enum StudyPhase { focus, rest }

/// 공부 타이머 (기획 2026-10-29-AI-챗봇-체크인 3-5, 결정 D-57 · D-58 · D-59). 챗봇 탭 옆 칸에서 쓴다.
///
/// **뽀모도로**: 집중 [focusMinutes]분 → 쉬는 시간 [breakMinutes]분을 반복한다 ([free]면 시간 제한 없이).
/// 단계는 따로 저장하지 않고 "시작한 뒤 흐른 시간(일시정지 뺌)"에서 계산한다 — 앱을 닫았다 열어도 그대로 이어진다.
/// 끝내면 **집중한 분만** 그날 그 공부 습관에 쌓이고(쉬는 시간은 빼고), 집중을 한 번 마칠 때마다 토마토가 하나 쌓인다.
/// 한 번에 최대 [maxMinutes]분 (켜 두고 자는 것을 막는다). 기기에만 저장한다 — 서버 기록은 DB 제안 3번 합의 뒤.
class StudyTimer extends ChangeNotifier {
  StudyTimer({StudyTimerStore? store, DateTime Function()? clock})
      : store = store ?? MemoryStudyTimerStore(),
        _clock = clock ?? DateTime.now;

  static const int maxMinutes = 240;
  static const int maxFriends = 3;

  final StudyTimerStore store;
  final DateTime Function() _clock;

  // ---------- 설정 (톱니바퀴) ----------
  int focusMinutes = 25;
  int breakMinutes = 5;

  /// 시간 제한 없이 (뽀모도로 끔).
  bool free = false;
  StudySound sound = StudySound.rain;

  /// 같이 공부하는 몬스터 uid (최대 [maxFriends]). 비어 있으면 화면이 대화 상대를 쓴다.
  List<String> friends = [];

  // ---------- 재는 중 ----------
  /// 재고 있는 습관 (없으면 쉬는 중).
  String? habitId;
  DateTime? startedAt;

  /// 지금 일시정지 중이면 그 시각.
  DateTime? pausedAt;

  /// 지금까지 일시정지한 총 시간.
  Duration paused = Duration.zero;

  /// 날짜(yyyy-MM-dd) → 습관 id → 그날 집중한 분.
  final Map<String, Map<String, int>> minutes = {};

  /// 날짜 → 그날 모은 토마토(집중을 끝까지 마친 횟수).
  final Map<String, int> tomatoes = {};

  bool get running => habitId != null && pausedAt == null;
  bool get isPaused => habitId != null && pausedAt != null;
  bool get idle => habitId == null;

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 시작한 뒤 흐른 시간 (일시정지 뺌, 최대 [maxMinutes]분).
  Duration get elapsed {
    final start = startedAt;
    if (start == null) return Duration.zero;
    final end = pausedAt ?? _clock();
    final d = end.difference(start) - paused;
    const cap = Duration(minutes: maxMinutes);
    return d.isNegative ? Duration.zero : (d > cap ? cap : d);
  }

  int get _cycle => (focusMinutes + breakMinutes) * 60;

  /// 지금 단계 (자유 모드는 늘 집중).
  StudyPhase get phase {
    if (free) return StudyPhase.focus;
    return elapsed.inSeconds % _cycle < focusMinutes * 60 ? StudyPhase.focus : StudyPhase.rest;
  }

  /// 몇 번째 집중인지 (1부터).
  int get round => free ? 1 : elapsed.inSeconds ~/ _cycle + 1;

  /// 이번에 집중한 시간 (쉬는 시간 뺌).
  Duration get focused {
    final e = elapsed.inSeconds;
    if (free) return Duration(seconds: e);
    final full = e ~/ _cycle;
    final pos = e % _cycle;
    return Duration(seconds: full * focusMinutes * 60 + (pos < focusMinutes * 60 ? pos : focusMinutes * 60));
  }

  /// 이번에 모은 토마토 (집중을 끝까지 마친 횟수).
  int get sessionTomatoes {
    if (free) return 0;
    final e = elapsed.inSeconds;
    return e ~/ _cycle + (e % _cycle >= focusMinutes * 60 ? 1 : 0);
  }

  /// 시계에 보일 시간: 뽀모도로면 이 단계의 남은 시간, 자유면 흐른 시간.
  Duration get display {
    if (free) return elapsed;
    if (idle) return Duration(minutes: focusMinutes);
    final pos = elapsed.inSeconds % _cycle;
    final left = pos < focusMinutes * 60 ? focusMinutes * 60 - pos : _cycle - pos;
    return Duration(seconds: left);
  }

  /// 최대 시간을 넘겼는지 (화면이 1초마다 보고 자동으로 끝낸다).
  bool get overLimit => !idle && elapsed >= const Duration(minutes: maxMinutes);

  /// 그날 그 습관에 쌓인 분 (재는 중인 시간은 빼고).
  int todayMinutes(String habitId, {DateTime? day}) => minutes[dayKey(day ?? _clock())]?[habitId] ?? 0;

  int todayTomatoes({DateTime? day}) => tomatoes[dayKey(day ?? _clock())] ?? 0;

  Future<void> restore() async {
    try {
      final raw = await store.read();
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      habitId = j['habitId'] as String?;
      startedAt = j['startedAt'] == null ? null : DateTime.parse(j['startedAt'] as String);
      pausedAt = j['pausedAt'] == null ? null : DateTime.parse(j['pausedAt'] as String);
      paused = Duration(seconds: j['pausedSeconds'] as int? ?? 0);
      focusMinutes = j['focusMinutes'] as int? ?? 25;
      breakMinutes = j['breakMinutes'] as int? ?? 5;
      free = j['free'] as bool? ?? false;
      sound = StudySound.values.where((e) => e.name == j['sound']).firstOrNull ?? StudySound.rain;
      friends = [for (final f in j['friends'] as List? ?? const []) f as String];
      minutes
        ..clear()
        ..addAll({
          for (final e in (j['minutes'] as Map<String, dynamic>? ?? {}).entries)
            e.key: (e.value as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
        });
      tomatoes
        ..clear()
        ..addAll((j['tomatoes'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, v as int)));
      notifyListeners();
    } catch (_) {
      // 저장소를 못 읽으면 빈 타이머로
    }
  }

  // ---------- 설정 바꾸기 (재는 중엔 시간 설정을 못 바꾼다) ----------
  void setFocusMinutes(int m) {
    if (!idle) return;
    focusMinutes = m.clamp(5, 90);
    _changed();
  }

  void setBreakMinutes(int m) {
    if (!idle) return;
    breakMinutes = m.clamp(1, 30);
    _changed();
  }

  void setFree(bool on) {
    if (!idle) return;
    free = on;
    _changed();
  }

  void setSound(StudySound s) {
    sound = s;
    _changed();
  }

  /// 같이 공부할 친구 넣기 · 빼기 (최대 [maxFriends], 한 마리는 남긴다).
  void toggleFriend(String uid) {
    if (friends.contains(uid)) {
      if (friends.length > 1) friends.remove(uid);
    } else if (friends.length < maxFriends) {
      friends.add(uid);
    }
    _changed();
  }

  void setFriends(List<String> uids) {
    friends = uids.take(maxFriends).toList();
    _changed();
  }

  // ---------- 재기 ----------
  void start(String habitId) {
    if (!idle) return;
    this.habitId = habitId;
    startedAt = _clock();
    pausedAt = null;
    paused = Duration.zero;
    _changed();
  }

  void pause() {
    if (!running) return;
    pausedAt = _clock();
    _changed();
  }

  void resume() {
    final p = pausedAt;
    if (p == null || idle) return;
    paused += _clock().difference(p);
    pausedAt = null;
    _changed();
  }

  /// 끝내기: 집중한 분을 쌓는다 (1분 미만은 버림). 자정을 넘겼으면 00시를 기준으로 날짜를 나눈다.
  /// 돌려주는 값 = 이번에 쌓은 분.
  int stop() {
    final id = habitId;
    final start = startedAt;
    if (id == null || start == null) return 0;
    final total = focused.inMinutes;
    final got = sessionTomatoes;
    // 시작한 날 자정까지 몫 (일시정지 · 쉬는 시간은 앞날에서 뺀다고 본다 — 단순하게)
    final midnight = DateTime(start.year, start.month, start.day + 1);
    final firstDay = total <= 0 ? 0 : midnight.difference(start).inMinutes.clamp(0, total);
    void add(DateTime d, int m) {
      if (m <= 0) return;
      final day = minutes.putIfAbsent(dayKey(d), () => {});
      day[id] = (day[id] ?? 0) + m;
    }

    add(start, firstDay);
    add(midnight, total - firstDay);
    if (got > 0) tomatoes[dayKey(_clock())] = (tomatoes[dayKey(_clock())] ?? 0) + got;
    habitId = null;
    startedAt = null;
    pausedAt = null;
    paused = Duration.zero;
    _changed();
    return total;
  }

  void _changed() {
    notifyListeners();
    // 오늘 · 어제 기록만 남긴다 (체크인은 그날만 쓰니까)
    final keep = {dayKey(_clock()), dayKey(_clock().subtract(const Duration(days: 1)))};
    minutes.removeWhere((k, _) => !keep.contains(k));
    tomatoes.removeWhere((k, _) => !keep.contains(k));
    store
        .write(jsonEncode({
          'habitId': habitId,
          'startedAt': startedAt?.toIso8601String(),
          'pausedAt': pausedAt?.toIso8601String(),
          'pausedSeconds': paused.inSeconds,
          'focusMinutes': focusMinutes,
          'breakMinutes': breakMinutes,
          'free': free,
          'sound': sound.name,
          'friends': friends,
          'minutes': minutes,
          'tomatoes': tomatoes,
        }))
        .catchError((_) {});
  }
}

/// 타이머 보관함. 앱에선 기기 안전 저장소, 테스트 · 기본은 메모리.
abstract class StudyTimerStore {
  Future<String?> read();
  Future<void> write(String value);
}

class MemoryStudyTimerStore implements StudyTimerStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;
}

class SecureStudyTimerStore implements StudyTimerStore {
  static const _key = 'study_timer';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String v) => _storage.write(key: _key, value: v);
}

/// 앱 전체에서 같은 타이머를 쓴다 (챗봇 탭 · 체크인 미리 채우기).
class StudyTimerScope extends InheritedNotifier<StudyTimer> {
  const StudyTimerScope({super.key, required StudyTimer super.notifier, required super.child});

  /// 없으면 null (위젯 테스트 등) — 부르는 쪽이 자기 타이머를 만든다.
  static StudyTimer? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudyTimerScope>()?.notifier;
}
