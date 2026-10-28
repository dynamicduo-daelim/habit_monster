import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/results.dart';
import '../constants/economy.dart';

/// 앱 전체 게임 상태. 지금은 메모리에만 있고, 나중에 로컬 저장소/백엔드와 연결한다.
class GameState extends ChangeNotifier {
  GameState({
    required this.gold,
    required this.balls,
    required this.monsters,
    required this.habits,
    required this.goals,
    required this.pickedCategories,
    required this.categoryPoints,
    this.encountersLeft = 0,
    this.streakDays = 0,
    this.dayCount = 1,
    math.Random? random,
  }) : _rand = random ?? math.Random();

  final math.Random _rand;

  int gold;
  int balls;
  int encountersLeft;
  int streakDays;
  int dayCount;
  final List<OwnedMonster> monsters;
  final List<Habit> habits;
  final List<Goal> goals;
  final List<String> pickedCategories;
  final Map<String, int> categoryPoints;
  final Map<String, int> inventory = {'s': 3, 'm': 1, 'l': 0};
  String? chatPartnerUid;

  /// 오늘 체크인의 최신 값 (습관 id → 값, O/X는 1/0). 확정 전엔 비어 있다 (임시값은 챗봇에만).
  /// 다시 제출하면 이 값만 바뀐다 (DB `habit_checkin.value`).
  final Map<String, double> todayRecords = {};

  /// 첫 확정 때의 점수 (습관 id → 점수). 보상 기준이라 다시 제출해도 그대로다 (DB `habit_checkin.rewarded_score`).
  final Map<String, int> rewardedScores = {};

  /// 오늘 점수 상위 [Economy.dailyHabitCap]개로 반영된 습관 id (첫 확정 때 정해지고 바뀌지 않는다).
  final Set<String> countedToday = {};

  /// 오늘 체크인을 확정했는지. 확정 뒤에도 기록은 고칠 수 있지만([resubmitCheckin]) 보상은 첫 확정 그대로 (DB v1.5).
  bool checkedInToday = false;

  /// 오늘 출석했는지 = 오늘 앱(홈)에 들어왔는지. 습관 체크인과는 별개다 (2026-10-10, 결정 D-15).
  bool attendedToday = false;

  /// 오늘 체크인한 카테고리 = 오늘 탐색 풀 (DB Q-15 `explore_quota_category`).
  final Set<String> exploreCategoriesToday = {};

  /// 도감에 등록된 종 (`SEEN` + `OWNED`): 탐색에서 한 번이라도 만났거나 가진 종. 몬스터를 내보내도 줄지 않는다.
  /// 잡지 않고 만나기만 해도 들어간다 (2026-10-15, D-17 · API 명세 v5).
  final Set<String> discoveredSpecies = {};

  /// 한 번이라도 가진(잡았거나 스타터로 받은) 종 (DB 도감 기록의 "처음 잡은 시각"이 있는 종 = `OWNED`).
  /// 카테고리 칸 진행(`dexCount`)은 이 수만 센다 (API 명세 v5). [discoveredSpecies]에도 항상 들어 있다.
  final Set<String> caughtSpecies = {};

  /// 서버 데이터를 다 불러왔는지. 서버 모드는 [GameState.empty]로 시작해 `HttpGameRepository.load()`가 채운 뒤 true가 된다
  /// (그 전엔 홈 대신 로딩 화면 — 결정 D-40). 서버 없이 쓰는 샘플 상태는 처음부터 true.
  bool loaded = true;

  /// 서버 모드에서 오늘 체크인할 습관 id (서버 순서, `GET /checkins/today`). 로컬 모드는 null → [activeHabits]를 묻는다.
  /// 제출 후에는 제출에 들어간 습관 (다시 체크 대상 — 기간을 채워 끝난 습관도 들어 있다).
  List<String>? serverCheckinIds;

  /// 서버 모드에서 습관마다 고를 수 있는 값 (서버 `options`, 오름차순). 로컬 모드는 비어 있다.
  final Map<String, List<double>> checkinOptions = {};

  /// 서버가 계산한 오늘의 최신 점수 (제출 · 다시 체크 응답). 없으면 [scoreOf]가 앱 공식으로 계산한다.
  final Map<String, int> serverScores = {};

  /// 서버 모드의 시작 상태: 아무것도 없고 [loaded]가 false. 로그아웃하면 다시 이 상태로 (다른 계정의 데이터가 남지 않게).
  factory GameState.empty({math.Random? random}) {
    final s = GameState(
      random: random,
      gold: 0,
      balls: 0,
      monsters: [],
      habits: [],
      goals: [],
      pickedCategories: [],
      categoryPoints: {},
      dayCount: 0,
    )..loaded = false;
    s.inventory.updateAll((id, count) => 0);
    return s;
  }

