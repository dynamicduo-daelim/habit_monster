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
    this.periodBonusGold = 0,
  });

  final List<HabitScore> scores;

  /// 받은 골드 (반영 점수 + 카테고리 레벨업 보너스).
  final int goldEarned;

  /// 레벨이 오른 카테고리 → 오른 뒤 레벨.
  final Map<String, int> levelUps;

  /// 오늘 받은 탐색 횟수.
  final int exploreCount;

  /// [goldEarned] 중 습관 기간을 채워 받은 보너스 (서버 `goldBreakdown.periodBonus`). 로컬 모드는 0.
  final int periodBonusGold;

  int get totalScore => scores.fold(0, (a, s) => a + s.score);
  int get countedScore => scores.where((s) => s.counted).fold(0, (a, s) => a + s.score);
}

/// 탐색 1회 결과. 백엔드 `POST /explores` 응답과 같은 모양 (API 명세 v5):
/// 꽝(`MISS`, species 없음) · 가진 종(`DUPLICATE`, 볼 없이 바로 골드) · 안 가진 종(`ENCOUNTER`, 볼을 던질 수 있음).
/// 안 가진 종은 아직 잡은 게 아니다. 잡기는 [GameState.throwBall] → [CatchResult].
class EncounterResult {
  const EncounterResult({
    this.species,
    this.alreadyOwned = false,
    this.emptyPool = false,
    this.gold = 0,
    this.exploreId,
    this.newlySeen = false,
    this.captureRate,
  });

  /// 만난 몬스터 종 (아무도 없었으면 null).
  final MonsterSpecies? species;

  /// 이미 가진 종인지 (`DUPLICATE`: 볼을 던지지 않고 [gold]를 바로 받는다).
  final bool alreadyOwned;

  /// 가진 종이 나와서 바로 받은 골드 (`goldAwarded`).
  final int gold;

  /// 아무도 없었던 이유가 "오늘 체크인한 길에 만날 몬스터가 아예 없어서"인지 (아니면 이번에만 안 나온 것).
  final bool emptyPool;

  /// 서버의 탐색 번호 (`exploreId`) — 볼을 던질 때 이 번호로 부른다. 로컬 모드는 null.
  final String? exploreId;

  /// 처음 만난 종이라 이번에 도감에 새로 등록됐는지 (`newlySeen`, "도감 등록!" 연출).
  final bool newlySeen;

  /// 서버가 알려 준 포획률 (`captureRate`, 0 ~ 1). 로컬 모드는 null → [GameState.captureRateOf].
  final double? captureRate;

  bool get found => species != null;

  /// 볼을 던질 수 있는 등장인지 (안 가진 종).
  bool get catchable => found && !alreadyOwned;
}

/// 성실볼 던지기 결과: 잡음(`CAPTURED`) · 놓침(`ESCAPED`, 도망가고 그 등장은 끝).
enum CatchKind { newMonster, escaped }

/// 성실볼 1개를 던진 결과. 백엔드 `POST /explores/{id}/capture` 응답과 같은 모양.
class CatchResult {
  const CatchResult({required this.kind, required this.species, this.monster, this.toField = false});

  final CatchKind kind;
  final MonsterSpecies species;

  /// 새로 얻은 몬스터 ([CatchKind.newMonster]일 때).
  final OwnedMonster? monster;

  /// 새 몬스터가 필드로 나왔는지 (꽉 찼으면 가방).
  final bool toField;

  bool get caught => kind == CatchKind.newMonster;
}
