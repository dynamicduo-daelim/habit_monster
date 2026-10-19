import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/results.dart';
import '../api/api_client.dart';
import 'game_repository.dart';
import 'game_state.dart';
import 'local_game_repository.dart';

/// 서버 API로 동작하는 [GameRepository] (`API_BASE_URL`을 주고 빌드했을 때).
///
/// 서버가 규칙을 계산하고, 이 클래스는 응답을 [GameState]의 `apply…` 메서드로 옮긴다.
/// 아직 서버 API가 없는 동작은 [LocalGameRepository]에 넘긴다 — 그 결과는 앱 안에만 있고 서버에 저장되지 않는다.
/// 넘기는 메서드에는 "3-x에서 서버로"라고 적어 두고, 단계마다 하나씩 서버로 옮긴다 (`docs/handoff/`).
///
/// 서버 id ↔ 앱 모델 (결정 D2 · D-38):
/// - 몬스터 `uid` = 서버 `userMonsterId` 문자열, 종 = `imageKey`(= 종 코드 = 앱 종 id)
/// - 습관 `id` = 서버 `habitId` 문자열, 측정 항목 = `GET /measure-types`의 (카테고리, 순서) ↔ `measureTypeId`
/// - 목표 `id` = 서버 `goalId` 문자열, 아이템 = [Catalog.itemByServerCode]
class HttpGameRepository implements GameRepository {
  HttpGameRepository(this.state, this.api) : _local = LocalGameRepository(state);

  final GameState state;
  final ApiClient api;
  final LocalGameRepository _local;

  static const _periodCodes = ['D7', 'D30', 'D100'];

  /// 측정 항목 id → (카테고리, 카테고리 안 순서). 앱 [Habit.measureIndex]가 그 순서다. 한 번 받아 두고 계속 쓴다.
  Map<int, (String, int)>? _measures;

  /// 마지막으로 불러온 업무 날짜. 앱이 다른 날짜로 돌아오면 다시 불러온다.
  String? _businessDate;

  Future<Map<int, (String, int)>> _measureTable() async {
    final cached = _measures;
    if (cached != null) return cached;
    final groups = (await api.get('/measure-types') as List).cast<Map<String, dynamic>>();
    final table = <int, (String, int)>{};
    for (final g in groups) {
      final types = (g['measureTypes'] as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < types.length; i++) {
        table[types[i]['id'] as int] = (g['categoryCode'] as String, i);
      }
    }
    return _measures = table;
  }

  int _measureTypeId(Map<int, (String, int)> table, Habit h) =>
      table.entries.firstWhere((e) => e.value == (h.categoryId, h.measureIndex)).key;

  // ---------- 조회 (3-2) ----------

  /// 홈을 그릴 데이터를 모두 불러온다: 상단 바 · 오늘 요약 · 연 카테고리 · 몬스터 · 가방 · 습관 · 목표.
  /// 몬스터 목록엔 호감도 · 경험치가 없어서 마리마다 상세(`GET /monsters/{id}`)를 같이 부른다 (명세 그대로).
  @override
  Future<void> load() async {
    final r = await Future.wait([
      api.get('/me/status'),
      api.get('/me/today'),
      api.get('/categories'),
      api.get('/monsters'),
      api.get('/inventory'),
      api.get('/habits'),
      api.get('/goals'),
      _measureTable(),
    ]);
    final status = r[0] as Map<String, dynamic>;
    final today = r[1] as Map<String, dynamic>;
    final list = (r[3] as List).cast<Map<String, dynamic>>().where((m) => _knownSpecies(m['imageKey'])).toList();
    final details = (await Future.wait(list.map((m) => api.get('/monsters/${m['userMonsterId']}'))))
        .cast<Map<String, dynamic>>();
    final measures = r[7] as Map<int, (String, int)>;

    final items = ((r[4] as Map<String, dynamic>)['items'] as List).cast<Map<String, dynamic>>();
    final potions = <String, int>{};
    for (final it in items) {
      final item = Catalog.itemByServerCode(it['itemCode'] as String);
      if (item != null && item.id != Catalog.seongsilBall.id) potions[item.id] = it['quantity'] as int;
    }

    state
      ..applyStatus(
        gold: status['gold'] as int,
        balls: status['ballCount'] as int,
        currentStreak: status['currentStreak'] as int,
        checkedInToday: status['checkedInToday'] as bool,
        exploreRemaining: status['exploreRemaining'] as int,
        dayCount: status['dayCount'] as int,
      )
      ..applyCategories([
        for (final c in (r[2] as List).cast<Map<String, dynamic>>())
          if (c['opened'] == true) c['code'] as String,
      ])
      ..applyMonsters(
        [for (final d in details) _monster(d)],
        partnerUid: list.where((m) => m['isPartner'] == true).map((m) => '${m['userMonsterId']}').firstOrNull,
      )
      ..applyPotions(potions)
      ..applyHabits([
        for (final h in (r[5] as List).cast<Map<String, dynamic>>())
          if (measures.containsKey(h['measureTypeId'])) _habit(h, measures),
      ])
      ..applyGoals(_goals(r[6] as Map<String, dynamic>));
    if (today['checkedIn'] == true) {
      final hs = (today['habits'] as List).cast<Map<String, dynamic>>();
      state.applyToday(
        values: {for (final h in hs) '${h['habitId']}': (h['rewardedValue'] as num).toDouble()},
        scores: {for (final h in hs) '${h['habitId']}': h['rewardedScore'] as int},
        counted: {for (final h in hs) if (h['counted'] == true) '${h['habitId']}'},
      );
    }
    _businessDate = status['businessDate'] as String;
    state.markLoaded();
  }

