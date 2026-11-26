import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../data/catalog.dart';
import '../../core/widgets/help_button.dart';
import '../../core/widgets/category_icon.dart';
import '../../data/models.dart';
import 'home_parts.dart';
import '../../core/theme/app_theme.dart';

/// 홈 아래 슬라이드 시트. 접히면 손잡이 + 오늘의 성실도 막대만 (글자 없이, 11-12), 펼치면 오늘의 성실도.
/// 습관 리스트는 하단 가운데 습관 탭으로 옮겼다 (기획 2026-11-25-습관-탭-목표-제거).
class HabitSheet extends StatefulWidget {
  const HabitSheet({super.key, required this.maxHeight});

  /// 홈 본문 높이 (펼친 높이가 넘지 않게).
  final double maxHeight;

  static const double closedHeight = 70; // 테두리 4 + 손잡이 24 + 총점 막대 8 + 6 + 습관별 작은 막대 줄 18 + 아래 여백 10 (11-26)
  static const double openHeight = 310; // 성실도 카드 + 반영 습관 3줄 + 안내 (습관 리스트를 탭으로 옮겨 470 → 310)

  @override
  State<HabitSheet> createState() => _HabitSheetState();
}

class _HabitSheetState extends State<HabitSheet> {
  bool _open = false;

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
      decoration: BoxDecoration(
        color: AppColors.nightDeep,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purple, width: 2),
      ),
      child: GestureDetector(
        onVerticalDragEnd: _onDrag,
        behavior: HitTestBehavior.translucent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: math.max(openH, HabitSheet.closedHeight) - 4, // 위아래 테두리 2 + 2
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
                  Expanded(child: _ScorePage(s: s, pct: pct)),
              ],
            ),
          ),
        ),
      ),
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

/// 접힌 시트: 글자 없이 오늘의 성실도 막대만. 읽기 도우미에는 점수 · 체크 수를 말로 알린다.
class _Summary extends StatelessWidget {
  const _Summary({required this.s, required this.pct, required this.onTap});
  final GameState s;
  final double pct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '오늘의 성실도 ${s.todayScore}/${GameState.maxDailyScore}, '
          '습관 ${s.checkedCount}/${s.activeHabits.length} 체크. 눌러서 성실도 자세히 보기',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('habit-sheet-summary'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Column(
            children: [
              _ProgressBar(pct: pct, color: AppColors.gold, height: 8),
              const SizedBox(height: 6),
              // 습관마다 작은 막대 (분야 아이콘 + 받은 점수 / 25) — 접힌 채로도 무엇을 했는지 (11-26)
              Row(
                children: [
                  for (var i = 0; i < s.activeHabits.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: _MiniHabitBar(s: s, habit: s.activeHabits[i])),
                  ],
                ],
              ),
            ],
          ),
        ),
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
                      style: const TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 34, height: 1.1, fontWeight: FontWeight.w700, color: AppColors.gold)),
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

/// 접힌 시트의 습관 하나: 분야 아이콘 + 얇은 막대 (체크 전이면 빈 막대).
class _MiniHabitBar extends StatelessWidget {
  const _MiniHabitBar({required this.s, required this.habit});
  final GameState s;
  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final score = s.rewardedScoreOf(habit) ?? 0;
    return Row(
      children: [
        CategoryIcon(habit.categoryId, size: 16, outline: 0),
        const SizedBox(width: 4),
        Expanded(
          child: _ProgressBar(
            pct: score / Economy.maxSincerityPerHabit,
            color: Catalog.category(habit.categoryId).color,
            height: 6,
            border: 1.5,
          ),
        ),
      ],
    );
  }
}
