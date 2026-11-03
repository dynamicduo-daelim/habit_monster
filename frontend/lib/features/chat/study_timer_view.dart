import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/audio/bgm.dart';
import '../../core/state/game_state.dart';
import '../../core/state/study_timer.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/pixel_icons.dart';

/// 공부방 장면의 모습 (타이머 상태에서 정한다).
enum _Mood { idle, focus, rest, paused, done }

/// 챗봇 탭 옆 "공부 타이머" 칸 (기획 2026-10-29-AI-챗봇-체크인 3-5, 2026-11-02 공부방으로 개편 — 결정 D-59).
/// 고른 루틴몬(1~3마리)이 공부방 책상에 앉아 같이 공부한다. 뽀모도로(집중 → 쉬는 시간)로 돌고,
/// 집중하는 동안엔 배경음악 대신 공부 소리가 난다 (셸이 [StudySound.track]을 튼다).
/// 끝내면 집중한 분만 오늘 그 습관에 쌓이고 챗봇 체크인 때 미리 채워 준다. 최대 [StudyTimer.maxMinutes]분이면 저절로 끝난다.
class StudyTimerView extends StatefulWidget {
  const StudyTimerView({super.key, required this.timer, this.onSaved, this.onGoChat, this.onPreview});
  final StudyTimer timer;

  /// 끝내서 기록이 쌓였을 때 (분). 셸이 토스트를 띄운다.
  final void Function(int minutes)? onSaved;

  /// [챗봇에 기록하러].
  final VoidCallback? onGoChat;

  /// 설정에서 소리를 고르면 잠깐 들려준다.
  final void Function(BgmTrack track)? onPreview;

  /// 타이머를 쓸 수 있는 습관: 공부 카테고리 + 단위가 분.
  static List<Habit> studyHabits(GameState s) =>
      [for (final h in s.habits) if (h.categoryId == 'st' && s.measureOf(h).unit == '분') h];

  /// 같이 공부하는 친구: 고른 몬스터 중 아직 가진 것, 없으면 대화 상대 (그것도 없으면 첫 몬스터).
  static List<OwnedMonster> friendsOf(GameState s, StudyTimer t) {
    final picked = [for (final uid in t.friends) if (s.monsterByUid(uid) case final m?) m];
    if (picked.isNotEmpty) return picked;
    final first = s.monsterByUid(s.chatPartnerUid) ?? s.monsters.firstOrNull;
    return [if (first != null) first];
  }

  /// 시계 글자: 1시간 미만이면 mm:ss, 넘으면 h:mm:ss.
  static String clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final mmss = '${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return d.inHours > 0 ? '${d.inHours}:$mmss' : mmss;
  }

  @override
  State<StudyTimerView> createState() => _StudyTimerViewState();
}

class _StudyTimerViewState extends State<StudyTimerView> {
  Timer? _tick;
  String? _picked;

  /// 0.6초마다 바뀌는 박자 (몬스터 움직임 · 반짝임).
  int _beat = 0;

  /// 방금 끝낸 기록 (다시 시작하기 전까지 "수고했어" 장면).
  int? _doneMinutes;
  int _doneTomatoes = 0;

  StudyTimer get t => widget.timer;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (!mounted) return;
      if (t.overLimit) {
        _stop(auto: true);
        return;
      }
      setState(() => _beat++);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _start(String habitId) {
    _doneMinutes = null;
    t.start(habitId);
  }

