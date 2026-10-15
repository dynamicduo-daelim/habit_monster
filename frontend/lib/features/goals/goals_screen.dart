import 'package:flutter/material.dart';

import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/models.dart';
import '../../data/pixel_icons.dart';
import '../home/home_parts.dart' show CoinIcon, DashedBorderPainter;
import '../shell/game_action.dart';
import '../shell/main_shell.dart';

/// 목표 체크리스트: 주간(3칸 · +40G) · 월간(1칸 · +150G).
/// 카드를 누르면 달성 체크, 연필로 수정 · 삭제, 4번째 주간 칸은 유료 · 기록용.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

/// 주간 · 월간 목표 색 (온보딩 보상표와 같은 하늘색 · 노란색).
class _TierColors {
  const _TierColors(this.ribbon, this.card, this.shadow, this.addText);
  final Color ribbon; // 섹션 이름표 · 점선 버튼 · 폼 배지
  final Color card; // 아직 안 한 목표 카드
  final Color shadow; // 카드 그림자
  final Color addText;

  static const weekly =
      _TierColors(AppColors.skyCardSelShadow, AppColors.skyCard, AppColors.skyCardShadow, AppColors.skyCard);
  static const monthly = _TierColors(AppColors.goldDeep, AppColors.butter, AppColors.yellowShadow, AppColors.butter);

  static _TierColors of(GoalTier t) => t == GoalTier.weekly ? weekly : monthly;
}