  /// 디자인 시안과 같은 샘플 데이터 (DAY 12).
  factory GameState.sample({
    math.Random? random,
    int gold = Economy.startingGold,
    int balls = Economy.startingBalls,
  }) {
    final s = GameState(
      random: random,
      gold: gold,
      balls: balls,
      streakDays: 11,
      dayCount: 12,
      pickedCategories: ['ex', 'st', 'fd'],
      categoryPoints: {'ex': 64, 'st': 38, 'fd': 21, 'md': 0, 'sl': 0, 'mn': 0},
      monsters: [
        OwnedMonster(uid: 'm1', speciesId: 'monkey', level: 7, exp: 60, affection: 4),
        OwnedMonster(uid: 'm2', speciesId: 'mouse', level: 4, exp: 90, affection: 8),
        OwnedMonster(uid: 'm3', speciesId: 'turtle', level: 2, exp: 30, affection: 2),
      ],
      habits: [
        Habit(id: 'h1', name: '아침 러닝', categoryId: 'ex', measureIndex: 0, target: 30, periodIndex: 1),
        Habit(id: 'h2', name: '전공 공부', categoryId: 'st', measureIndex: 0, target: 60, periodIndex: 2),
        Habit(id: 'h3', name: '물 2L 마시기', categoryId: 'fd', measureIndex: 0, target: 2, periodIndex: 0),
      ],
      goals: [
        Goal(id: 'w1', tier: GoalTier.weekly, title: '주 3회 러닝', detail: '월·수·금 아침, 30분 이상', done: true),
        Goal(id: 'w2', tier: GoalTier.weekly, title: '전공 2챕터 끝내기', detail: '자료구조 5–6장, 연습문제까지'),
        Goal(id: 'mo1', tier: GoalTier.monthly, title: '책 2권 완독', detail: '10월 안에 소설 1권 + 에세이 1권'),
      ],
    );
    s.chatPartnerUid = 'm2';
    s.discoveredSpecies.addAll(s.monsters.map((m) => m.speciesId));
    s.caughtSpecies.addAll(s.monsters.map((m) => m.speciesId));
    return s;
  }

  List<OwnedMonster> get fieldMonsters => monsters.where((m) => m.inField).toList();

  CategoryLevel categoryLevel(String categoryId) =>
      CategoryLevel.fromPoints(categoryPoints[categoryId] ?? 0);

  /// 지금 가진 개수 (물약은 가방, 성실볼은 [balls]).
  int ownedCount(ShopItem item) => item.id == Catalog.seongsilBall.id ? balls : (inventory[item.id] ?? 0);

  /// [count]개를 한 번에 산다. 골드가 모자라면 아무것도 안 하고 false.
  bool buy(ShopItem item, {int count = 1}) {
    final total = item.price * count;
    if (count < 1 || gold < total) return false;
    gold -= total;
    if (item.id == Catalog.seongsilBall.id) {
      balls += count;
    } else {
      inventory[item.id] = (inventory[item.id] ?? 0) + count;
    }
    notifyListeners();
    return true;
  }

  // ---------- 카테고리 슬롯 ----------
  /// 도감에 등록된(본) 종 수 (`seenCount`, 가진 종 포함).
  int get discoveredCount => discoveredSpecies.length;

  /// 가진 적 있는 종 수 (`dexCount`). 카테고리 칸은 이 수로 연다.
  int get caughtCount => caughtSpecies.length;

  /// 열 수 있는 카테고리 칸 수: 기본 3, 가진 종 5 · 10 · 15마리마다 +1 (카테고리 수를 넘지 않음).
  int get categorySlotCount =>
      Economy.categorySlots(caughtCount).clamp(0, Catalog.categories.length);

  bool get canOpenCategory => pickedCategories.length < categorySlotCount;

  /// 빈 칸에 새 길을 연다. 그 길의 초기 몬스터도 함께 온다 ([grantStarter]).
  bool openCategory(String id) {
    if (!canOpenCategory || pickedCategories.contains(id)) return false;
    pickedCategories.add(id);
    grantStarter(id);
    notifyListeners();
    return true;
  }

