import 'package:flutter/foundation.dart';

import '../../core/utils/format.dart';
import '../../data/models.dart';
import '../../data/results.dart';

/// 챗봇이 "무슨 말을 할지"만 정한다. 게임 규칙(성실도 · 골드 · 레벨)은 [GameState]가 맡는다.
///
/// 지금은 [ScriptedChatBrain](시안 대본)을 쓰고, 나중에 AI를 붙이면 이 인터페이스를 구현한
/// `AiChatBrain`을 만들어 [ChatController]에 넘기면 된다. 모든 메서드가 Future라서 서버 호출을 그대로 넣을 수 있다.
abstract class ChatBrain {
  /// 대화를 시작할 때 첫인사. 아직 함께하는 몬스터가 없으면 [partner]는 null.
  Future<String> greet(MonsterSpecies? partner);

  /// 습관 하나를 했는지 묻기.
  Future<String> askHabit(Habit habit, HabitCategory category);

  /// "했어!" 다음에 얼마나 했는지 묻기 (O/X가 아닌 습관).
  Future<String> askAmount(Habit habit, Measure measure);

  /// 답 하나에 대한 반응. [score]는 미리 계산한 점수 (보상은 마지막 확정 때 정해진다).
  Future<String> react(Habit habit, int score);

  /// 오늘 체크를 확정했을 때 (점수 상위 3개 반영 결과).
  Future<String> wrapUp(DailyCheckinResult result, {required int maxScore});

  /// 오늘 이미 체크를 확정한 뒤 대화를 다시 열었을 때.
  Future<String> alreadyCheckedIn();

  /// 확정한 오늘 기록을 고치려고 "다시 체크"를 눌렀을 때 (이어서 습관을 처음부터 다시 묻는다).
  Future<String> recheckIntro();

  /// 다시 체크한 기록을 저장했을 때. 보상은 첫 확정 그대로다.
  Future<String> recheckDone(DailyCheckinResult result);

  /// 탐색에서 몬스터를 잡았을 때 대화창에 남길 말 (잡았을 때만 불린다).
  Future<String> catchReport(CatchResult result);
}

/// 시안(prototype-source.dc.html)의 대사를 그대로 쓰는 대본형 챗봇.
class ScriptedChatBrain implements ChatBrain {
  const ScriptedChatBrain();

  @override
  Future<String> greet(MonsterSpecies? partner) => SynchronousFuture(partner == null
      ? '안녕! 오늘 습관 체크하러 왔어. 탐색에서 첫 친구도 만나보자.'
      : '안녕! 나 ${partner.name}. 오늘 습관 체크하러 왔어.');

  @override
  Future<String> askHabit(Habit habit, HabitCategory category) =>
      SynchronousFuture("[${category.name}] '${habit.name}' 오늘 했어?");

  @override
  Future<String> askAmount(Habit habit, Measure measure) => SynchronousFuture(
      '좋아! ${measure.label}은 얼마나 했어? 목표는 ${formatNum(habit.target)}${measure.unit}이야.');

  @override
  Future<String> react(Habit habit, int score) {
    if (score == 0) return SynchronousFuture('괜찮아, 내일 같이 해보자. 기록해 둘게.');
    return SynchronousFuture(score >= 20 ? '최고야! 오늘 해냈구나.' : '좋아, 조금이라도 한 게 중요해.');
  }

  @override
  Future<String> wrapUp(DailyCheckinResult r, {required int maxScore}) {
    final skipped = r.scores.where((s) => !s.counted).map((s) => s.habit.name).toList();
    final skippedText = skipped.isEmpty
        ? ''
        : " (점수가 높은 3개만 반영돼서 ${skipped.map((n) => "'$n'").join(', ')}${josaEunNeun(skipped.last)} 이번엔 빠졌어)";
    return SynchronousFuture('오늘 체크 끝! 오늘의 성실도는 ${r.countedScore}/$maxScore야.$skippedText'
        ' 탐색 ${r.exploreCount}번 할 수 있어. 같이 갈래?');
  }

  @override
  Future<String> alreadyCheckedIn() => SynchronousFuture('오늘 체크는 이미 끝났어! 탐색하러 갈래?');

  @override
  Future<String> recheckIntro() =>
      SynchronousFuture('잘못 적은 게 있었어? 처음부터 다시 물어볼게. 골드랑 탐색 횟수는 처음 확정한 그대로야.');

  @override
  Future<String> recheckDone(DailyCheckinResult r) =>
      SynchronousFuture('기록을 고쳐 뒀어! 보상은 처음 확정한 그대로야.');

  @override
  Future<String> catchReport(CatchResult r) {
    final name = r.species.name;
    if (r.kind == CatchKind.duplicate) {
      return SynchronousFuture('$name${josaEulReul(name)} 또 잡았어! 이미 있는 친구라 ${r.gold}G로 바꿨어.');
    }
    return SynchronousFuture('$name${josaEulReul(name)} 잡았어! 새 친구가 생겼네. '
        '${r.toField ? '필드에서 기다리고 있을 거야.' : '필드가 꽉 차서 가방에 넣어뒀어.'}');
  }
}