class _GoalsScreenState extends State<GoalsScreen> {
  /// 작성 중인 칸 (null이면 폼 닫힘). [_editing]이 있으면 수정, 없으면 새 목표.
  GoalTier? _draftTier;
  Goal? _editing;
  final _title = TextEditingController();
  final _detail = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _detail.dispose();
    super.dispose();
  }

  void _openDraft(GoalTier tier, [Goal? g]) {
    setState(() {
      _draftTier = tier;
      _editing = g;
      _title.text = g?.title ?? '';
      _detail.text = g?.detail ?? '';
    });
  }

  void _closeDraft() => setState(() {
        _draftTier = null;
        _editing = null;
      });

  Future<void> _save(GameState s) async {
    final shell = MainShell.of(context);
    final t = _title.text.trim();
    if (t.isEmpty) {
      shell.toast('목표를 적어주세요');
      return;
    }
    final d = _detail.text.trim();
    final editing = _editing;
    final tier = _draftTier!;
    final ok = await runGameAction(context, (r) async {
      if (editing != null) {
        await r.updateGoal(editing, t, d);
      } else {
        await r.addGoal(tier, t, d);
      }
      return true;
    });
    if (ok != true || !mounted) return;
    if (editing != null) shell.toast('목표를 고쳤어요');
    _closeDraft();
  }

  Future<void> _delete(GameState s) async {
    final shell = MainShell.of(context);
    final ok = await runGameAction(context, (r) => r.deleteGoal(_editing!));
    if (ok == null || !mounted) return;
    if (!ok) {
      shell.toast('완료한 목표는 지울 수 없어요');
      return;
    }
    shell.toast('목표를 지웠어요');
    _closeDraft();
  }

  /// 달성 체크. 완료한 목표는 되돌릴 수 없다 (DB Q-5).
  Future<void> _toggle(GameState s, Goal g) async {
    final shell = MainShell.of(context);
    final ok = await runGameAction(context, (r) => r.completeGoal(g));
    if (ok == null || !mounted) return;
    if (!ok) {
      shell.toast('완료한 목표는 되돌릴 수 없어요');
      return;
    }
    shell.toast('+${g.reward}', coin: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      children: [
        _section(s, GoalTier.weekly),
        const SizedBox(height: 18),
        _section(s, GoalTier.monthly),
      ],
    );
  }

  Widget _section(GameState s, GoalTier tier) {
    final weekly = tier == GoalTier.weekly;
    final list = s.goalsOf(tier);
    final cap = s.capOf(tier);
    final drafting = _draftTier == tier;
    final colors = _TierColors.of(tier);
    final canAdd = _draftTier == null && list.length < cap;
    final locked = weekly && !s.extraWeeklySlot && list.length >= Economy.weeklyGoalSlots && _draftTier == null;

    final children = <Widget>[
      Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: colors.ribbon, border: Border.all(color: AppColors.ink, width: 3)),
            child: Text(weekly ? '주간 목표' : '월간 목표',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                  shadows: [Shadow(color: AppColors.ink, offset: Offset(1, 1))],
                )),
          ),
          const SizedBox(width: 8),
          Text('${list.length}/$cap', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.yellowButton,
              border: Border.all(color: AppColors.ink, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CoinIcon(size: 11),
                const SizedBox(width: 4),
                Text(weekly ? '개당 +${Economy.weeklyGoalGold}G' : '+${Economy.monthlyGoalGold}G',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.brownText)),
              ],
            ),
          ),
        ],
      ),
      for (final g in list)
        _GoalCard(goal: g, colors: colors, onToggle: () => _toggle(s, g), onEdit: () => _openDraft(tier, g)),
      if (drafting) _draftForm(s, colors),
      if (canAdd)
        _DashedButton(
          color: colors.ribbon,
          textColor: colors.addText,
          label: '+ 목표 추가 · 빈 슬롯 ${cap - list.length}칸',
          onTap: () => _openDraft(tier),
        ),
      if (locked)
        Semantics(
          button: true,
          child: GestureDetector(
            onTap: () async {
              await runGameAction(context, (r) => r.unlockExtraWeeklySlot());
              if (mounted) MainShell.of(context).toast('결제 화면 자리 · 슬롯 +1');
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.introFloor,
                border: Border.all(color: AppColors.gold, width: 3),
              ),
              child: const Text('슬롯 추가 열기 (유료 · 기록용)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.goldLight)),
            ),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 9),
          children[i],
        ],
      ],
    );
  }

  Widget _draftForm(GameState s, _TierColors colors) {
    InputDecoration deco(String hint) => InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.brownMuted),
          filled: true,
          fillColor: AppColors.parchment,
          contentPadding: const EdgeInsets.all(10),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppColors.ink, width: 3),
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppColors.ink, width: 3),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppColors.ink, width: 3),
          ),
        );
    const label = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.brownMuted);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cream,
        border: Border.all(color: AppColors.ink, width: 3),
        boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: colors.ribbon, border: Border.all(color: AppColors.ink, width: 2)),
              child: Text(_editing != null ? '목표 수정' : '새 목표',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.white)),
            ),
          ),
          const SizedBox(height: 9),
          const Text('목표', style: label),
          const SizedBox(height: 5),
          TextField(
            controller: _title,
            cursorColor: AppColors.brownText,
            style: const TextStyle(fontSize: 12, color: AppColors.brownText),
            decoration: deco('예: 주 3회 러닝'),
          ),
          const SizedBox(height: 9),
          const Text('상세 내용', style: label),
          const SizedBox(height: 5),
          TextField(
            controller: _detail,
            minLines: 3,
            maxLines: 3,
            cursorColor: AppColors.brownText,
            style: const TextStyle(fontSize: 11.5, height: 1.7, color: AppColors.brownText),
            decoration: deco('언제, 얼마나, 어떻게 할지 적어두세요'),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              if (_editing != null && !_editing!.done) ...[
                SizedBox(
                  width: 58,
                  child: PixelButton(
                    label: '삭제',
                    onPressed: () => _delete(s),
                    height: 42,
                    depth: 3,
                    fontSize: 11,
                    color: AppColors.redSoft,
                    shadowColor: AppColors.redShadow,
                    textColor: AppColors.white,
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              SizedBox(
                width: 60,
                child: PixelButton(
                  label: '취소',
                  onPressed: _closeDraft,
                  height: 42,
                  depth: 3,
                  fontSize: 11,
                  color: AppColors.parchment,
                  shadowColor: AppColors.parchmentShadow,
                  textColor: AppColors.brownText,
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PixelButton(label: '저장', onPressed: () => _save(s), height: 42, depth: 3, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.colors, required this.onToggle, required this.onEdit});
  final Goal goal;
  final _TierColors colors;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final g = goal;
    final done = g.done;
    return Container(
      decoration: BoxDecoration(
        color: done ? AppColors.goalDoneCard : colors.card,
        border: Border.all(color: AppColors.ink, width: 3),
        boxShadow: [BoxShadow(color: done ? AppColors.ink : colors.shadow, offset: const Offset(0, 4))],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Semantics(
                button: true,
                checked: done,
                label: '${g.title} 달성 체크',
                excludeSemantics: true,
                onTap: onToggle,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 11, 6, 11),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          margin: const EdgeInsets.only(top: 1),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: done ? AppColors.green : AppColors.white,
                            border: Border.all(color: AppColors.ink, width: 3),
                          ),
                          child: done
                              ? const PixelIcon(
                                  layers: [PixelLayer(PixelIcons.checkStroke, AppColors.brownText)],
                                  size: 12,
                                  strokeWidth: 3.5,
                                )
                              : null,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(g.title,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: done ? AppColors.disabledText : AppColors.brownText,
                                    decoration: done ? TextDecoration.lineThrough : null,
                                    decorationColor: AppColors.disabledText,
                                  )),
                              const SizedBox(height: 5),
                              Text(g.detail.isEmpty ? '상세 내용 없음 · 연필을 눌러 적어보세요' : g.detail,
                                  style: const TextStyle(fontSize: 10, height: 1.7, color: AppColors.brownMuted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 11),
                        Opacity(
                          opacity: done ? 1 : 0.7,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: done ? AppColors.yellowButton : AppColors.cream,
                              border: Border.all(color: done ? AppColors.ink : AppColors.goalTagBorder, width: 2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CoinIcon(size: 12),
                                const SizedBox(width: 3),
                                Text('+${g.reward}',
                                    style: const TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: '목표 수정',
              child: GestureDetector(
                onTap: onEdit,
                child: Container(
                  width: 42,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.parchment,
                    border: Border(left: BorderSide(color: AppColors.ink, width: 3)),
                  ),
                  child: const PixelIcon(layers: PixelIcons.pencil, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 점선 "+ 목표 추가" 버튼 (주간 · 월간 색).
class _DashedButton extends StatelessWidget {
  const _DashedButton({required this.label, required this.onTap, required this.color, required this.textColor});
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: DashedBorderPainter(color: color, width: 3, dash: 9, gap: 4),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(10),
            child: Text(label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textColor)),
          ),
        ),
      ),
    );
  }
}
