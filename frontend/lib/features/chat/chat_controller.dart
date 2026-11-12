import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/constants/economy.dart';
import '../../core/state/game_repository.dart';
import '../../core/state/game_state.dart';
import '../../core/state/local_game_repository.dart';
import '../../core/utils/format.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/results.dart';
import 'chat_brain.dart';

/// 대화 단계: 시작 전 · 했어/못 했어 · 수행량 입력 · 확인 카드(말로 답했을 때) · 체크 끝 · 탐색 화면.
enum ChatStep { idle, yesNo, amount, done, explore }

class ChatMessage {
  const ChatMessage.bot(this.text, {this.reward, this.levelUp}) : fromBot = true;
  const ChatMessage.me(this.text)
      : fromBot = false,
        reward = null,
        levelUp = null;

  final bool fromBot;
  final String text;

  /// 보상 칩 (예: 성실도 +20 · +20G).
  final String? reward;

  /// 카테고리 레벨업 칩.
  final String? levelUp;
}

/// 습관 체크 대화의 흐름. 활성 습관 전부(최대 [Economy.maxActiveHabits]개)를 차례로 묻고,
/// 답은 확정 전까지 여기에만 임시로 두었다가 마지막에 한 번에 확정한다 (하루 1번, DB Q-4).
/// 말은 [ChatBrain]이, 규칙 계산(상위 3개 반영 · 골드 · 레벨)은 [GameState]가 한다.
class ChatController extends ChangeNotifier {
  /// [repository]를 안 주면 앱 안에서 계산한다 (테스트 · 시연).
  ChatController({
    required this.state,
    GameRepository? repository,
    this.brain = const ScriptedChatBrain(),
    this.timerMinutes,
  }) : repository = repository ?? LocalGameRepository(state);

  /// 오늘 공부 타이머로 잰 분 (습관 id → 분). 있으면 그 습관을 물을 때 미리 채운다.
  final int Function(String habitId)? timerMinutes;

  /// 읽기 (오늘 기록 · 남은 탐색 · 볼 개수 …).
  final GameState state;

  /// 바꾸기 (체크인 제출 · 탐색 · 포획). 서버를 붙이면 여기가 서버를 부른다.
  final GameRepository repository;
  final ChatBrain brain;

  final List<ChatMessage> messages = [];
  ChatStep step = ChatStep.idle;
  int _habitIndex = 0;

  /// 확정 전 임시 답 (습관 id → 값).
  final Map<String, double> _answers = {};

  /// 확정한 기록을 고치려고 다시 묻는 중 ([recheck]).
  bool _rechecking = false;

  /// 챗봇이 대답을 만드는 중 (AI 연결 시 입력을 막고 "…"을 보여준다).
  bool busy = false;

  /// 마지막 탐색에서 만난 몬스터.
  EncounterResult? encounter;

  /// 그 몬스터에게 던진 성실볼 결과 (아직 안 던졌으면 null).
  CatchResult? lastCatch;

  /// 방금 "탐색하기"로 나온 결과인지 (탐색 화면이 "찾는 중…" 연출을 한다). 남아 있던 등장을 되살린 것이면 false.
  bool justExplored = false;

  bool _disposed = false;

  List<Habit> get _habits => state.checkinHabits;
  Habit? get currentHabit => _habitIndex < _habits.length ? _habits[_habitIndex] : null;
  Measure? get currentMeasure => currentHabit == null ? null : state.measureOf(currentHabit!);

  /// 수행량 빠른 선택: 점수형은 3·4·5, 나머지는 목표의 50% · 100% · 150%.
  /// 서버 모드면 각각 가장 가까운 서버 선택지로 맞춘다 (버튼 값 = 기록되는 값).
  List<double> get quickAmounts {
    final h = currentHabit;
    final m = currentMeasure;
    if (h == null || m == null || m.isOX) return const [];
    double r1(double v) => (v * 10).round() / 10;
    final raw = m.unit == '점' ? const [3.0, 4.0, 5.0] : [r1(h.target * 0.5) < 1 ? 1.0 : r1(h.target * 0.5), h.target, r1(h.target * 1.5)];
    final timer = timedMinutes(h);
    return {if (timer > 0) state.recordableValue(h, timer.toDouble()), for (final v in raw) state.recordableValue(h, v)}.toList();
  }