  void _stop({bool auto = false}) {
    final got = t.sessionTomatoes;
    final m = t.stop();
    setState(() {
      _doneMinutes = m;
      _doneTomatoes = got;
    });
    widget.onSaved?.call(m);
    if (auto && mounted) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: const Text('${StudyTimer.maxMinutes ~/ 60}시간이 지나서 타이머를 멈췄어요. 아직 공부 중이면 다시 시작해 주세요!'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))],
        ),
      );
    }
  }

  _Mood get _mood {
    if (t.idle) return _doneMinutes != null ? _Mood.done : _Mood.idle;
    if (t.isPaused) return _Mood.paused;
    return t.phase == StudyPhase.focus ? _Mood.focus : _Mood.rest;
  }

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final habits = StudyTimerView.studyHabits(s);
    if (habits.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('공부 시간(분) 습관이 없어요.\n홈 › 습관에서 공부 습관을 추가하면 타이머를 쓸 수 있어요.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.7, color: AppColors.textMuted)),
        ),
      );
    }
    final current = t.habitId ?? (habits.any((h) => h.id == _picked) ? _picked! : habits.first.id);
    final habit = habits.firstWhere((h) => h.id == current, orElse: () => habits.first);
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final friends = StudyTimerView.friendsOf(s, t);
        final mood = _mood;
        Widget room({double? height}) => _StudyRoom(
              height: height,
              friends: friends,
              mood: mood,
              beat: _beat,
              tomatoes: t.todayTomatoes() + (t.idle ? 0 : t.sessionTomatoes),
              rain: t.sound == StudySound.rain && mood == _Mood.focus,
              bubble: _bubble(mood, friends),
            );
        List<Widget> below() => [
              const SizedBox(height: 12),
              _blackboard(habit, mood),
              if (habits.length > 1) ...[
                const SizedBox(height: 10),
                _habitChips(habits, habit),
              ],
              const SizedBox(height: 12),
              _buttons(habit, mood),
            ];
        // 한 화면에 다 보이게 (11-02, 사용자 "내려야 돼서 불편"): 공부방이 남는 높이를 차지하고 줄어든다.
        // 화면이 아주 낮아 공부방이 [_StudyRoom.minHeight]보다 작아지면 그때만 스크롤.
        return LayoutBuilder(builder: (context, box) {
          final fits = box.maxHeight >= _StudyRoom.minHeight + 300 + (habits.length > 1 ? 46 : 0);
          const pad = EdgeInsets.fromLTRB(14, 10, 14, 12);
          if (!fits) {
            return ListView(padding: pad, children: [
              _friendsRow(s, friends),
              const SizedBox(height: 10),
              room(height: _StudyRoom.minHeight),
              ...below(),
            ]);
          }
          return Padding(
            padding: pad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _friendsRow(s, friends),
                const SizedBox(height: 10),
                Expanded(child: room()),
                ...below(),
              ],
            ),
          );
        });
      },
    );
  }

  /// 말풍선: 5박자(3초)마다 다음 말, 말하는 친구도 돌아가며.
  (int, String) _bubble(_Mood mood, List<OwnedMonster> friends) {
    final lines = switch (mood) {
      _Mood.focus => const ['열공 중!', '집중 집중…', '이 문제 어렵다…', '거의 다 왔어!', '같이 하니까 좋다!'],
      _Mood.rest => const ['쉬는 시간~', '기지개 쭉!', '물 한 잔 마시자'],
      _Mood.paused => const ['잠깐만… 쿨…'],
      _Mood.idle => const ['같이 공부할래?'],
      _Mood.done => ['오늘 ${_doneMinutes ?? 0}분 했어! 최고야!'],
    };
    final turn = _beat ~/ 5;
    return (turn % friends.length.clamp(1, 3), lines[turn % lines.length]);
  }

  Widget _friendsRow(GameState s, List<OwnedMonster> friends) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('같이 공부하는 친구',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.goldLight)),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final m in friends) ...[
                    _Avatar(m, size: 34),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      friends.map((m) => Catalog.speciesById(m.speciesId).name).join(' · '),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.purpleSoft),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          width: 72,
          child: RoundBlockButton(
            label: '바꾸기',
            height: 40,
            fontSize: 12,
            color: AppColors.gold,
            onPressed: s.monsters.isEmpty ? null : () => _openFriends(s, friends),
          ),
        ),
      ],
    );
  }

  Widget _blackboard(Habit habit, _Mood mood) {
    final status = switch (mood) {
      _Mood.idle => t.free ? '준비 · 자유' : '준비 · ${t.focusMinutes}분 집중',
      _Mood.focus => t.free ? '집중 중' : '${t.round}번째 집중',
      _Mood.rest => '쉬는 시간 (${t.breakMinutes}분)',
      _Mood.paused => '잠깐 멈춤',
      _Mood.done => _doneTomatoes > 0 ? '수고했어! 토마토 $_doneTomatoes개' : '수고했어!',
    };
    final shown = mood == _Mood.done ? Duration(minutes: _doneMinutes ?? 0) : t.display;
    final setup = '${t.free ? '자유' : '${t.focusMinutes}분 · ${t.breakMinutes}분 쉼'} · ${t.sound.label}';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.chalkboard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.woodDark, width: 5),
        boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(0, 4))],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 10,
            top: 8,
            child: Text(setup, style: const TextStyle(fontSize: 11, color: AppColors.chalkSoft)),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: Semantics(
              button: true,
              label: '타이머 설정',
              child: GestureDetector(
                key: const ValueKey('timer_settings'),
                onTap: _openSettings,
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.woodDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.ink, width: 2),
                  ),
                  child: const PixelIcon(layers: [
                    PixelLayer(PixelIcons.gear, AppColors.cream),
                    PixelLayer(PixelIcons.gearHole, AppColors.woodDark),
                  ], size: 20),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 30, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(status, style: const TextStyle(fontSize: 13, color: AppColors.goldLight)),
                const SizedBox(height: 2),
                Text(
                  StudyTimerView.clock(shown),
                  key: const ValueKey('timer_clock'),
                  style: const TextStyle(
                      fontFamily: AppTheme.pixelFont,
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: AppColors.offWhite),
                ),
                const SizedBox(height: 2),
                Text('${habit.name} · 목표 ${habit.target.round()}분 · 오늘 ${t.todayMinutes(habit.id)}분',
                    style: const TextStyle(fontSize: 12, color: AppColors.chalkSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _habitChips(List<Habit> habits, Habit habit) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final h in habits)
          ChoiceChip(
            label: Text(h.name),
            selected: h.id == habit.id,
            showCheckmark: false,
            disabledColor: h.id == habit.id ? AppColors.purpleDeep : AppColors.nightRaised,
            onSelected: t.idle ? (_) => setState(() => _picked = h.id) : null,
            selectedColor: AppColors.purpleDeep,
            backgroundColor: AppColors.nightRaised,
            labelStyle: TextStyle(color: h.id == habit.id ? AppColors.goldLight : AppColors.text, fontSize: 13),
            side: BorderSide(color: h.id == habit.id ? AppColors.gold : AppColors.nightLine2, width: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
      ],
    );
  }

  Widget _buttons(Habit habit, _Mood mood) {
    Widget pair(Widget a, Widget b) => Row(children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]);
    switch (mood) {
      case _Mood.idle:
        return RoundBlockButton(
            label: '같이 집중 시작', onPressed: () => _start(habit.id), color: AppColors.gold, shadowColor: AppColors.goldShadow);
      case _Mood.done:
        return pair(
          RoundBlockButton(
              label: '한 번 더', onPressed: () => _start(habit.id), color: AppColors.introFloor, textColor: AppColors.text),
          RoundBlockButton(
              label: '챗봇에 기록하러', onPressed: widget.onGoChat, color: AppColors.purple, textColor: AppColors.white),
        );
      case _Mood.focus || _Mood.rest || _Mood.paused:
        return pair(
          RoundBlockButton(
            label: t.running ? '일시정지' : '이어서',
            onPressed: t.running ? t.pause : t.resume,
            color: AppColors.introFloor,
            textColor: AppColors.text,
          ),
          RoundBlockButton(label: '끝내기', onPressed: _stop, color: AppColors.gold, shadowColor: AppColors.goldShadow),
        );
    }
  }

  // ---------- 내 루틴몬 (친구 고르기) ----------
  void _openFriends(GameState s, List<OwnedMonster> shown) {
    if (t.friends.isEmpty) t.setFriends([for (final m in shown) m.uid]);
    String filter = 'all';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => AnimatedBuilder(
          animation: t,
          builder: (ctx, _) {
            final cats = [for (final c in Catalog.categories) if (s.monsters.any((m) => _cat(m) == c.id)) c];
            final list = [for (final m in s.monsters) if (filter == 'all' || _cat(m) == filter) m];
            final picked = [for (final uid in t.friends) if (s.monsterByUid(uid) case final m?) m];
            return _Sheet(
              height: MediaQuery.sizeOf(ctx).height * 0.72,
              children: [
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('내 루틴몬',
                        style: TextStyle(
                            fontFamily: AppTheme.pixelFont, fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text('같이 공부할 친구를 골라요 · 최대 ${StudyTimer.maxFriends}마리',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (id, label) in [('all', '전체'), for (final c in cats) (c.id, c.short)])
                      _Pill(label: label, on: filter == id, onTap: () => setSheet(() => filter = id)),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.82,
                    children: [
                      for (final m in list)
                        _CollectionCard(
                          monster: m,
                          order: t.friends.indexOf(m.uid) + 1,
                          onTap: () => t.toggleFriend(m.uid),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final m in picked) ...[_Avatar(m, size: 28), const SizedBox(width: 4)],
                    const SizedBox(width: 4),
                    Text('${picked.length}마리 골랐어요', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    const Spacer(),
                    SizedBox(
                      width: 96,
                      child: RoundBlockButton(
                          label: '완료', height: 46, color: AppColors.gold, onPressed: () => Navigator.pop(ctx)),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _cat(OwnedMonster m) => Catalog.speciesById(m.speciesId).categoryId;

  // ---------- 타이머 설정 (톱니바퀴) ----------
  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AnimatedBuilder(
        animation: t,
        builder: (ctx, _) {
          final locked = !t.idle;
          Widget stepper(String label, int value, int step, void Function(int) set) {
            final off = t.free || locked;
            Widget btn(String text, int d) => _SquareButton(
                  text: text,
                  onTap: off ? null : () => set(value + d),
                );
            return Opacity(
              opacity: off ? 0.35 : 1,
              child: Row(
                children: [
                  SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text))),
                  btn('−', -step),
                  Expanded(
                    child: Text('$value분',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontFamily: AppTheme.pixelFont,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text)),
                  ),
                  btn('+', step),
                ],
              ),
            );
          }

          return _Sheet(
            children: [
              const Text('타이머 설정',
                  style: TextStyle(
                      fontFamily: AppTheme.pixelFont, fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 14),
              _Box(children: [
                Row(
                  children: [
                    const _Tomato(size: 16),
                    const SizedBox(width: 8),
                    const Text('뽀모도로',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.goldLight)),
                    const Spacer(),
                    const Text('시간 제한 없이', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    const SizedBox(width: 8),
                    _Switch(on: t.free, onTap: locked ? null : () => t.setFree(!t.free)),
                  ],
                ),
                const SizedBox(height: 12),
                stepper('집중 시간', t.focusMinutes, 5, t.setFocusMinutes),
                const SizedBox(height: 12),
                stepper('쉬는 시간', t.breakMinutes, 1, t.setBreakMinutes),
                if (locked) ...[
                  const SizedBox(height: 10),
                  const Text('재는 중엔 시간을 바꿀 수 없어요. 끝낸 뒤 바꿔 주세요.',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ]),
              const SizedBox(height: 14),
              _Box(children: [
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('공부 소리',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.purpleSoft)),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text('집중하는 동안 배경음악 대신 들려요',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final snd in StudySound.values)
                  InkWell(
                    onTap: () {
                      t.setSound(snd);
                      widget.onPreview?.call(snd.track);
                    },
                    child: SizedBox(
                      height: 42,
                      child: Row(
                        children: [
                          const SizedBox(width: 6),
                          Container(
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: t.sound == snd ? AppColors.gold : AppColors.nightLine2, width: 2),
                            ),
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle, color: t.sound == snd ? AppColors.gold : Colors.transparent),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(snd.label, style: const TextStyle(fontSize: 14, color: AppColors.text)),
                          const Spacer(),
                          Text(snd.hint, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          const SizedBox(width: 6),
                        ],
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              const Text(
                '끝내면 집중한 시간만 오늘 공부 기록에 쌓여요 (쉬는 시간은 빼고). 챗봇 체크인 때 미리 채워 줘요. '
                '한 번에 최대 ${StudyTimer.maxMinutes ~/ 60}시간 · 앱을 닫아도 이어서 재요.',
                style: TextStyle(fontSize: 11, height: 1.6, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              RoundBlockButton(label: '완료', height: 48, color: AppColors.gold, onPressed: () => Navigator.pop(ctx)),
            ],
          );
        },
      ),
    );
  }
}

/// 공부방: 창문 · 책장 · 책상 · 스탠드 불빛 · 앉아 있는 친구들 · 펼친 책 · 연필 · Zzz · 하트 · 토마토 · 말풍선.
class _StudyRoom extends StatelessWidget {
  const _StudyRoom({
    this.height,
    required this.friends,
    required this.mood,
    required this.beat,
    required this.tomatoes,
    required this.rain,
    required this.bubble,
  });
  final List<OwnedMonster> friends;
  final _Mood mood;
  final int beat;
  final int tomatoes;
  final bool rain;
  final (int, String) bubble;

  /// 정해진 높이 (null이면 부모가 준 높이를 다 쓴다).
  final double? height;

  /// 이보다 낮으면 화면이 스크롤로 바뀐다.
  static const double minHeight = 180;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.studyRoom,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ink, width: 2),
        boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(0, 4))],
      ),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        // 책상 윗면에서 방 바닥 끝까지 (책상 다리 · 토마토 자리) — 방이 낮으면 다리를 짧게 보여 몸집을 지킨다
        final belowDesk = (h * 0.38).clamp(70.0, 116.0);
        final deskTop = h - belowDesk; // 방 높이가 바뀌면 책상 · 바닥이 아래에 붙어 따라간다
        final n = friends.length.clamp(1, 3);
        // 말풍선(위 34px)까지 방 안에 들어오게 몸집을 줄인다
        final size = min(n == 1 ? 116.0 : (n == 2 ? 100.0 : 84.0), deskTop - 42);
        final even = beat.isEven;
        // 상태별 움직임: 집중 = 끄덕끄덕 · 쉬는 시간/준비 = 좌우로 흔들 · 멈춤 = 조는 고개 · 끝 = 깡충
        double dy(int i) {
          final on = (beat + i).isEven;
          return switch (mood) {
            _Mood.focus => on ? -3 : 1,
            _Mood.done => on ? -12 : 0,
            _Mood.paused => 2,
            _ => -6,
          };
        }

        double turn(int i) {
          final on = (beat + i).isEven;
          return switch (mood) {
            _Mood.idle || _Mood.rest => on ? -0.05 : 0.05,
            _Mood.paused => 0.08,
            _ => 0,
          };
        }

        double cx(int i) => w / (n + 1) * (i + 1);
        final speaker = bubble.$1.clamp(0, n - 1);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // 벽 · 바닥 (바닥 널빤지 줄)
            Positioned(left: 0, right: 0, top: 0, height: deskTop - 14, child: const ColoredBox(color: AppColors.purpleDeep)),
            Positioned(
              left: 0,
              right: 0,
              top: deskTop - 14,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.studyFloor,
                  border: Border(top: BorderSide(color: AppColors.introFloor, width: 3)),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < 12; i++)
                      Expanded(
                        child: Container(
                            decoration: const BoxDecoration(
                                border: Border(right: BorderSide(color: Color(0x400D0B16), width: 3)))),
                      ),
                  ],
                ),
              ),
            ),
            // 창문 (빗소리면 비가 내린다, 아니면 달 · 별)
            Positioned(left: 16, top: 14, child: _Window(rain: rain, beat: beat)),
            // 책장
            Positioned(
              right: 18,
              top: 26,
              child: Container(
                width: 64,
                height: 56,
                padding: const EdgeInsets.fromLTRB(5, 0, 5, 4),
                decoration: BoxDecoration(
                  color: AppColors.nightRaised,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.ink, width: 3),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (c, h) in const [
                      (AppColors.redSoft, 28.0),
                      (AppColors.bookBlue, 24.0),
                      (AppColors.rateMid, 30.0),
                      (AppColors.green, 22.0),
                      (AppColors.purpleSoft, 26.0),
                    ])
                      Expanded(child: Container(height: h, margin: const EdgeInsets.only(right: 2), color: c)),
                  ],
                ),
              ),
            ),
            // 스탠드 불빛 (집중할 때만)
            if (mood == _Mood.focus)
              Positioned(
                left: 0,
                right: 0,
                top: deskTop - 84,
                height: 110,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topCenter,
                        radius: 1.1,
                        colors: [AppColors.butter.withValues(alpha: 0.30), AppColors.butter.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
            // 친구들 (책상 뒤에 앉아 있다)
            for (var i = 0; i < n; i++)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeInOut,
                left: cx(i) - size / 2,
                top: deskTop + 6 - size + dy(i),
                width: size,
                height: size,
                child: AnimatedRotation(
                  turns: turn(i) / 6.283,
                  duration: const Duration(milliseconds: 450),
                  alignment: Alignment.bottomCenter,
                  child: PixelImage(
                    Catalog.speciesById(friends[i].speciesId).assetAt(friends[i].level),
                    width: size,
                    height: size,
                    alignment: Alignment.bottomCenter,
                  ),
                ),
              ),
            // Zzz (멈춤)
            if (mood == _Mood.paused)
              for (var k = 0; k < 3; k++)
                Positioned(
                  left: cx(speaker) + size / 2 - 14 + k * 9,
                  top: deskTop - size - 4 - k * 13 - (even ? 3 : 0),
                  child: Text('Z',
                      style: TextStyle(
                          fontFamily: AppTheme.pixelFont,
                          fontSize: 13 + k * 4.0,
                          fontWeight: FontWeight.w700,
                          color: AppColors.purpleSoft.withValues(alpha: k == 2 && even ? 0.5 : 1))),
                ),
            // 하트 (끝)
            if (mood == _Mood.done)
              for (var i = 0; i < n; i++)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 450),
                  left: cx(i) - 8,
                  top: deskTop - size - (even ? 22 : 12) - (i.isOdd ? 8 : 0),
                  child: const Text('♥', style: TextStyle(fontSize: 18, color: AppColors.heart)),
                ),
            // 책상
            Positioned(
              left: 26,
              right: 26,
              top: deskTop + 14,
              height: 18,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.wood,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.ink, width: 3),
                ),
                alignment: Alignment.topCenter,
                child: Container(height: 3, color: AppColors.woodLight),
              ),
            ),
            for (final left in [true, false])
              Positioned(
                left: left ? 42 : null,
                right: left ? null : 42,
                top: deskTop + 32,
                child: Container(
                  width: 14,
                  height: 74,
                  decoration: const BoxDecoration(
                    color: AppColors.woodDark,
                    border: Border(
                      left: BorderSide(color: AppColors.ink, width: 3),
                      right: BorderSide(color: AppColors.ink, width: 3),
                      bottom: BorderSide(color: AppColors.ink, width: 3),
                    ),
                  ),
                ),
              ),
            // 펼친 책 (집중 · 멈춤)
            if (mood == _Mood.focus || mood == _Mood.paused)
              for (var i = 0; i < n; i++)
                Positioned(left: cx(i) - 28, top: deskTop + 2, child: const _OpenBook()),
            // 연필 (집중 중 첫 친구가 사각사각)
            if (mood == _Mood.focus)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                left: cx(0) + 18 + (even ? 0 : 6),
                top: deskTop - 18 + (even ? 0 : 2),
                child: Transform.rotate(
                  angle: 0.5,
                  child: const PixelIcon(layers: PixelIcons.pencil, size: 22),
                ),
              ),
            // 말풍선
            Positioned(
              left: (cx(speaker) + size * 0.12).clamp(8, w - 150),
              top: (deskTop - size - 34).clamp(6, h),
              child: Container(
                key: ValueKey('bubble_${bubble.$2}'),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: const BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                    bottomLeft: Radius.circular(2),
                  ),
                  border: Border.fromBorderSide(BorderSide(color: AppColors.ink, width: 2)),
                  boxShadow: [BoxShadow(color: AppColors.ink, offset: Offset(0, 3))],
                ),
                child: Text(bubble.$2,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brownText)),
              ),
            ),
            // 오늘 모은 토마토
            if (tomatoes > 0)
              Positioned(
                left: 12,
                bottom: 10,
                child: Row(
                  children: [
                    for (var k = 0; k < tomatoes.clamp(0, 6); k++) ...[const _Tomato(size: 16), const SizedBox(width: 4)],
                    if (tomatoes > 6)
                      Text('+${tomatoes - 6}', style: const TextStyle(fontSize: 11, color: AppColors.goldLight)),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _Window extends StatelessWidget {
  const _Window({required this.rain, required this.beat});
  final bool rain;
  final int beat;

  @override
  Widget build(BuildContext context) {
    final shift = (beat % 3) * 7.0;
    return Container(
      width: 104,
      height: 84,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.nightPanel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.woodDark, width: 5),
      ),
      child: Stack(
        children: [
          if (rain)
            for (var k = 0; k < 9; k++)
              Positioned(
                left: 4.0 + k * 10.5,
                top: ((k * 17 + shift * 2) % 70) - 6,
                child: Container(width: 2, height: 12, color: AppColors.bookBlue.withValues(alpha: 0.7)),
              )
          else ...[
            Positioned(
              left: 58,
              top: 6,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.butter),
              ),
            ),
            for (final (x, y, c) in const [
              (8.0, 8.0, AppColors.butter),
              (22.0, 48.0, AppColors.white),
              (70.0, 50.0, AppColors.purpleSoft),
            ])
              Positioned(
                left: x,
                top: y,
                child: Opacity(
                  opacity: (beat + x.toInt()).isEven ? 1 : 0.35,
                  child: Transform.rotate(angle: 0.785, child: Container(width: 5, height: 5, color: c)),
                ),
              ),
          ],
          // 창살
          const Positioned(left: 44, top: 0, bottom: 0, width: 4, child: ColoredBox(color: AppColors.woodDark)),
          const Positioned(left: 0, right: 0, top: 34, height: 4, child: ColoredBox(color: AppColors.woodDark)),
        ],
      ),
    );
  }
}

