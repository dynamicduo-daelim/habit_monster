import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'game_state.dart';

/// 단계별로 열리는 기능 (기획 2026-11-26-단계별-열기, D-100).
enum Feature {
  field('필드', '루틴몬들이 사는 곳이에요. 상점 · 출석부 · 습관 관리도 여기 있어요.', '오늘 습관을 체크하면 열려요'),
  bag('가방', '잡은 루틴몬과 산 물건이 들어 있어요. 필드로 꺼내거나 넣을 수 있어요.', '루틴몬을 2마리 모으면 열려요'),
  gift('선물함', '퀘스트를 깨면 보상이 여기 쌓여요. 눌러서 받아요.', '퀘스트를 깨면 열려요'),
  dex('도감', '만난 루틴몬이 기록돼요. 많이 모으면 새 카테고리를 열 수 있어요.', '시작하고 3일째에 열려요'),
  stats('통계', '연속 출석과 성실도 그래프, 카테고리 레벨을 볼 수 있어요.', '시작하고 3일째에 열려요');

  const Feature(this.label, this.description, this.lockHint);
  final String label;
  final String description;

  /// 잠긴 탭을 눌렀을 때 보여 줄 여는 조건 ([Unlocks.evaluate]와 맞춘다).
  final String lockHint;
}

/// 열린 기능을 기기에 저장하는 곳. 테스트는 [MemoryUnlockStore].
abstract class UnlockStore {
  Future<Map<String, String>> read();
  Future<void> write(Map<String, String> values);
}

class MemoryUnlockStore implements UnlockStore {
  MemoryUnlockStore([Map<String, String>? initial]) : _v = {...?initial};
  final Map<String, String> _v;
  @override
  Future<Map<String, String>> read() async => {..._v};
  @override
  Future<void> write(Map<String, String> values) async => _v
    ..clear()
    ..addAll(values);
}

/// 기기 저장 (이미 쓰는 flutter_secure_storage — 새 패키지 없음).
class SecureUnlockStore implements UnlockStore {
  static const _s = FlutterSecureStorage();
  static const _keys = ['unlock.fresh', 'unlock.start', 'unlock.open'];
  @override
  Future<Map<String, String>> read() async {
    final out = <String, String>{};
    for (final k in _keys) {
      final v = await _s.read(key: k);
      if (v != null) out[k] = v;
    }
    return out;
  }

  @override
  Future<void> write(Map<String, String> values) async {
    for (final k in _keys) {
      final v = values[k];
      if (v == null) {
        await _s.delete(key: k);
      } else {
        await _s.write(key: k, value: v);
      }
    }
  }
}

/// 단계별 열기 상태. 온보딩을 **새로 마친** 사람만 잠겨 있고([fresh]), 그 밖에는 전부 열려 있다.
/// 조건은 게임 상태로 계산하고, 한 번 열린 것은 저장해 계속 열려 있다.
class Unlocks extends ChangeNotifier {
  Unlocks(this._store);
  final UnlockStore _store;

  bool _fresh = false;
  int _startDay = 0;
  final Set<Feature> _open = {};
  bool loaded = false;

  /// 새로 시작한 사람인지 (아니면 전부 열림).
  bool get fresh => _fresh;

  bool isOpen(Feature f) => !_fresh || _open.contains(f);

  Future<void> load() async {
    try {
      final v = await _store.read();
      _fresh = v['unlock.fresh'] == '1';
      _startDay = int.tryParse(v['unlock.start'] ?? '') ?? 0;
      _open
        ..clear()
        ..addAll([
          for (final n in (v['unlock.open'] ?? '').split(','))
            for (final f in Feature.values)
              if (f.name == n) f,
        ]);
    } catch (_) {
      _fresh = false; // 저장소를 못 읽으면 전부 열림
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await _store.write({
        if (_fresh) 'unlock.fresh': '1',
        if (_fresh) 'unlock.start': '$_startDay',
        if (_fresh) 'unlock.open': _open.map((f) => f.name).join(','),
      });
    } catch (_) {}
  }

  /// 온보딩을 막 마쳤다: 오늘 · 챗봇만 열린 상태로 시작.
  Future<void> startFresh(int dayCount) async {
    _fresh = true;
    _startDay = dayCount;
    _open.clear();
    notifyListeners();
    await _save();
  }

  /// 조건을 다시 본다 → 이번에 새로 열린 기능 (없으면 빈 목록).
  List<Feature> evaluate(GameState s) {
    if (!_fresh) return const [];
    final days = s.dayCount - _startDay; // 온보딩한 날 = 0
    final cond = <Feature, bool>{
      Feature.field: s.checkedInToday || s.todayRecords.isNotEmpty || days >= 1,
      Feature.bag: s.monsters.length >= 2,
      Feature.gift: s.hasPendingGift,
      Feature.dex: days >= 2,
      Feature.stats: days >= 2,
    };
    final opened = [
      for (final f in Feature.values)
        if (!_open.contains(f) && cond[f] == true) f,
    ];
    if (opened.isEmpty) return const [];
    _open.addAll(opened);
    notifyListeners();
    _save();
    return opened;
  }

  /// 시험용: 전부 연다.
  void openAll() {
    _open.addAll(Feature.values);
    notifyListeners();
    _save();
  }
}

class UnlocksScope extends InheritedNotifier<Unlocks> {
  const UnlocksScope({super.key, required Unlocks unlocks, required super.child}) : super(notifier: unlocks);

  /// 없으면 null — 그때는 전부 열린 것으로 본다 (테스트 · 저장소 없는 화면).
  static Unlocks? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<UnlocksScope>()?.notifier;
}
