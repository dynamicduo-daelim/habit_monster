import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/help_button.dart';
import 'home_parts.dart';

/// 홈 아래 슬라이드 시트. 접히면 오늘의 성실도 요약, 펼치면 [습관 리스트 | 오늘의 성실도] 두 쪽.
class HabitSheet extends StatefulWidget {
  const HabitSheet({super.key, required this.maxHeight, required this.onGoChat});

  /// 홈 본문 높이 (펼친 높이가 넘지 않게).
  final double maxHeight;
  final VoidCallback onGoChat;

  static const double closedHeight = 108;
  static const double openHeight = 470;

  @override
  State<HabitSheet> createState() => _HabitSheetState();
}

class _HabitSheetState extends State<HabitSheet> {
  bool _open = false;
  int _page = 0;

  void _toggle() => setState(() => _open = !_open);

  void _onDrag(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v < -100 && !_open) setState(() => _open = true);
    if (v > 100 && _open) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final openH = math.min(HabitSheet.openHeight, widget.maxHeight - 40);
    final score = s.todayScore;
    final pct = score / GameState.maxDailyScore;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: _open ? openH : HabitSheet.closedHeight,
      decoration: const BoxDecoration(
        color: AppColors.nightDeep,
        border: Border(top: BorderSide(color: AppColors.purple, width: 3)),
      ),
      child: GestureDetector(
        onVerticalDragEnd: _onDrag,
        behavior: HitTestBehavior.translucent,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: math.max(openH, HabitSheet.closedHeight) - 3,
            child: Column(
              children: [
                Semantics(
                  button: true,
                  label: _open ? '시트 접기' : '시트 펼치기',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    child: SizedBox(
                      height: 24,
                      width: double.infinity,
                      child: Center(child: Container(width: 46, height: 5, color: AppColors.sheetHandle)),
                    ),
                  ),
                ),
                if (!_open)
                  _Summary(s: s, pct: pct, onTap: _toggle)
                else
                  Expanded(child: _pages(s, pct)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pages(GameState s, double pct) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              for (final (i, label) in const [(0, '습관 리스트'), (1, '오늘의 성실도')]) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _page = i),
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _page == i ? AppColors.introFloor : AppColors.nightDeep,
                        border: Border.all(color: _page == i ? AppColors.purple : AppColors.nightLine, width: 3),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 11.5, color: _page == i ? AppColors.text : AppColors.textMuted)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            return ClipRect(
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    left: _page == 0 ? 0 : -w,
                    top: 0,
                    bottom: 0,
                    width: w * 2,
                    child: Row(
                      children: [
                        SizedBox(width: w, child: _HabitList(s: s, onGoChat: widget.onGoChat)),
                        SizedBox(width: w, child: _ScorePage(s: s, pct: pct)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// "오늘의 성실도" 옆 ? 버튼: 성실도가 무엇이고 어디에 쓰이는지.
class SincerityHelp extends StatelessWidget {
  const SincerityHelp({super.key});

  @override
  Widget build(BuildContext context) {
    return const HelpButton(title: '성실도란?', items: [
      ('성실도가 뭐예요?', '오늘 습관을 얼마나 지켰는지 보여주는 점수예요. 챗봇에서 오늘 습관을 체크하면 쌓여요.'),
      (
        '어떻게 정해져요?',
        '목표에 가까울수록 점수가 높고, 습관 하나에 최대 ${Economy.maxSincerityPerHabit}점이에요. '
            '점수가 높은 습관 ${Economy.dailyHabitCap}개만 더해서 하루에 최대 ${GameState.maxDailyScore}점까지 받아요.'
      ),
      (
        '어디에 쓰여요?',
        '성실도 1점마다 ${Economy.goldPerSincerity}골드를 받아요. 카테고리 레벨도 함께 올라서, '
            '레벨이 오르면 ${Economy.categoryLevelUpGold}골드를 받고 탐색에서 새로운 몬스터를 만날 수 있어요.'
      ),
    ]);
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.pct, required this.color, this.height = 10, this.border = 2, this.bg = AppColors.nightRaised});
  final double pct;
  final Color color;
  final double height;
  final double border;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(color: bg, border: Border.all(color: AppColors.nightLine2, width: border)),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(widthFactor: pct.clamp(0.0, 1.0), heightFactor: 1, child: ColoredBox(color: color)),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.s, required this.pct, required this.onTap});
  final GameState s;
  final double pct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final countable = s.activeHabits.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text('오늘의 성실도 · 습관 ${s.checkedCount}/$countable 체크',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ),
                      const SizedBox(width: 2),
                      const SincerityHelp(),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${s.todayScore}'),
                    const TextSpan(
                        text: ' / ${GameState.maxDailyScore}',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w400, color: AppColors.textMuted)),
                  ]),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.gold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ProgressBar(pct: pct, color: AppColors.gold),
            const SizedBox(height: 8),
            const Text('위로 밀어 습관 리스트 보기', style: TextStyle(fontSize: 9.5, color: AppColors.lavender)),
          ],
        ),
      ),
    );
  }
}