  /// [categoryId] 길의 초기 몬스터를 준다 — 연 카테고리마다 1마리 (DB v1.5 `monster.starter_grant`).
  /// 그 종을 이미 데리고 있으면 그 몬스터를, 아직 그림이 없는 길(명상 · 절약)이면 null을 돌려준다.
  OwnedMonster? grantStarter(String categoryId) {
    final speciesId = Catalog.starters[categoryId];
    if (speciesId == null) return null;
    final own = monsters.where((m) => m.speciesId == speciesId).firstOrNull;
    if (own != null) return own;
    final m = OwnedMonster(
      uid: 'st_$speciesId',
      speciesId: speciesId,
      affection: Economy.starterAffection,
      inField: fieldMonsters.length < Economy.fieldCapacity,
    );
    monsters.add(m);
    discoveredSpecies.add(speciesId);
    caughtSpecies.add(speciesId);
    return m;
  }

  /// 물약을 먹인다. 올라간 레벨 수를 돌려준다 (실패 시 -1).
  int feed(OwnedMonster m, ShopItem item) {
    final have = inventory[item.id] ?? 0;
    if (have <= 0 || m.level >= Economy.finalEvolutionLevel) return -1;
    inventory[item.id] = have - 1;
    final ups = m.addExp(item.exp);
    notifyListeners();
    return ups;
  }

  // ---------- 오늘의 성실도 ----------
  /// 하루 성실도 만점 (습관 3개 × 25 = 75).
  static const int maxDailyScore = Economy.dailyHabitCap * Economy.maxSincerityPerHabit;

  /// 챗봇이 묻는 습관 (활성 습관 전부, 상한 [Economy.maxActiveHabits]).
  List<Habit> get activeHabits => habits.take(Economy.maxActiveHabits).toList();

  /// 오늘 체크인할 습관: 서버 모드면 서버가 정한 대상 ([serverCheckinIds]), 아니면 [activeHabits].
  List<Habit> get checkinHabits {
    final ids = serverCheckinIds;
    if (ids == null) return activeHabits;
    return [
      for (final id in ids)
        if (habits.where((h) => h.id == id).firstOrNull case final h?) h,
    ];
  }

  /// 기록할 값: 서버 선택지가 있으면 [raw]에 가장 가까운 선택지 (같은 거리면 작은 쪽), 없으면 그대로 (결정 D-42).
  /// 직접 입력한 값을 서버가 그대로 받게 되면 이 함수만 `raw`를 돌려주게 바꾸면 된다.
  double recordableValue(Habit h, double raw) {
    final options = checkinOptions[h.id];
    if (options == null || options.isEmpty || raw <= 0) return raw;
    var best = options.first;
    for (final o in options) {
      if ((o - raw).abs() < (best - raw).abs()) best = o;
    }
    return best;
  }

  /// 오늘 성실도에 들어간 습관. 확정 전엔 아직 정해지지 않아 앞에서부터 [Economy.dailyHabitCap]개를 보여준다.
  List<Habit> get countedHabits => checkedInToday
      ? activeHabits.where((h) => countedToday.contains(h.id)).toList()
      : activeHabits.take(Economy.dailyHabitCap).toList();

  Measure measureOf(Habit h) => Catalog.category(h.categoryId).measures[h.measureIndex];

  /// 오늘 기록한 (최신) 값의 성실도. 기록이 없으면 null.
  int? scoreOf(Habit h) {
    final v = todayRecords[h.id];
    if (v == null) return null;
    final server = serverScores[h.id];
    if (server != null) return server;
    return sincerityScore(measure: measureOf(h), target: h.target, value: v);
  }

  /// 보상에 쓰인 점수 = 첫 확정 때의 점수. 그때 답하지 않은 습관은 null.
  int? rewardedScoreOf(Habit h) => rewardedScores[h.id];

  /// 오늘의 성실도 = 반영된 습관의 첫 확정 점수 합 (받은 골드와 같다).
  /// 확정 뒤 습관을 그만둬도 줄지 않게, 습관 목록이 아니라 확정 기록에서 더한다.
  int get todayScore => countedToday.fold(0, (a, id) => a + (rewardedScores[id] ?? 0));
  int get checkedCount => activeHabits.where((h) => todayRecords.containsKey(h.id)).length;

  /// 상단 바 · 출석부의 연속 출석 (오늘 앱에 들어왔으면 +1).
  int get currentStreak => streakDays + (attendedToday ? 1 : 0);

  /// 오늘 출석 처리 (홈에 들어올 때 부른다). 이미 했으면 false — 하루 1번만 센다.
  bool attend() {
    if (attendedToday) return false;
    attendedToday = true;
    notifyListeners();
    return true;
  }

  /// [day]에 출석(앱 접속)했는지. 아직 날짜별 기록이 없어서 지금 이어지는 연속 출석 구간만 안다.
  bool attendedOn(DateTime day, {DateTime? today}) {
    final t = today ?? DateTime.now();
    final ago = DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
    if (ago < 0) return false;
    return ago == 0 ? attendedToday : ago <= streakDays;
  }