class _OpenBook extends StatelessWidget {
  const _OpenBook();

  @override
  Widget build(BuildContext context) {
    Widget page(double skew) => Transform(
          transform: Matrix4.skewY(skew),
          child: Container(
            width: 28,
            height: 14,
            decoration: BoxDecoration(color: AppColors.cream, border: Border.all(color: AppColors.ink, width: 2)),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [page(0.1), page(-0.1)]);
  }
}

/// 토마토 (뽀모도로 한 번 = 하나).
class _Tomato extends StatelessWidget {
  const _Tomato({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            top: size * 0.15,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.redSoft,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.ink, width: 1.5),
              ),
            ),
          ),
          Positioned(
            left: size * 0.3,
            top: 0,
            child: Container(
              width: size * 0.4,
              height: size * 0.28,
              decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.monster, {required this.size});
  final OwnedMonster monster;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.purpleDeep,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.gold, width: 2),
      ),
      child: PixelImage(Catalog.speciesById(monster.speciesId).assetAt(monster.level)),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.monster, required this.order, required this.onTap});
  final OwnedMonster monster;

  /// 고른 순서 (0이면 안 고름).
  final int order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sp = Catalog.speciesById(monster.speciesId);
    final cat = Catalog.category(sp.categoryId);
    final on = order > 0;
    return Semantics(
      button: true,
      selected: on,
      label: sp.name,
      child: GestureDetector(
        key: ValueKey('friend_${monster.uid}'),
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
              decoration: BoxDecoration(
                color: on ? AppColors.purpleDeep : AppColors.nightRaised,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: on ? AppColors.gold : AppColors.nightLine2, width: 2),
              ),
              child: Column(
                children: [
                  Expanded(child: PixelImage(sp.assetAt(monster.level), alignment: Alignment.bottomCenter)),
                  const SizedBox(height: 4),
                  Text(sp.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text)),
                  Text('${cat.short} · Lv.${monster.level}', style: TextStyle(fontSize: 11, color: cat.color)),
                ],
              ),
            ),
            if (on)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.ink, width: 2),
                  ),
                  child: Text('$order',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 아래에서 올라오는 시트 (손잡이 + 내용).
class _Sheet extends StatelessWidget {
  const _Sheet({required this.children, this.height});
  final List<Widget> children;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      decoration: const BoxDecoration(
        color: AppColors.nightPanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.nightLine2, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: AppColors.sheetHandle, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.nightRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.nightLine2, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? AppColors.purpleDeep : AppColors.nightRaised,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: on ? AppColors.gold : AppColors.nightLine2, width: 2),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: on ? AppColors.goldLight : AppColors.textMuted)),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.text, required this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.introFloor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.ink, width: 2),
        ),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.on, required this.onTap});
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: on,
      label: '자유 모드',
      child: GestureDetector(
        key: const ValueKey('timer_free'),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 46,
          height: 26,
          padding: const EdgeInsets.all(2),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: on ? AppColors.green : AppColors.nightLine2,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.ink, width: 2),
          ),
          child: Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(color: AppColors.cream, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