  /// 오늘 공부 타이머로 잰 분 (시간(분) 습관만, 없으면 0).
  int timedMinutes(Habit h) => state.measureOf(h).unit == '분' ? (timerMinutes?.call(h.id) ?? 0) : 0;

  /// 대화 상대 (몬스터가 하나도 없으면 null).
  OwnedMonster? get partner => state.monsterByUid(state.chatPartnerUid) ?? state.monsters.firstOrNull;

  /// 방금 잡았지만 아직 결과 팝업을 닫지 않은 몬스터 (대화 상대 줄에서 잠깐 숨긴다).
  String? hiddenMonsterUid;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _think<T>(Future<T> f) async {
    busy = true;
    _notify();
    try {
      return await f;
    } finally {
      busy = false;
    }
  }

  /// 대화를 처음부터 (대화 상대가 바뀌었을 때). 오늘 이미 확정했으면 묻지 않고 탐색으로.
  Future<void> start() async {
    messages.clear();
    encounter = null;
    _answers.clear();
    _rechecking = false;
    final p = partner;
    final sp = p == null ? null : Catalog.speciesById(p.speciesId);
    messages.add(ChatMessage.bot(await _think(brain.greet(sp))));
    if (state.checkedInToday) {
      messages.add(ChatMessage.bot(await _think(brain.alreadyCheckedIn())));
      step = ChatStep.done;
      await _restoreEncounter();
      _notify();
      return;
    }
    await _ask(0);
  }

  /// [i]번째부터 아직 답이 없는 습관을 묻는다. 다 답했으면 바로 제출한다
  /// (확인 카드 [맞아!]는 없앴다 — 11-12 사용자. 잘못 기록됐으면 [다시 체크]로 고친다).
  Future<void> _ask(int i) async {
    var k = i;
    while (k < _habits.length && _answers.containsKey(_habits[k].id)) {
      k++;
    }
    _habitIndex = k;
    final h = currentHabit;
    if (h == null) {
      await _confirm();
      return;
    }
    messages.add(ChatMessage.bot(await _think(brain.askHabit(h, Catalog.category(h.categoryId)))));
    final timer = timedMinutes(h);
    if (timer > 0) messages.add(ChatMessage.bot("타이머로 $timer분 쟀네! '$timer분 했어'라고 보내 주면 돼."));
    step = ChatStep.yesNo;
    _notify();
  }