  /// 이 습관이 오늘 반영됐는지 (확정 후에만 의미 있음).
  bool isCounted(Habit h) => countedToday.contains(h.id);

  // ---------- 체크인 (서버: POST /checkins) ----------
  /// 오늘 체크인을 한 번에 확정한다 (하루 1번). 이미 확정했으면 null — 기록을 고치려면 [resubmitCheckin].
  /// [answers]: 습관 id → 값. 점수 상위 [Economy.dailyHabitCap]개만 골드 · 카테고리 EXP에 반영하고,
  /// 카테고리 레벨이 오르면 레벨당 보너스를 준다. 확정하면 오늘 탐색 횟수와 탐색 풀(체크인한 카테고리)이 생긴다.
  DailyCheckinResult? confirmCheckin(Map<String, double> answers) {
    if (checkedInToday || answers.isEmpty) return null;
    final order = activeHabits.where((h) => answers.containsKey(h.id)).toList();
    final scored = [
      for (final h in order) (h, answers[h.id]!, sincerityScore(measure: measureOf(h), target: h.target, value: answers[h.id]!)),
    ];
    // 점수 높은 순 (같으면 습관 순서)으로 상위 N개
    final ranked = [...scored]..sort((a, b) => b.$3.compareTo(a.$3));
    final counted = ranked.take(Economy.dailyHabitCap).map((e) => e.$1.id).toSet();

    final before = {for (final c in pickedCategories) c: categoryLevel(c).level};
    var gold = 0;
    for (final (h, _, score) in scored) {
      if (!counted.contains(h.id)) continue;
      categoryPoints[h.categoryId] = (categoryPoints[h.categoryId] ?? 0) + score;
      gold += score * Economy.goldPerSincerity;
    }
    final levelUps = <String, int>{};
    for (final c in before.keys) {
      final ups = categoryLevel(c).level - before[c]!;
      if (ups > 0) {
        levelUps[c] = categoryLevel(c).level;
        gold += ups * Economy.categoryLevelUpGold;
      }
    }
    this.gold += gold;

    todayRecords
      ..clear()
      ..addAll({for (final e in scored) e.$1.id: e.$2});
    rewardedScores
      ..clear()
      ..addAll({for (final e in scored) e.$1.id: e.$3});
    countedToday
      ..clear()
      ..addAll(counted);
    exploreCategoriesToday
      ..clear()
      ..addAll(order.map((h) => h.categoryId));
    checkedInToday = true;
    // 전부 "못 했어"(값 0)로 제출한 날도 탐색은 1번 (API 명세 v4)
    final allMissed = scored.every((e) => e.$2 == 0);
    encountersLeft = allMissed ? Economy.encountersAllMissedDay : Economy.encountersPerDay;
    notifyListeners();
    return DailyCheckinResult(
      scores: [for (final (h, v, sc) in scored) HabitScore(habit: h, value: v, score: sc, counted: counted.contains(h.id))],
      goldEarned: gold,
      levelUps: levelUps,
      exploreCount: encountersLeft,
    );
  }

  /// 확정한 오늘 체크인을 다시 제출한다 (DB v1.5 `checkin_submission`). 아직 확정 전이면 null.
  /// 기록(값 · 점수)만 최신으로 바뀌고, 골드 · 카테고리 EXP · 반영 습관 · 탐색 횟수는 첫 확정 그대로다.
  /// 돌려주는 결과의 `counted`는 첫 확정 때 반영됐는지, `goldEarned`는 항상 0.
  DailyCheckinResult? resubmitCheckin(Map<String, double> answers) {
    if (!checkedInToday || answers.isEmpty) return null;
    final order = activeHabits.where((h) => answers.containsKey(h.id)).toList();
    todayRecords.addAll({for (final h in order) h.id: answers[h.id]!});
    notifyListeners();
    return DailyCheckinResult(
      scores: [
        for (final h in order)
          HabitScore(habit: h, value: answers[h.id]!, score: scoreOf(h)!, counted: countedToday.contains(h.id)),
      ],
      goldEarned: 0,
      levelUps: const {},
      exploreCount: 0,
    );
  }

  // ---------- 탐색 (서버: POST /explore) ----------
  /// 지금 탐색에서 만날 수 있는 종: 오늘 체크인한 (열린) 카테고리이고, 카테고리 레벨이 출현 레벨 이상.
  List<MonsterSpecies> get encounterPool => Catalog.species
      .where((sp) =>
          exploreCategoriesToday.contains(sp.categoryId) &&
          pickedCategories.contains(sp.categoryId) &&
          sp.unlockLevel <= categoryLevel(sp.categoryId).level)
      .toList();

