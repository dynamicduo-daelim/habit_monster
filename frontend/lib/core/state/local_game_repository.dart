import '../../data/models.dart';
import '../../data/results.dart';
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

  @override
  Future<Goal> addGoal(GoalTier tier, String title, String detail) async => state.addGoal(tier, title, detail);

  @override
  Future<void> updateGoal(Goal g, String title, String detail) async => state.updateGoal(g, title, detail);

  @override
  Future<bool> deleteGoal(Goal g) async => state.deleteGoal(g);

  @override
  Future<bool> completeGoal(Goal g) async => state.toggleGoal(g);
}
