import 'models.dart';

/// 습관 하나의 오늘 기록 (DB `habit.habit_checkin`).
class HabitScore {
  const HabitScore({required this.habit, required this.value, required this.score, required this.counted});
  final Habit habit;

  /// 기록한 값 ("못 했어" = 0, O/X는 1 · 0).
  final double value;
  final int score;

  /// 점수 상위 [Economy.dailyHabitCap]개에 들어 골드 · 카테고리 EXP에 반영됐는지.
  final bool counted;
}

/// 하루 1번 일괄 확정한 체크인 결과. 백엔드 `POST /checkins` 응답과 같은 모양 (DB `habit.daily_checkin`).
/// 지금은 [GameState.confirmCheckin]이 로컬에서 계산하고, 서버를 붙이면 응답을 이 객체로 바꾸면 된다.
class DailyCheckinResult {
  const DailyCheckinResult({
    required this.scores,
    required this.goldEarned,
    required this.levelUps,
    required this.exploreCount,
  });

  final List<HabitScore> scores;

  /// 받은 골드 (반영 점수 + 카테고리 레벨업 보너스).
  final int goldEarned;

  /// 레벨이 오른 카테고리 → 오른 뒤 레벨.
  final Map<String, int> levelUps;

  /// 오늘 받은 탐색 횟수.
  final int exploreCount;

  int get totalScore => scores.fold(0, (a, s) => a + s.score);
  int get countedScore => scores.where((s) => s.counted).fold(0, (a, s) => a + s.score);
}

/// 탐색 1회 결과: 몬스터를 만났는지. 백엔드 `POST /explore` 응답과 같은 모양.
/// 아직 잡은 게 아니다. 잡기는 [GameState.throwBall] → [CatchResult].
class EncounterResult {
  const EncounterResult({this.species, this.alreadyOwned = false, this.emptyPool = false});

  /// 만난 몬스터 종 (아무도 없었으면 null).
  final MonsterSpecies? species;

  /// 이미 가진 종인지 (잡으면 골드로 바뀐다).
  final bool alreadyOwned;

  /// 아무도 없었던 이유가 "오늘 체크인한 길에 만날 몬스터가 아예 없어서"인지 (아니면 이번에만 안 나온 것).
  final bool emptyPool;

  bool get found => species != null;
}

/// 성실볼 던지기 결과: 잡음(새 몬스터) · 잡음(중복 → 골드) · 놓침(도망).
enum CatchKind { newMonster, duplicate, escaped }

/// 성실볼 1개를 던진 결과. 백엔드 `POST /explore/throw` 응답과 같은 모양.
class CatchResult {
  const CatchResult({required this.kind, required this.species, this.monster, this.toField = false, this.gold = 0});

  final CatchKind kind;
  final MonsterSpecies species;

  /// 새로 얻은 몬스터 ([CatchKind.newMonster]일 때).
  final OwnedMonster? monster;

  /// 새 몬스터가 필드로 나왔는지 (꽉 찼으면 가방).
  final bool toField;

  /// 중복으로 받은 골드.
  final int gold;

  bool get caught => kind != CatchKind.escaped;
}