  /// 탐색 1회 (API 명세 v4 `POST /explores`). 남은 횟수가 없으면 null.
  /// [Economy.exploreMissRate] 확률로 꽝 (횟수는 쓴다). 나온 종은 잡지 않아도 도감에 등록된다.
  /// 가진 종이 나오면 볼 없이 바로 [Economy.duplicateMonsterGold]골드, 안 가진 종이면 볼을 던질 수 있다.
  EncounterResult? explore() {
    if (encountersLeft <= 0) return null;
    encountersLeft -= 1;
    final pool = encounterPool;
    notifyListeners();
    if (pool.isEmpty) return const EncounterResult(emptyPool: true);
    if (_rand.nextDouble() < Economy.exploreMissRate) return const EncounterResult();
    final sp = pool[_rand.nextInt(pool.length)];
    final owned = monsters.any((m) => m.speciesId == sp.id);
    final newlySeen = !owned && !discoveredSpecies.contains(sp.id);
    discoveredSpecies.add(sp.id); // 만나기만 해도 도감에 등록 (잡는 건 별개)
    if (owned) gold += Economy.duplicateMonsterGold;
    notifyListeners();
    return EncounterResult(
      species: sp,
      alreadyOwned: owned,
      gold: owned ? Economy.duplicateMonsterGold : 0,
      newlySeen: newlySeen,
    );
  }

  /// 성실볼을 던졌을 때 [sp]가 잡힐 확률 (희귀할수록 낮다).
  double captureRateOf(MonsterSpecies sp) => Economy.captureRate[sp.stars] ?? Economy.captureRate.values.last;

  /// 만난 (안 가진) 몬스터에게 성실볼 1개를 던진다. 볼이 없거나 이미 가진 종이면 null.
  /// [captureRateOf] 확률로 잡히고, 아니면 도망간다.
  CatchResult? throwBall(MonsterSpecies sp) {
    if (balls <= 0 || monsters.any((m) => m.speciesId == sp.id)) return null;
    balls -= 1;
    final CatchResult result;
    if (_rand.nextDouble() >= captureRateOf(sp)) {
      result = CatchResult(kind: CatchKind.escaped, species: sp);
    } else {
      final toField = fieldMonsters.length < Economy.fieldCapacity;
      final m = OwnedMonster(uid: 'n${monsters.length}_${sp.id}', speciesId: sp.id, inField: toField);
      monsters.add(m);
      discoveredSpecies.add(sp.id);
      caughtSpecies.add(sp.id);
      result = CatchResult(kind: CatchKind.newMonster, species: sp, monster: m, toField: toField);
    }
    notifyListeners();
    return result;
  }

  OwnedMonster? monsterByUid(String? uid) => monsters.where((m) => m.uid == uid).firstOrNull;

  // ---------- 교감 ----------
  /// 쓰다듬기 완료 (하루 1회). 실제로 오른 호감도를 돌려준다.
  int pet(OwnedMonster m) {
    final gain = math.min(Economy.petAffectionGain, Economy.maxAffection - m.affection);
    m.affection += gain;
    m.pettedToday = true;
    notifyListeners();
    return gain;
  }

  /// 놀아주기. 오늘 처음이고 호감도가 꽉 차지 않았으면 +1.
  int play(OwnedMonster m) {
    if (m.playedToday || m.affection >= Economy.maxAffection) return 0;
    m.affection += Economy.playAffectionGain;
    m.playedToday = true;
    notifyListeners();
    return Economy.playAffectionGain;
  }

  /// 홈 필드에서 끌어 옮기기. 오늘 처음이고 호감도가 꽉 차지 않았으면 +1 (몬스터마다 하루 1번).
  int drag(OwnedMonster m) {
    if (m.draggedToday || m.affection >= Economy.maxAffection) return 0;
    m.affection += Economy.dragAffectionGain;
    m.draggedToday = true;
    notifyListeners();
    return Economy.dragAffectionGain;
  }

  bool moveMonster(OwnedMonster m, {required bool toField}) {
    if (toField && fieldMonsters.length >= Economy.fieldCapacity) return false;
    if (!toField && fieldMonsters.length <= 1) return false;
    m.inField = toField;
    notifyListeners();
    return true;
  }

  // ---------- 습관 추가 · 그만두기 (서버: POST · DELETE /habits) ----------
  int _habitSeq = 0;

  /// 습관을 더 넣을 수 있는지 (최대 [Economy.maxActiveHabits]개).
  bool get canAddHabit => habits.length < Economy.maxActiveHabits;

