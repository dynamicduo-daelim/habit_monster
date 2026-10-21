import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/results.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../constants/economy.dart';
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

  /// 홈을 그릴 데이터를 모두 불러온다: 상단 바 · 오늘 요약 · 연 카테고리 · 몬스터 · 가방 · 습관 · 목표 · 오늘 체크인 대상(선택지).
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
      api.get('/checkins/today'),
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
    _applyBoard(r[8] as Map<String, dynamic>);
    _businessDate = status['businessDate'] as String;
    state.markLoaded();
  }

  /// `GET /checkins/today`: 체크인할 습관(탭 순서) · 선택지, 제출 후면 다시 체크까지 반영한 최신 값.
  void _applyBoard(Map<String, dynamic> board) {
    final hs = [
      for (final t in (board['tabs'] as List).cast<Map<String, dynamic>>())
        ...(t['habits'] as List).cast<Map<String, dynamic>>(),
    ];
    state.applyCheckinBoard(
      ids: [for (final h in hs) '${h['habitId']}'],
      options: {
        for (final h in hs) '${h['habitId']}': [for (final o in h['options'] as List) (o as num).toDouble()],
      },
      latest: {
        for (final h in hs)
          if (h['previousValue'] != null) '${h['habitId']}': (h['previousValue'] as num).toDouble(),
      },
    );
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

  // ---------- 체크인 (3-3) ----------

  /// 오늘 체크인 첫 제출 (`POST /checkins/today`, 중복 방지 키). 점수 · 반영 습관 · 골드 · 레벨 · 탐색 횟수는 서버가 정한다.
  /// [answers]: 습관 id → 값 (0 = "못 했어"). 값은 챗봇이 이미 서버 선택지로 맞춰 둔 것 ([GameState.recordableValue]).
  @override
  Future<DailyCheckinResult?> confirmCheckin(Map<String, double> answers) async {
    if (answers.isEmpty) return null;
    final res = await api.send('POST', '/checkins/today', idempotent: true, body: _checkinBody(answers))
        as Map<String, dynamic>;
    final hs = (res['habits'] as List).cast<Map<String, dynamic>>();
    final categories = (res['categoryExp'] as List).cast<Map<String, dynamic>>();
    final scores = {for (final h in hs) '${h['habitId']}': h['score'] as int};
    final counted = {for (final h in hs) if (h['counted'] == true) '${h['habitId']}'};
    state.applyCheckinResult(
      gold: res['gold'] as int,
      values: {for (final h in hs) '${h['habitId']}': answers['${h['habitId']}'] ?? 0},
      scores: scores,
      counted: counted,
      exploreTotal: res['exploreTotal'] as int,
      categoryExp: {
        for (final c in categories)
          c['categoryCode'] as String: _expTotal(c['levelAfter'] as int, c['expInLevel'] as int),
      },
    );
    return DailyCheckinResult(
      scores: [
        for (final h in hs)
          if (_habitById('${h['habitId']}') case final habit?)
            HabitScore(
              habit: habit,
              value: answers[habit.id] ?? 0,
              score: scores[habit.id]!,
              counted: counted.contains(habit.id),
            ),
      ],
      goldEarned: res['goldEarned'] as int,
      levelUps: {
        for (final c in categories)
          if ((c['levelAfter'] as int) > (c['levelBefore'] as int)) c['categoryCode'] as String: c['levelAfter'] as int,
      },
      exploreCount: res['exploreTotal'] as int,
      periodBonusGold: (res['goldBreakdown'] as Map<String, dynamic>)['periodBonus'] as int,
    );
  }

  /// 다시 체크 (`PUT /checkins/today`). 최신 값 · 점수만 바뀌고 보상은 첫 제출 그대로라 `goldEarned`는 0.
  @override
  Future<DailyCheckinResult?> resubmitCheckin(Map<String, double> answers) async {
    if (answers.isEmpty) return null;
    final res = await api.send('PUT', '/checkins/today', idempotent: true, body: _checkinBody(answers))
        as Map<String, dynamic>;
    final hs = (res['habits'] as List).cast<Map<String, dynamic>>();
    final values = {for (final h in hs) '${h['habitId']}': (h['value'] as num).toDouble()};
    final scores = {for (final h in hs) '${h['habitId']}': h['score'] as int};
    state.applyRecheck(values: values, scores: scores);
    return DailyCheckinResult(
      scores: [
        for (final h in hs)
          if (_habitById('${h['habitId']}') case final habit?)
            HabitScore(
              habit: habit,
              value: values[habit.id]!,
              score: scores[habit.id]!,
              counted: state.countedToday.contains(habit.id),
            ),
      ],
      goldEarned: 0,
      levelUps: const {},
      exploreCount: 0,
    );
  }

  /// 체크인 본문: 화면을 연 업무 날짜 + 습관마다 했는지 · 값. 서버가 정한 대상 순서대로 보낸다.
  Map<String, dynamic> _checkinBody(Map<String, double> answers) => {
        'businessDate': _businessDate,
        'answers': [
          for (final e in answers.entries)
            {
              'habitId': int.parse(e.key),
              'done': e.value > 0,
              if (e.value > 0) 'value': e.value,
            },
        ],
      };

  Habit? _habitById(String id) => state.habits.where((h) => h.id == id).firstOrNull;

  /// 레벨 · 그 레벨에서 모은 경험치 → 누적 경험치 (레벨 L까지 10 × (1 + … + (L − 1)), [CategoryLevel.fromPoints]와 같은 공식).
  static int _expTotal(int level, int expInLevel) => 10 * level * (level - 1) ~/ 2 + expInLevel;

  // ---------- 탐색 · 포획 (3-4) ----------

  /// 탐색 1회 (`POST /explores`, 중복 방지 키). 꽝 · 가진 종(골드) · 안 가진 종(등장)은 서버가 정한다.
  /// 남은 등장이 있었으면 서버가 닫는다 (`skippedExploreId`) — 앱은 새 결과로 바꿔 보여 주기만 한다.
  @override
  Future<EncounterResult?> explore() async {
    if (state.encountersLeft <= 0) return null;
    final res = await api.send('POST', '/explores', idempotent: true, body: {'businessDate': _businessDate})
        as Map<String, dynamic>;
    final e = _encounter(res);
    state.applyExplore(
      gold: res['gold'] as int,
      exploreRemaining: res['exploreRemaining'] as int,
      seenSpeciesId: e.catchable ? e.species!.id : null,
    );
    return e;
  }

  /// 챗봇에 들어올 때 오늘 처리하지 않은 등장 (`GET /explores/pending`, 없으면 204).
  @override
  Future<EncounterResult?> pendingEncounter() async {
    final res = await api.get('/explores/pending') as Map<String, dynamic>?;
    if (res == null) return null;
    final e = _encounter(res);
    return e.catchable ? e : null;
  }

  /// 볼 던지기 (`POST /explores/{exploreId}/capture`, 중복 방지 키). 볼 1개를 쓰고 희귀도별 확률로 잡거나 놓친다.
  @override
  Future<CatchResult?> throwBall(EncounterResult encounter) async {
    final id = encounter.exploreId;
    final sp = encounter.species;
    if (id == null || sp == null || state.balls <= 0) return null;
    final res = await api.send('POST', '/explores/$id/capture', idempotent: true, body: {'businessDate': _businessDate})
        as Map<String, dynamic>;
    final m = res['monster'] as Map<String, dynamic>?;
    final caught = m == null
        ? null
        : OwnedMonster(uid: '${m['userMonsterId']}', speciesId: sp.id, inField: m['location'] == 'FIELD');
    state.applyCapture(balls: res['ballCount'] as int, caught: caught);
    return caught == null
        ? CatchResult(kind: CatchKind.escaped, species: sp)
        : CatchResult(kind: CatchKind.newMonster, species: sp, monster: caught, toField: caught.inField);
  }

  /// `POST /explores` · `GET /explores/pending` 응답 → [EncounterResult]. 앱이 모르는 종이면 꽝처럼 보여 준다.
  static EncounterResult _encounter(Map<String, dynamic> res) {
    final sp = res['species'] as Map<String, dynamic>?;
    final species = sp == null ? null : Catalog.species.where((s) => s.id == sp['imageKey']).firstOrNull;
    if (species == null) return EncounterResult(exploreId: '${res['exploreId']}');
    return EncounterResult(
      species: species,
      alreadyOwned: res['result'] == 'DUPLICATE',
      gold: res['goldAwarded'] as int,
      exploreId: '${res['exploreId']}',
      newlySeen: res['newlySeen'] as bool,
      captureRate: (sp!['captureRate'] as num?)?.toDouble(),
    );
  }

  // ---------- 성장 · 교감 (3-5) ----------

  /// 구매 (`POST /shop/purchases`, 중복 방지 키). 가격은 서버가 상점 가격으로 계산하고, 골드가 모자라면 422 `NOT_ENOUGH_GOLD`.
  @override
  Future<bool> buy(ShopItem item, {int count = 1}) async {
    if (count < 1) return false;
    final res = await api.send('POST', '/shop/purchases',
        idempotent: true, body: {'itemCode': Catalog.serverCodeOf(item), 'quantity': count}) as Map<String, dynamic>;
    state.applyPurchase(gold: res['gold'] as int, item: item, quantity: res['quantity'] as int);
    return true;
  }

  /// 물약 먹이기 (`POST /monsters/{id}/feed`, 중복 방지 키). 오른 레벨 수, 물약이 없으면 -1 (서버를 부르지 않음).
  @override
  Future<int> feed(OwnedMonster m, ShopItem potion) async {
    if ((state.inventory[potion.id] ?? 0) <= 0) return -1;
    final res = await api.send('POST', '/monsters/${m.uid}/feed',
        idempotent: true, body: {'itemCode': Catalog.serverCodeOf(potion)}) as Map<String, dynamic>;
    state.applyFeed(m,
        potion: potion,
        expGained: res['expGained'] as int,
        levelAfter: res['levelAfter'] as int,
        remaining: res['remainingQuantity'] as int);
    return (res['levelAfter'] as int) - (res['levelBefore'] as int);
  }

  /// 쓰다듬기 (`POST /monsters/{id}/affection` PET). 오른 호감도.
  @override
  Future<int> pet(OwnedMonster m) => _affection(m, pet: true);

  /// 놀아주기 (`POST /monsters/{id}/affection` PLAY). 오른 호감도.
  @override
  Future<int> play(OwnedMonster m) => _affection(m, pet: false);

  /// 명세대로 중복 방지 키 없음. 오늘 이미 했으면 서버가 409 `ALREADY_DONE_TODAY` — 앱도 "오늘 한 것"으로 표시하고
  /// 오류를 그대로 올려 "오늘은 이미 했어요" 토스트가 뜨게 한다 (실패가 아니라 안내).
  Future<int> _affection(OwnedMonster m, {required bool pet}) async {
    try {
      final res = await api.send('POST', '/monsters/${m.uid}/affection', body: {'action': pet ? 'PET' : 'PLAY'})
          as Map<String, dynamic>;
      state.applyAffection(m, pet: pet, affection: res['affection'] as int);
      return res['gain'] as int;
    } on ApiException catch (e) {
      if (e.code == 'ALREADY_DONE_TODAY') state.applyAffection(m, pet: pet);
      rethrow;
    }
  }

  /// 필드 끌기 호감도(D-20)는 명세 · DB에 없어 **서버 모드에서는 오르지 않는다** (결정 D-46). 끌기 자체는 화면에서 그대로 된다.
  @override
  Future<int> dragMonster(OwnedMonster m) async => 0;

  /// 가방에 넣기 · 꺼내기 (`PATCH /monsters/{id}/location`). 필드 1마리 넣기 · 꽉 찼을 때 꺼내기는 서버를 부르지 않고 false.
  @override
  Future<bool> moveMonster(OwnedMonster m, {required bool toField}) async {
    if (toField && state.fieldMonsters.length >= Economy.fieldCapacity) return false;
    if (!toField && state.fieldMonsters.length <= 1) return false;
    final res = await api.send('PATCH', '/monsters/${m.uid}/location', body: {'location': toField ? 'FIELD' : 'BAG'})
        as Map<String, dynamic>;
    state.applyLocation(m, inField: res['location'] == 'FIELD');
    return true;
  }

  /// 대화 상대 (`PUT /me/partner`). 가방에 있어도 된다.
  @override
  Future<void> setPartner(OwnedMonster m) async {
    final res = await api.send('PUT', '/me/partner', body: {'userMonsterId': int.parse(m.uid)}) as Map<String, dynamic>;
    state.applyPartner('${res['partnerMonsterId']}');
  }

  /// 말 걸기 (`GET /monsters/{id}/line`) — 호감도 단계에 맞는 서버 대사.
  @override
  Future<String?> talk(OwnedMonster m) async {
    final res = await api.get('/monsters/${m.uid}/line') as Map<String, dynamic>;
    return res['line'] as String?;
  }

  // ---------- 아직 앱 안에서 계산 (서버에 저장되지 않음) ----------

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
