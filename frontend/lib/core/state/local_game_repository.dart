import '../../data/models.dart';
import '../../data/results.dart';
import '../constants/economy.dart';
import 'game_repository.dart';
import 'game_state.dart';

/// 서버 없이 앱 안에서 계산하는 [GameRepository]. 규칙은 전부 [GameState]의 메서드에 있다 (그 테스트도 그대로).
/// `API_BASE_URL` 없이 빌드했을 때(시연 · 화면 개발)와 테스트에서 쓴다.
class LocalGameRepository implements GameRepository {
  LocalGameRepository(this.state);

  final GameState state;

  @override
  Future<void> load() async {}

  @override
  Future<bool> attend() async => state.attend();

  @override
  Future<void> completeOnboarding({
    required List<String> picked,
    required List<Habit> habits,
    required List<Goal> goals,
    String? starterCategory,
  }) async =>
      state.completeOnboarding(picked: picked, habits: habits, goals: goals, starterCategory: starterCategory);

  @override
  Future<bool> buy(ShopItem item, {int count = 1}) async => state.buy(item, count: count);

  @override
  Future<DailyCheckinResult?> confirmCheckin(Map<String, double> answers) async => state.confirmCheckin(answers);

  @override
  Future<DailyCheckinResult?> resubmitCheckin(Map<String, double> answers) async => state.resubmitCheckin(answers);

  @override
  Future<EncounterResult?> explore() async => state.explore();

  @override
  Future<EncounterResult?> pendingEncounter() async => null;

  @override
  Future<CatchResult?> throwBall(EncounterResult encounter) async => state.throwBall(encounter.species!);

  @override
  Future<int> pet(OwnedMonster m) async => state.pet(m);

  @override
  Future<int> play(OwnedMonster m) async => state.play(m);

  @override
  Future<int> feed(OwnedMonster m, ShopItem potion) async => state.feed(m, potion);

  @override
  Future<int> dragMonster(OwnedMonster m) async => state.drag(m);

  @override
  Future<bool> moveMonster(OwnedMonster m, {required bool toField}) async => state.moveMonster(m, toField: toField);

  @override
  Future<void> setPartner(OwnedMonster m) async {
    state.chatPartnerUid = m.uid;
    state.touch();
  }

  @override
  Future<String?> talk(OwnedMonster m) async => null;

  @override
  Future<bool> openCategory(String categoryId) async => state.openCategory(categoryId);

  @override
  Future<Habit?> addHabit({
    required String name,
    required String categoryId,
    required int measureIndex,
    required double target,
    required int periodIndex,
  }) async =>
      state.addHabit(
        name: name,
        categoryId: categoryId,
        measureIndex: measureIndex,
        target: target,
        periodIndex: periodIndex,
      );

  @override
  Future<bool> removeHabit(Habit h) async => state.removeHabit(h);

  /// 시연 모드 통계: 연속 출석 · 카테고리 레벨은 앱 값, 지난 6일 성실도는 시안의 샘플 값 (기록이 없어서).
  /// 시연 모드에는 AI가 없다 (키는 서버에만 — D-57).
  @override
  Future<InterpretResult?> interpret({
    required String message,
    required List<(String, String)> history,
    required Map<String, double> draft,
    String? askingHabitId,
  }) async =>
      null;

  @override
  Future<StatsData> loadStats() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayRate = state.countedToday.isEmpty
        ? null
        : (state.countedToday.map((id) => ((state.rewardedScores[id] ?? 0) / Economy.targetHitScore).clamp(0, 1) * 100)
                    .reduce((a, b) => a + b) /
                state.countedToday.length)
            .round();
    final rates = <int?>[..._sampleRates, todayRate];
    final week = [
      for (var i = 0; i < 7; i++) (weekdayLabel(today.subtract(Duration(days: 6 - i))), rates[i]),
    ];
    final done = rates.whereType<int>().toList();
    return StatsData(
      currentStreak: state.currentStreak,
      longestStreak: state.currentStreak,
      last14Days: [for (var i = 13; i >= 0; i--) state.attendedOn(today.subtract(Duration(days: i)), today: today)],
      last7Days: week,
      averageRate: done.isEmpty ? null : (done.reduce((a, b) => a + b) / done.length).round(),
      categories: {for (final c in state.pickedCategories) c: state.categoryLevel(c)},
    );
  }

  /// 시안의 지난 6일 점수(42 · 55 · 30 · 61 · 48 · 52 / 75)를 달성률 %로.
  static const _sampleRates = [56, 73, 40, 81, 64, 69];

  @override
  Future<Goal> addGoal(GoalTier tier, String title, String detail) async => state.addGoal(tier, title, detail);

  @override
  Future<void> updateGoal(Goal g, String title, String detail) async => state.updateGoal(g, title, detail);

  @override
  Future<bool> deleteGoal(Goal g) async => state.deleteGoal(g);

  @override
  Future<bool> completeGoal(Goal g) async => state.toggleGoal(g);
}