  /// 습관을 그만둘 수 있는지 (마지막 1개는 남긴다 — 체크할 습관이 없으면 앱의 흐름이 끊긴다).
  bool get canRemoveHabit => habits.length > 1;

  /// 새 습관을 등록한다. 꽉 찼거나, 열지 않은 카테고리거나, 이름 · 목표가 비었으면 null.
  /// 오늘 이미 체크인을 확정했다면 이 습관은 내일부터 보상에 반영된다 (보상은 첫 확정 기준).
  Habit? addHabit({
    required String name,
    required String categoryId,
    required int measureIndex,
    required double target,
    required int periodIndex,
  }) {
    final trimmed = name.trim();
    if (!canAddHabit || trimmed.isEmpty || target <= 0 || !pickedCategories.contains(categoryId)) return null;
    final h = Habit(
      id: 'nh${_habitSeq++}',
      name: trimmed,
      categoryId: categoryId,
      measureIndex: measureIndex,
      target: target,
      periodIndex: periodIndex,
    );
    habits.add(h);
    notifyListeners();
    return h;
  }

  /// 습관을 그만둔다. 이미 받은 골드 · 카테고리 경험치 · 오늘의 성실도는 그대로 둔다. 마지막 1개면 false.
  bool removeHabit(Habit h) {
    if (!canRemoveHabit || !habits.remove(h)) return false;
    todayRecords.remove(h.id);
    notifyListeners();
    return true;
  }

  // ---------- 목표 ----------
  /// 유료로 연 주간 목표 슬롯 (기록용, 골드 보상 없음). 결제가 없어 화면에서는 열 수 없다 (D-48 — 누르면 "결제가 필요해요" 창).
  bool extraWeeklySlot = false;
  int _goalSeq = 0;

  List<Goal> goalsOf(GoalTier tier) => goals.where((g) => g.tier == tier).toList();

  int capOf(GoalTier tier) => tier == GoalTier.weekly
      ? Economy.weeklyGoalSlots + (extraWeeklySlot ? 1 : 0)
      : Economy.monthlyGoalSlots;

  /// 목표 달성 → 보상 골드. 완료한 목표는 되돌릴 수 없다 (DB Q-5). 이미 완료면 false.
  bool toggleGoal(Goal g) {
    if (g.done) return false;
    g.done = true;
    gold += g.reward;
    notifyListeners();
    return true;
  }

  /// 새 목표. 무료 칸을 다 쓴 뒤의 주간 목표는 유료 슬롯(보상 없음)으로 들어간다.
  Goal addGoal(GoalTier tier, String title, String detail) {
    final paid = tier == GoalTier.weekly && goalsOf(tier).length >= Economy.weeklyGoalSlots;
    final g = Goal(id: 'g${_goalSeq++}', tier: tier, title: title, detail: detail, paidSlot: paid);
    goals.add(g);
    notifyListeners();
    return g;
  }

  void updateGoal(Goal g, String title, String detail) {
    g
      ..title = title
      ..detail = detail;
    notifyListeners();
  }

  /// 진행 중인 목표를 지운다. 완료한 목표는 지울 수 없다 (DB Q-5). 못 지우면 false.
  bool deleteGoal(Goal g) {
    if (g.done) return false;
    goals.remove(g);
    notifyListeners();
    return true;
  }

  void unlockExtraWeeklySlot() {
    extraWeeklySlot = true;
    notifyListeners();
  }

  /// 온보딩 1~3단계 결과를 반영한다 (시안의 `enterApp`).
  /// 길을 안 골랐거나 습관이 없으면 기존(샘플) 값을 그대로 둔다.
  void completeOnboarding({
    required List<String> picked,
    required List<Habit> habits,
    required List<Goal> goals,
    String? starterCategory,
  }) {
    if (picked.isNotEmpty) {
      pickedCategories
        ..clear()
        ..addAll(picked);
    } else if (pickedCategories.isEmpty) {
      pickedCategories.addAll(Catalog.defaultCategories);
    }
    if (habits.isNotEmpty) {
      this.habits
        ..clear()
        ..addAll(habits);
    }
    this.goals
      ..clear()
      ..addAll(goals);

    // 고르지 않은 길의 몬스터는 데리고 시작하지 않는다.
    monsters.removeWhere((m) => !pickedCategories.contains(Catalog.speciesById(m.speciesId).categoryId));
    discoveredSpecies
      ..clear()
      ..addAll(monsters.map((m) => m.speciesId));
    caughtSpecies
      ..clear()
      ..addAll(monsters.map((m) => m.speciesId));

    // 고른 길마다 초기 몬스터 1마리. 대화 상대는 고른 첫 파트너, 안 골랐으면 원래 상대나 첫 몬스터.
    for (final c in pickedCategories) {
      final m = grantStarter(c);
      if (m != null && c == starterCategory) chatPartnerUid = m.uid;
    }
    if (monsterByUid(chatPartnerUid) == null) chatPartnerUid = monsters.firstOrNull?.uid;
    notifyListeners();
  }