  static bool _knownSpecies(Object? code) => Catalog.species.any((s) => s.id == code);

  static OwnedMonster _monster(Map<String, dynamic> d) {
    final actions = d['todayActions'] as Map<String, dynamic>;
    return OwnedMonster(
      uid: '${d['userMonsterId']}',
      speciesId: d['imageKey'] as String,
      level: d['level'] as int,
      exp: d['expInLevel'] as int,
      affection: d['affection'] as int,
      inField: d['location'] == 'FIELD',
      pettedToday: actions['pet'] as bool,
      playedToday: actions['play'] as bool,
    );
  }

  static Habit _habit(Map<String, dynamic> h, Map<int, (String, int)> measures) {
    final (category, index) = measures[h['measureTypeId']]!;
    return Habit(
      id: '${h['habitId']}',
      name: h['name'] as String? ?? '',
      categoryId: category,
      measureIndex: index,
      target: (h['dailyTarget'] as num).toDouble(),
      periodIndex: _periodCodes.indexOf(h['periodCode'] as String).clamp(0, _periodCodes.length - 1),
    );
  }

  static List<Goal> _goals(Map<String, dynamic> json) => [
        for (final (key, tier) in [('weekly', GoalTier.weekly), ('monthly', GoalTier.monthly)])
          for (final g in ((json[key] as Map<String, dynamic>)['goals'] as List).cast<Map<String, dynamic>>())
            Goal(
              id: '${g['goalId']}',
              tier: tier,
              title: g['title'] as String? ?? '',
              detail: g['detail'] as String? ?? '',
              done: g['status'] == 'COMPLETED',
            ),
      ];

  // ---------- 출석 · 온보딩 (3-1) ----------

  /// 오늘 출석. 앱이 다른 업무 날짜로 돌아왔으면(자정을 넘겨 다시 열었으면) 오늘 데이터를 다시 불러온다.
  @override
  Future<bool> attend() async {
    final res = await api.send('POST', '/me/attendance') as Map<String, dynamic>;
    if (_businessDate != null && res['date'] != _businessDate) await load();
    state.applyAttendance(currentStreak: res['currentStreak'] as int);
    return res['alreadyAttended'] != true;
  }

  /// 온보딩 일괄 제출 (`POST /onboarding`, 중복 방지 키). 서버가 스타터 · 대화 상대 · 습관 · 목표를 만들고,
  /// 끝나면 [load]로 서버 상태를 그대로 받아 온다. 1단계에서 고른 첫 파트너는 `partnerCategory`로 보낸다 (결정 D-36).
  @override
  Future<void> completeOnboarding({
    required List<String> picked,
    required List<Habit> habits,
    required List<Goal> goals,
    String? starterCategory,
  }) async {
    final table = await _measureTable();
    await api.send('POST', '/onboarding', idempotent: true, body: {
      'categories': picked,
      if (starterCategory != null) 'partnerCategory': starterCategory,
      'habits': [
        for (final h in habits)
          {
            'categoryCode': h.categoryId,
            'measureTypeId': _measureTypeId(table, h),
            'name': h.name,
            'dailyTarget': h.target,
            'periodCode': _periodCodes[h.periodIndex],
          },
      ],
      'goals': [
        for (final g in goals)
          {
            'goalType': g.tier == GoalTier.weekly ? 'WEEKLY' : 'MONTHLY',
            'title': g.title,
            if (g.detail.isNotEmpty) 'detail': g.detail,
          },
      ],
    });
    await load();
  }