  /// 말(글)로 답하기: 서버 AI가 해석한 기록 후보를 답에 넣고, 아직 안 들은 습관을 이어서 묻는다.
  /// AI가 없거나(시연 모드) 실패하면 말 속의 숫자 · "못 했어"만 읽는다.
  Future<void> sendText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || busy || (step != ChatStep.yesNo && step != ChatStep.amount)) return;
    final asking = currentHabit;
    final history = [
      for (final m in messages.length > 10 ? messages.sublist(messages.length - 10) : messages)
        (m.fromBot ? 'BOT' : 'USER', m.text),
    ];
    messages.add(ChatMessage.me(text));
    _notify();
    final r = await _call(() => _think(repository.interpret(
          message: text,
          history: history,
          draft: Map.of(_answers),
          askingHabitId: asking?.id,
        )));
    if (r == null || (!r.fromAi && r.answers.isEmpty)) {
      if (r != null) messages.add(ChatMessage.bot(r.reply));
      await _readLocally(text, asking);
      return;
    }
    messages.add(ChatMessage.bot(r.reply));
    // 힘든 감정 · 위기 신호: 습관 질문을 밀어붙이지 않고 그 자리에 머문다 (버튼으로 이어 갈 수 있다)
    if (r.safety) {
      _notify();
      return;
    }
    for (final e in r.answers.entries) {
      if (_habits.any((h) => h.id == e.key)) _answers[e.key] = e.value;
    }
    final again = r.askAgainHabitId;
    final i = again == null ? -1 : _habits.indexWhere((h) => h.id == again);
    if (i >= 0 && !_answers.containsKey(again)) {
      _habitIndex = i;
      final q = r.askAgainQuestion;
      if (q != null && q.isNotEmpty && !r.reply.contains(q)) messages.add(ChatMessage.bot(q));
      step = state.measureOf(_habits[i]).isOX ? ChatStep.yesNo : ChatStep.amount;
      _notify();
      return;
    }
    await _ask(0);
  }

  /// AI 없이 (시연 모드 · AI 실패): 채팅만으로 답하게 말을 직접 읽는다 (11-12 버튼 없앰).
  /// "못/안 했어" → 0, 숫자 → 그 값 (했다/안 했다 습관은 1), "했어 · 응 · 다 했어" → 했다/안 했다 습관은 1,
  /// 양을 재는 습관이면 얼마나 했는지 되묻는다. 그 밖에는 말하는 법을 알려 준다.
  Future<void> _readLocally(String text, Habit? h) async {
    if (h == null) return;
    final m = state.measureOf(h);
    final n = RegExp(r'\d+(\.\d+)?').firstMatch(text);
    if (RegExp(r'못|안 ?했|아니|안 ?함').hasMatch(text)) {
      return _record(0);
    }
    if (n != null) {
      final v = double.parse(n.group(0)!);
      return _record(m.isOX ? (v > 0 ? 1 : 0) : v);
    }
    if (RegExp(r'했|응|ㅇㅇ|네|예|그럼|완료|당연').hasMatch(text)) {
      if (m.isOX) {
          return _record(1);
      }
      if (step == ChatStep.yesNo) {
        messages.add(ChatMessage.bot(await _think(brain.askAmount(h, m))));
        step = ChatStep.amount;
      } else {
        messages.add(ChatMessage.bot('좋아! 몇 ${m.unit} 했는지 숫자로 알려줄래?'));
      }
      _notify();
      return;
    }
    messages.add(const ChatMessage.bot("음… 잘 못 알아들었어. '30분 했어'나 '못 했어'처럼 말해 줄래?"));
    _notify();
  }

  /// 했어 / 못 했어.
  Future<void> answer(bool yes) async {
    final h = currentHabit;
    if (h == null || step != ChatStep.yesNo || busy) return;
    messages.add(ChatMessage.me(yes ? '했어!' : '못 했어…'));
    if (!yes) return _record(0);
    final m = state.measureOf(h);
    if (m.isOX) return _record(1);
    messages.add(ChatMessage.bot(await _think(brain.askAmount(h, m))));
    step = ChatStep.amount;
    _notify();
  }

  /// 수행량 보내기. 숫자가 아니면 false.
  Future<bool> sendAmount(String raw) async {
    final v = double.tryParse(raw.trim());
    if (v == null || v < 0) return false;
    await sendValue(v);
    return true;
  }

  Future<void> sendValue(double v) async {
    final m = currentMeasure;
    if (m == null || step != ChatStep.amount || busy) return;
    messages.add(ChatMessage.me('${formatNum(v)}${m.unit}'));
    await _record(v);
  }

  /// 답 하나를 임시로 적고, 미리 계산한 점수로 반응한다 (골드는 확정 때).
  Future<void> _record(double raw) async {
    final h = currentHabit!;
    // 서버 모드: 서버가 받는 값(선택지) 중 가장 가까운 값으로 기록 (결정 D-42). 바뀌었으면 알려 준다.
    final v = state.recordableValue(h, raw);
    if (v != raw) {
      messages.add(ChatMessage.bot('선택지에 맞춰 ${formatNum(v)}${state.measureOf(h).unit} 기록할게!'));
    }
    _answers[h.id] = v;
    final preview = sincerityScore(measure: state.measureOf(h), target: h.target, value: v);
    messages.add(ChatMessage.bot(await _think(brain.react(h, preview))));
    await _ask(_habitIndex + 1);
  }

  /// 확정한 오늘 기록을 고친다: 습관을 처음부터 다시 묻고 마지막에 다시 제출한다 (DB v1.5).
  /// 보상(골드 · 레벨 · 탐색 횟수)은 첫 확정 그대로다.
  Future<void> recheck() async {
    if (!state.checkedInToday || step != ChatStep.done || busy) return;
    _rechecking = true;
    _answers.clear();
    messages.add(ChatMessage.bot(await _think(brain.recheckIntro())));
    await _ask(0);
  }

  /// 마지막 답까지 받으면 한 번에 확정: 상위 3개 반영 · 골드 · 레벨업 · 오늘 탐색 횟수.
  /// 다시 체크 중이었으면 기록만 고친다.
  Future<void> _confirm() async {
    if (_rechecking) {
      _rechecking = false;
      final again = await _call(() => repository.resubmitCheckin(_answers));
      _answers.clear();
      if (again != null) messages.add(ChatMessage.bot(await _think(_closingLine(() => brain.recheckDone(again)))));
      step = ChatStep.done;
      _notify();
      return;
    }
    final r = await _call(() => repository.confirmCheckin(_answers));
    _answers.clear();
    if (r == null) {
      step = ChatStep.done;
      _notify();
      return;
    }
    final text = await _think(_closingLine(() => brain.wrapUp(r, maxScore: GameState.maxDailyScore)));
    final lv = [
      for (final e in r.levelUps.entries) '${Catalog.category(e.key).name} Lv.${e.value} 달성!',
    ];
    final lvGold = r.goldEarned - r.countedScore * Economy.goldPerSincerity - r.periodBonusGold;
    messages.add(ChatMessage.bot(
      text,
      reward: r.countedScore > 0 ? '성실도 +${r.countedScore} · +${r.countedScore * Economy.goldPerSincerity}G' : null,
      levelUp: lv.isEmpty ? null : '${lv.join(' · ')} +${lvGold}G',
    ));
    if (r.periodBonusGold > 0) {
      messages.add(ChatMessage.bot('습관 기간을 다 채웠어! 기간 보너스 +${r.periodBonusGold}G'));
    }
    step = ChatStep.done;
    _notify();
  }

  // ---------- 탐색 ----------
  /// 탐색 1회: 몬스터가 나타난다 (아직 안 잡음).
  Future<void> explore() async {
    final r = await _call(repository.explore);
    if (r == null) return;
    encounter = r;
    lastCatch = null;
    justExplored = true;
    step = ChatStep.explore;
    _notify();
  }

  /// "그만"을 눌렀거나 앱이 꺼져서 남아 있는 오늘의 등장을 되살린다 (서버 `GET /explores/pending`). 로컬 모드는 없음.
  Future<void> _restoreEncounter() async {
    final e = await _call(repository.pendingEncounter);
    if (e == null) return;
    final n = e.species!.name;
    encounter = e;
    lastCatch = null;
    justExplored = false;
    messages.add(ChatMessage.bot('아까 만난 $n${josaIGa(n)} 아직 근처에 있어! 성실볼을 던져 볼까?'));
    step = ChatStep.explore;
  }

  /// 지금 나타난 몬스터에게 성실볼을 던질 수 있는지 (이미 던졌으면 끝).
  bool get canThrow => encounter?.catchable == true && lastCatch == null;

  /// 성실볼 1개를 던진다. 볼이 없거나 던질 대상이 없으면 null.
  /// 잡았으면 대화창에도 남긴다 (놓치면 남기지 않음).
  Future<CatchResult?> throwBall() async {
    if (!canThrow) return null;
    final r = await _call(() => repository.throwBall(encounter!));
    if (r == null) return null;
    lastCatch = r;
    hiddenMonsterUid = r.monster?.uid;
    _notify();
    if (r.caught) messages.add(ChatMessage.bot(await brain.catchReport(r)));
    return r;
  }

  /// 잡기 결과 팝업을 닫았다.
  void confirmCatch() {
    hiddenMonsterUid = null;
    _notify();
  }

  void leaveExplore() {
    step = ChatStep.done;
    _notify();
  }

  /// 서버 오류면 그 문구를 몬스터 말풍선으로 보여주고 null (예: 날짜가 바뀌었어요 · 서버에 연결할 수 없어요).
  /// 체크인 · 다시 체크를 마친 뒤의 마무리 말: 서버 대사(AI, D-64)가 있으면 그것, 없으면 [scripted] 대본.
  Future<String> _closingLine(Future<String> Function() scripted) async =>
      await repository.checkinDialogue() ?? await scripted();

  Future<T?> _call<T>(Future<T?> Function() action) async {
    try {
      return await action();
    } on ApiException catch (e) {
      messages.add(ChatMessage.bot(e.message));
      _notify();
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