  void touch() => notifyListeners();

  // ---------- 서버 응답 반영 (HttpGameRepository만 부른다) ----------
  // 규칙(점수 · 보상 계산)은 서버가 하고, 여기선 받은 값을 그대로 옮긴다. 다 옮긴 뒤 [markLoaded]가 한 번에 다시 그린다.

  /// `GET /me/status`: 상단 바 값. 연속 출석은 [applyAttendance]가 오늘 출석까지 반영한다.
  void applyStatus({
    required int gold,
    required int balls,
    required int currentStreak,
    required bool checkedInToday,
    required int exploreRemaining,
    required int dayCount,
  }) {
    this.gold = gold;
    this.balls = balls;
    streakDays = currentStreak;
    attendedToday = false;
    this.checkedInToday = checkedInToday;
    encountersLeft = exploreRemaining;
    this.dayCount = dayCount;
  }

  /// `POST /me/attendance` 응답. 서버의 연속 일수는 오늘을 포함하므로 [currentStreak] = 어제까지 + 오늘 1.
  void applyAttendance({required int currentStreak}) {
    attendedToday = true;
    streakDays = math.max(0, currentStreak - 1);
    notifyListeners();
  }

  /// `GET /categories`의 연 카테고리 (카테고리 순서).
  void applyCategories(List<String> opened) {
    pickedCategories
      ..clear()
      ..addAll(opened);
  }

  /// `GET /monsters` + 마리마다 `GET /monsters/{id}`. 가진 종은 도감에도 (본 종 · 탐색 기록은 3-4단계).
  void applyMonsters(List<OwnedMonster> list, {String? partnerUid}) {
    monsters
      ..clear()
      ..addAll(list);
    chatPartnerUid = partnerUid ?? monsters.firstOrNull?.uid;
    caughtSpecies.addAll(list.map((m) => m.speciesId));
    discoveredSpecies.addAll(list.map((m) => m.speciesId));
  }

  /// `GET /habits` (진행 중 + 기간을 채운 습관).
  void applyHabits(List<Habit> list) {
    habits
      ..clear()
      ..addAll(list);
  }

  /// `GET /goals` (기간이 남은 목표).
  void applyGoals(List<Goal> list) {
    goals
      ..clear()
      ..addAll(list);
  }

  /// `POST /goals` 응답.
  void applyGoalAdded(Goal g) {
    goals.add(g);
    notifyListeners();
  }

  /// `PATCH /goals/{id}` 응답.
  void applyGoalUpdated(Goal g, {required String title, required String detail}) {
    g
      ..title = title
      ..detail = detail;
    notifyListeners();
  }

  /// `DELETE /goals/{id}`.
  void applyGoalDeleted(Goal g) {
    goals.remove(g);
    notifyListeners();
  }

  /// `POST /goals/{id}/complete` 응답: 완료 표시 + 받은 뒤 잔액(서버 값).
  void applyGoalCompleted(Goal g, {required int gold}) {
    g.done = true;
    this.gold = gold;
    notifyListeners();
  }

  /// `GET /inventory`의 물약 (앱 아이템 id → 개수). 없는 물약은 0.
  void applyPotions(Map<String, int> counts) {
    inventory.updateAll((id, _) => counts[id] ?? 0);
  }

  /// `GET /me/today`가 체크인 후일 때: 습관 id → 보상 기준 값 · 점수, 반영된 습관.
  /// 기록 값은 첫 제출 값이다 (다시 체크한 최신 값은 3-3단계의 `GET /checkins/today`에서).
  void applyToday({required Map<String, double> values, required Map<String, int> scores, required Set<String> counted}) {
    todayRecords
      ..clear()
      ..addAll(values);
    rewardedScores
      ..clear()
      ..addAll(scores);
    countedToday
      ..clear()
      ..addAll(counted);
  }

  /// `GET /checkins/today`: 오늘 체크인 대상 · 선택지. 제출 후면 [latest]에 다시 체크까지 반영한 최신 값.
  void applyCheckinBoard({
    required List<String> ids,
    required Map<String, List<double>> options,
    required Map<String, double> latest,
  }) {
    serverCheckinIds = ids;
    checkinOptions
      ..clear()
      ..addAll(options);
    serverScores.clear();
    todayRecords.addAll(latest);
  }

