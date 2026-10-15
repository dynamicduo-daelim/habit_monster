import 'package:flutter/widgets.dart';

import '../../data/models.dart';
import '../../data/results.dart';

/// 화면이 게임 상태를 **바꿀 때** 쓰는 유일한 길. 읽기는 지금처럼 [GameState]에서 한다.
///
/// 화면은 이 인터페이스만 알고, 뒤에서 누가 계산하는지는 모른다:
/// - [LocalGameRepository] — 서버 없이 앱 안에서 계산 (지금 · 시연용). 규칙은 [GameState]에 있다.
/// - `HttpGameRepository` — 서버 API를 부르고 응답을 [GameState]에 반영 (3단계부터 API마다 붙인다).
///
/// 전부 `Future`인 이유: 서버를 부르면 기다려야 하고, 실패할 수 있다 (실패는 `ApiException`).
/// 결과 객체(`DailyCheckinResult` 등)는 API 응답과 같은 모양이라 두 구현이 같은 값을 돌려준다.
/// 서버 경로는 API 명세 v5 기준 (`docs/진행현황-및-계획.md`).
abstract class GameRepository {
  /// 처음 · 날짜가 바뀌었을 때 오늘 데이터를 다시 불러온다 (서버: `GET /me/status` 등).
  Future<void> load();

  // ---------- 온보딩 (POST /onboarding) ----------
  Future<void> completeOnboarding({
    required List<String> picked,
    required List<Habit> habits,
    required List<Goal> goals,
    String? starterCategory,
  });

  // ---------- 상점 (POST /shop/purchases) ----------
  /// [count]개를 산다. 골드가 모자라면 false.
  Future<bool> buy(ShopItem item, {int count = 1});

  // ---------- 체크인 (POST · PUT /checkins/today) ----------
  /// 오늘 첫 제출. 이미 냈으면 null.
  Future<DailyCheckinResult?> confirmCheckin(Map<String, double> answers);

  /// 다시 체크 (기록만 바뀌고 보상은 그대로). 아직 안 냈으면 null.
  Future<DailyCheckinResult?> resubmitCheckin(Map<String, double> answers);

  // ---------- 탐색 · 포획 (POST /explores · /explores/{id}/capture) ----------
  /// 탐색 1회. 남은 횟수가 없으면 null.
  Future<EncounterResult?> explore();

  /// 나타난 몬스터에게 성실볼 1개. 볼이 없으면 null.
  Future<CatchResult?> throwBall(MonsterSpecies species);

  // ---------- 몬스터 (POST /monsters/{id}/… · PATCH location · PUT /me/partner) ----------
  /// 쓰다듬기 (하루 1회). 오른 호감도.
  Future<int> pet(OwnedMonster m);

  /// 놀아주기 (하루 1회). 오른 호감도.
  Future<int> play(OwnedMonster m);

  /// 물약 먹이기. 오른 레벨 수, 못 먹이면 -1.
  Future<int> feed(OwnedMonster m, ShopItem potion);

  /// 필드 ↔ 가방. 칸 제한에 걸리면 false.
  Future<bool> moveMonster(OwnedMonster m, {required bool toField});

  /// 챗봇 대화 상대 바꾸기.
  Future<void> setPartner(OwnedMonster m);

  // ---------- 도감 · 카테고리 (POST /categories/{code}/unlock) ----------
  Future<bool> openCategory(String categoryId);

  // ---------- 습관 (POST /habits · /habits/{id}/stop) ----------
  Future<Habit?> addHabit({
    required String name,
    required String categoryId,
    required int measureIndex,
    required double target,
    required int periodIndex,
  });

  Future<bool> removeHabit(Habit h);

  // ---------- 목표 (/goals) ----------
  Future<Goal> addGoal(GoalTier tier, String title, String detail);
  Future<void> updateGoal(Goal g, String title, String detail);
  Future<bool> deleteGoal(Goal g);

  /// 목표 완료 → 보상. 이미 완료면 false.
  Future<bool> completeGoal(Goal g);

  /// 유료 주간 목표 칸 (결제는 MVP 밖 — 지금은 앱 안에서만).
  Future<void> unlockExtraWeeklySlot();
}

/// 위젯 트리 어디서든 `GameRepositoryScope.of(context)`로 꺼내 쓴다.
class GameRepositoryScope extends InheritedWidget {
  const GameRepositoryScope({super.key, required this.repository, required super.child});

  final GameRepository repository;

  static GameRepository of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<GameRepositoryScope>();
    assert(scope != null, 'GameRepositoryScope가 위젯 트리에 없습니다.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(GameRepositoryScope oldWidget) => repository != oldWidget.repository;
}