class _HabitList extends StatelessWidget {
  const _HabitList({required this.s, required this.onGoChat});
  final GameState s;
  final VoidCallback onGoChat;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      children: [
        for (var i = 0; i < s.habits.length; i++) ...[
          _HabitRow(s: s, habit: s.habits[i], counted: !s.checkedInToday || s.isCounted(s.habits[i])),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        Semantics(
          button: true,
          child: GestureDetector(
            onTap: onGoChat,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              margin: const EdgeInsets.only(right: 4, bottom: 4),
              padding: const EdgeInsets.all(12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.gold,
                border: Border.all(color: AppColors.goldLight, width: 3),
                boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(4, 4))],
              ),
              child: Text(s.checkedInToday ? '오늘 체크 완료 · 탐색하러 가기' : '챗봇에게 오늘 습관 체크받기',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.night)),
            ),
          ),
        ),
      ],
    );
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow({required this.s, required this.habit, required this.counted});
  final GameState s;
  final Habit habit;
  final bool counted;

  @override
  Widget build(BuildContext context) {
    final m = s.measureOf(habit);
    final v = s.todayRecords[habit.id];
    // 값은 최신 기록, +점수는 보상에 쓰인 첫 확정 점수 (다시 체크해도 보상은 그대로)
    final score = s.rewardedScoreOf(habit) ?? 0;
    final meta = '${m.label}${m.isOX ? ' · O/X' : ' · 목표 ${formatNum(habit.target)}${m.unit}'}'
        ' · ${Catalog.periods[habit.periodIndex].$1} ${Catalog.periodMult(habit.periodIndex)}';
    final String state;
    if (v != null && !counted) {
      state = '반영 안 됨 (상위 ${Economy.dailyHabitCap}개 밖)';
    } else if (v == null) {
      state = '미체크';
    } else {
      final value = m.isOX ? (v > 0 ? '완료' : '못 함') : '${formatNum(v)}${m.unit}';
      state = '$value · +$score';
    }
    final stateColor = v == null ? AppColors.lavender : (score > 0 ? AppColors.gold : AppColors.orange);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.nightPanel,
        border: Border.all(color: AppColors.nightLine, width: 3),
      ),
      child: Row(
        children: [
          CategoryIcon(habit.categoryId, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(habit.name, style: const TextStyle(fontSize: 12, color: AppColors.text)),
                const SizedBox(height: 4),
                Text(meta, style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(state, textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, color: stateColor)),
        ],
      ),
    );
  }
}

class _ScorePage extends StatelessWidget {
  const _ScorePage({required this.s, required this.pct});
  final GameState s;
  final double pct;

  @override
  Widget build(BuildContext context) {
    final score = s.todayScore;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.nightPanel,
            border: Border.all(color: AppColors.nightLine, width: 3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Text('오늘의 성실도', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                  SizedBox(width: 2),
                  SincerityHelp(),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$score',
                      style: const TextStyle(fontSize: 34, height: 1.1, fontWeight: FontWeight.w700, color: AppColors.gold)),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('/ ${GameState.maxDailyScore} · 획득 ${score * Economy.goldPerSincerity}G',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _ProgressBar(pct: pct, color: AppColors.gold, height: 12, border: 3, bg: AppColors.nightDeep),
            ],
          ),
        ),
        for (final h in s.countedHabits) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(h.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.text)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProgressBar(
                  pct: (s.rewardedScoreOf(h) ?? 0) / Economy.maxSincerityPerHabit,
                  color: Catalog.category(h.categoryId).color,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 40,
                child: Text('${s.rewardedScoreOf(h) ?? 0}/${Economy.maxSincerityPerHabit}',
                    textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        const CustomPaint(
          foregroundPainter: DashedBorderPainter(color: AppColors.nightLine2, width: 3, dash: 6, gap: 3),
          child: Padding(
            padding: EdgeInsets.all(13),
            child: Text(
              '성실도 1 = ${Economy.goldPerSincerity}G · 점수가 높은 습관 ${Economy.dailyHabitCap}개만 반영, 하루 ${GameState.maxDailyScore}G까지',
              style: TextStyle(fontSize: 10, height: 1.8, color: AppColors.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}
