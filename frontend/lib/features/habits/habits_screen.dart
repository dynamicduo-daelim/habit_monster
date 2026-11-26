import 'package:flutter/material.dart';

import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/pixel_icons.dart';
import '../home/habit_manage_screen.dart';
import '../home/habit_sheet.dart' show SincerityHelp;
import '../shell/main_shell.dart';

/// 하단 가운데 "습관" 탭: 오늘 습관을 한눈에.
/// 위에서부터 제목 + [+ 새 습관] → 체크 수 · 성실도 → 챗봇 체크받기(파트너 그림) → 습관마다 한 줄(체크 상태는 아이콘).
/// 목표 탭 자리를 대신한다 (기획 2026-11-25-습관-탭-목표-제거 · 11-26 다듬기).
class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final shell = MainShell.maybeOf(context);
    Future<void> add() async {
      final msg = await HabitManageScreen.open(context);
      if (msg != null) shell?.toast(msg);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('오늘의 습관',
                  style: TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.text)),
            ),
            _NewHabitButton(onTap: add),
          ],
        ),
        const SizedBox(height: 12),
        _TodayCard(s: s),
        // 챗봇 체크를 마치면 버튼을 없앤다 (사용자 요청 10-29)
        if (!s.checkedInToday && s.habits.isNotEmpty && shell != null) ...[
          const SizedBox(height: 12),
          _ChatCheckButton(s: s, onTap: () => shell.goTab(MainShell.chatTab)),
        ],
        const SizedBox(height: 14),
        if (s.habits.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('아직 습관이 없어요', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          )
        else
          for (final h in s.habits) ...[
            HabitRow(s: s, habit: h, counted: !s.checkedInToday || s.isCounted(h)),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

/// 오른쪽 위 "+ 새 습관" (금색 작은 버튼).
class _NewHabitButton extends StatelessWidget {
  const _NewHabitButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '새 습관',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.goldLight, width: 2),
            boxShadow: const [BoxShadow(color: AppColors.goldShadow, offset: Offset(0, 3))],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PixelIcon(layers: [PixelLayer(PixelIcons.plus, AppColors.night)], size: 14),
              SizedBox(width: 6),
              Text('새 습관', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.night)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 체크 수 · 오늘의 성실도.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.s});
  final GameState s;

  @override
  Widget build(BuildContext context) {
    final score = s.todayScore;
    final pct = (score / GameState.maxDailyScore).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.nightPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.nightLine, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('오늘의 성실도', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              const SizedBox(width: 2),
              const SincerityHelp(),
              const Spacer(),
              Text('${s.checkedCount} / ${s.activeHabits.length} 체크',
                  style: const TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 13, color: AppColors.gold)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(color: AppColors.nightDeep, border: Border.all(color: AppColors.nightLine2, width: 3)),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(widthFactor: pct, heightFactor: 1, child: const ColoredBox(color: AppColors.gold)),
                ),
              ),
              const SizedBox(width: 10),
              Text('$score / ${GameState.maxDailyScore} · ${score * Economy.goldPerSincerity}G',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// "챗봇에게 오늘 습관 체크받기": 대화 상대 몬스터 그림 + 말풍선 아이콘.
class _ChatCheckButton extends StatelessWidget {
  const _ChatCheckButton({required this.s, required this.onTap});
  final GameState s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = s.monsterByUid(s.chatPartnerUid) ?? s.monsters.firstOrNull;
    final sp = p == null ? null : Catalog.speciesById(p.speciesId);
    return Semantics(
      button: true,
      label: '챗봇에게 오늘 습관 체크받기',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.goldLight, width: 3),
            boxShadow: const [BoxShadow(color: AppColors.goldShadow, offset: Offset(0, 4))],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.butter,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.ink, width: 2),
                ),
                child: sp == null
                    ? const PixelIcon(layers: [PixelLayer(PixelIcons.checkStroke, AppColors.ink)], size: 22, strokeWidth: 3)
                    : PixelImage(sp.assetAt(p!.level), height: 40),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('오늘 습관 체크받기',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.night)),
                    const SizedBox(height: 2),
                    Text('${sp?.name ?? '루틴몬'}에게 오늘 한 걸 알려 줘요',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.brownText)),
                  ],
                ),
              ),
              PixelIcon(layers: [PixelLayer(PixelIcons.nav[1], AppColors.night)], size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// 습관 한 줄: 아이콘 · 이름 · 하루 목표, 오른쪽에 오늘 상태 아이콘(빈 칸 = 미체크, 초록 체크 = 했음, 회색 체크 = 반영 안 됨).
class HabitRow extends StatelessWidget {
  const HabitRow({super.key, required this.s, required this.habit, required this.counted});
  final GameState s;
  final Habit habit;

  /// 오늘 성실도에 반영되는지 (상위 [Economy.dailyHabitCap]개 안).
  final bool counted;

  @override
  Widget build(BuildContext context) {
    final m = s.measureOf(habit);
    final v = s.todayRecords[habit.id];
    // 값은 최신 기록, +점수는 보상에 쓰인 첫 확정 점수 (다시 체크해도 보상은 그대로)
    final score = s.rewardedScoreOf(habit) ?? 0;
    final goal = m.isOX ? '매일 했다 / 못 했다' : '하루 ${formatNum(habit.target)}${m.unit}';
    // 방금 등록한 습관: 금색 테두리 + NEW (기획 2026-11-26)
    final isNew = s.lastAddedHabitId == habit.id;

    final _CheckState st;
    final String? note; // 아이콘 옆 작은 글자 (값 · 점수)
    if (v == null) {
      st = _CheckState.todo;
      note = isNew ? (s.checkedInToday ? '내일부터' : '오늘부터') : null;
    } else if (!counted) {
      st = _CheckState.notCounted;
      note = '반영 안 됨';
    } else if (m.isOX ? v <= 0 : score <= 0) {
      st = _CheckState.missed;
      note = m.isOX ? null : '${formatNum(v)}${m.unit}';
    } else {
      st = _CheckState.done;
      note = m.isOX ? '+$score' : '${formatNum(v)}${m.unit} · +$score';
    }
    final label = switch (st) {
      _CheckState.todo => '미체크',
      _CheckState.done => '체크 완료',
      _CheckState.missed => '못 함',
      _CheckState.notCounted => '반영 안 됨',
    };
    return Semantics(
      label: '${habit.name}, $goal, $label${note != null && st == _CheckState.done ? ' $note' : ''}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: isNew ? AppColors.nightRaised : AppColors.nightPanel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isNew ? AppColors.gold : AppColors.nightLine, width: 3),
        ),
        child: Row(
          children: [
            CategoryIcon(habit.categoryId, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(habit.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                      ),
                      if (isNew) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          color: AppColors.gold,
                          child: const Text('NEW',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(goal, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
            if (note != null) ...[
              Text(note,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: st == _CheckState.done ? AppColors.gold : AppColors.purpleSoft)),
              const SizedBox(width: 8),
            ],
            _CheckBox(state: st),
          ],
        ),
      ),
    );
  }
}

enum _CheckState { todo, done, missed, notCounted }

/// 오늘 상태 아이콘 (32px): 빈 칸 · 초록 체크 · 주황 X · 회색 체크.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.state});
  final _CheckState state;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color line, String? path, Color ink) = switch (state) {
      _CheckState.todo => (AppColors.nightDeep, AppColors.nightLine2, null, AppColors.ink),
      _CheckState.done => (AppColors.green, AppColors.ink, PixelIcons.checkStroke, AppColors.ink),
      _CheckState.missed => (AppColors.orange, AppColors.ink, 'M4 4l8 8 M12 4l-8 8', AppColors.ink),
      _CheckState.notCounted => (AppColors.nightLine2, AppColors.ink, PixelIcons.checkStroke, AppColors.textMuted),
    };
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: line, width: 3),
      ),
      child: path == null ? null : PixelIcon(layers: [PixelLayer(path, ink)], size: 16, strokeWidth: 3.5),
    );
  }
}