  // ---------- 아직 앱 안에서 계산 (서버에 저장되지 않음) ----------

  /// 3-5에서 서버로 (`POST /shop/purchases`).
  @override
  Future<bool> buy(ShopItem item, {int count = 1}) => _local.buy(item, count: count);

  /// 3-3에서 서버로 (`POST /checkins/today`).
  @override
  Future<DailyCheckinResult?> confirmCheckin(Map<String, double> answers) => _local.confirmCheckin(answers);

  /// 3-3에서 서버로 (`PUT /checkins/today`).
  @override
  Future<DailyCheckinResult?> resubmitCheckin(Map<String, double> answers) => _local.resubmitCheckin(answers);

  /// 3-4에서 서버로 (`POST /explores`).
  @override
  Future<EncounterResult?> explore() => _local.explore();

  /// 3-4에서 서버로 (`POST /explores/{id}/capture`).
  @override
  Future<CatchResult?> throwBall(MonsterSpecies species) => _local.throwBall(species);

  /// 3-5에서 서버로 (`POST /monsters/{id}/affection` PET).
  @override
  Future<int> pet(OwnedMonster m) => _local.pet(m);

  /// 3-5에서 서버로 (`POST /monsters/{id}/affection` PLAY).
  @override
  Future<int> play(OwnedMonster m) => _local.play(m);

  /// 3-5에서 서버로 (`POST /monsters/{id}/feed`).
  @override
  Future<int> feed(OwnedMonster m, ShopItem potion) => _local.feed(m, potion);

  /// 명세 v5 · DB v1.7에 없음 (D-20) — 3-5에서 명세 · DB 다음 판과 함께 정한다.
  @override
  Future<int> dragMonster(OwnedMonster m) => _local.dragMonster(m);

  /// 3-5에서 서버로 (`PATCH /monsters/{id}/location`).
  @override
  Future<bool> moveMonster(OwnedMonster m, {required bool toField}) => _local.moveMonster(m, toField: toField);

  /// 3-5에서 서버로 (`PUT /me/partner`).
  @override
  Future<void> setPartner(OwnedMonster m) => _local.setPartner(m);

  /// 4단계에서 서버로 (`POST /categories/{code}/unlock`).
  @override
  Future<bool> openCategory(String categoryId) => _local.openCategory(categoryId);

  /// 4단계에서 서버로 (`POST /habits`).
  @override
  Future<Habit?> addHabit({
    required String name,
    required String categoryId,
    required int measureIndex,
    required double target,
    required int periodIndex,
  }) =>
      _local.addHabit(
          name: name, categoryId: categoryId, measureIndex: measureIndex, target: target, periodIndex: periodIndex);

  /// 4단계에서 서버로 (`POST /habits/{id}/stop`).
  @override
  Future<bool> removeHabit(Habit h) => _local.removeHabit(h);

  /// 4단계에서 서버로 (`POST /goals`).
  @override
  Future<Goal> addGoal(GoalTier tier, String title, String detail) => _local.addGoal(tier, title, detail);

  /// 4단계에서 서버로 (`PATCH /goals/{id}`).
  @override
  Future<void> updateGoal(Goal g, String title, String detail) => _local.updateGoal(g, title, detail);

  /// 4단계에서 서버로 (`DELETE /goals/{id}`).
  @override
  Future<bool> deleteGoal(Goal g) => _local.deleteGoal(g);

  /// 4단계에서 서버로 (`POST /goals/{id}/complete`).
  @override
  Future<bool> completeGoal(Goal g) => _local.completeGoal(g);

  /// 결제는 MVP 밖 — 앱 안에서만.
  @override
  Future<void> unlockExtraWeeklySlot() => _local.unlockExtraWeeklySlot();
}