  /// `POST /checkins/today` 응답: 보상은 서버가 계산한 값 그대로. 탐색 후보는 연 카테고리 전부 (결정 B4).
  /// [categoryExp]: 카테고리 → 서버의 누적 경험치 (앱 [CategoryLevel.fromPoints]와 같은 공식이라 그대로 넣는다).
  void applyCheckinResult({
    required int gold,
    required Map<String, double> values,
    required Map<String, int> scores,
    required Set<String> counted,
    required int exploreTotal,
    required Map<String, int> categoryExp,
  }) {
    this.gold = gold;
    todayRecords
      ..clear()
      ..addAll(values);
    rewardedScores
      ..clear()
      ..addAll(scores);
    serverScores
      ..clear()
      ..addAll(scores);
    countedToday
      ..clear()
      ..addAll(counted);
    categoryPoints.addAll(categoryExp);
    exploreCategoriesToday
      ..clear()
      ..addAll(pickedCategories);
    encountersLeft = exploreTotal;
    checkedInToday = true;
    notifyListeners();
  }

  /// `POST /explores` 응답: 골드 · 남은 횟수, 안 가진 종이 나왔으면 도감에 "본 종"으로.
  /// 본 종은 지금 서버에서 다시 불러오지 않는다 (도감 API는 4단계) — 앱을 다시 켜면 가진 종만 남는다.
  void applyExplore({required int gold, required int exploreRemaining, String? seenSpeciesId}) {
    this.gold = gold;
    encountersLeft = exploreRemaining;
    if (seenSpeciesId != null) discoveredSpecies.add(seenSpeciesId);
    notifyListeners();
  }

  /// `POST /explores/{id}/capture` 응답: 남은 볼, 잡았으면 새 몬스터 (도감 = 가진 종).
  void applyCapture({required int balls, OwnedMonster? caught}) {
    this.balls = balls;
    if (caught != null) {
      monsters.add(caught);
      discoveredSpecies.add(caught.speciesId);
      caughtSpecies.add(caught.speciesId);
    }
    notifyListeners();
  }

  /// `POST /shop/purchases` 응답: 골드 · 산 뒤 가방 개수 (성실볼은 [balls]).
  void applyPurchase({required int gold, required ShopItem item, required int quantity}) {
    this.gold = gold;
    if (item.id == Catalog.seongsilBall.id) {
      balls = quantity;
    } else {
      inventory[item.id] = quantity;
    }
    notifyListeners();
  }

  /// `POST /monsters/{id}/feed` 응답: 경험치를 앱 공식으로 더한 뒤 레벨은 서버 값으로 맞춘다 (둘 다 레벨당 125).
  void applyFeed(OwnedMonster m, {required ShopItem potion, required int expGained, required int levelAfter, required int remaining}) {
    m.addExp(expGained);
    m.level = levelAfter;
    inventory[potion.id] = remaining;
    notifyListeners();
  }

  /// `POST /monsters/{id}/affection` 응답 (또는 409 "오늘 이미" — [affection] 없이 오늘 한 것만 표시).
  void applyAffection(OwnedMonster m, {required bool pet, int? affection}) {
    if (affection != null) m.affection = affection;
    if (pet) {
      m.pettedToday = true;
    } else {
      m.playedToday = true;
    }
    notifyListeners();
  }

  /// `PATCH /monsters/{id}/location` · `PUT /me/partner` 응답.
  void applyLocation(OwnedMonster m, {required bool inField}) {
    m.inField = inField;
    notifyListeners();
  }

  void applyPartner(String uid) {
    chatPartnerUid = uid;
    notifyListeners();
  }

  /// `PUT /checkins/today` 응답: 최신 값 · 점수만 (보상은 첫 제출 그대로).
  void applyRecheck({required Map<String, double> values, required Map<String, int> scores}) {
    todayRecords.addAll(values);
    serverScores.addAll(scores);
    notifyListeners();
  }

  void markLoaded() {
    loaded = true;
    notifyListeners();
  }
}

/// 위젯 트리 어디서든 `GameScope.of(context)`로 상태를 꺼내 쓰고, 바뀌면 다시 그린다.
class GameScope extends InheritedNotifier<GameState> {
  const GameScope({super.key, required GameState super.notifier, required super.child});

  static GameState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GameScope>();
    assert(scope != null, 'GameScope가 위젯 트리에 없습니다.');
    return scope!.notifier!;
  }

  /// 다시 그리기 구독 없이 읽기만 할 때 (타이머 · 버튼 콜백 안에서).
  static GameState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<GameScope>();
    assert(scope != null, 'GameScope가 위젯 트리에 없습니다.');
    return scope!.notifier!;
  }
}
