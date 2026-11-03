import 'package:flutter/material.dart';

import '../../core/constants/economy.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/pixel_icons.dart';
import 'onboarding_controller.dart';
import 'onboarding_parts.dart';
import '../../core/theme/app_theme.dart';

/// 온보딩 2단계: 습관 퀘스트 만들기. 무엇을 → 얼마나 → 언제까지 순서로 한 단계씩.
class StepHabits extends StatelessWidget {
  const StepHabits({super.key, required this.c});
  final OnboardingController c;

  static const _profLines = [
    '어떤 습관을 키워보겠나? 추천을 고르거나 직접 적어보게!',
    '좋아! 하루에 얼마나 할지 정해보세.',
    '마지막이네! 오래 지킬수록 보물상자가 커진다네.',
  ];

  @override
  Widget build(BuildContext context) {
    final has = c.habits.isNotEmpty;
    return OnboardingFrame(
      bottom: PixelButton(
        label: has ? '모험 시작 ▶' : '퀘스트를 1개 이상 등록해 주세요',
        onPressed: has ? c.finishHabits : null,
        disabledColor: AppColors.nightLine2,
        disabledShadowColor: AppColors.ink,
        disabledTextColor: AppColors.night,
      ),
      children: [
        const StepHeader(step: 2, title: '습관 퀘스트 만들기'),
        ProfessorTip(text: _profLines[c.habStep]),
        _QuestForm(c: c),
        if (has)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('등록한 퀘스트 · ${c.habits.length}개',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.purpleSoft)),
                for (final h in c.habits) ...[
                  const SizedBox(height: 7),
                  _HabitRow(habit: h, onRemove: () => c.removeHabit(h)),
                ],
              ],
            ),
          ),
        const Text('퀘스트는 최대 ${Economy.maxActiveHabits}개 · 하루 성실도에는 점수가 높은 ${Economy.dailyHabitCap}개가 반영돼요.',
            style: TextStyle(fontSize: 9.5, height: 1.8, color: AppColors.textMuted)),
      ],
    );
  }
}

class _QuestForm extends StatelessWidget {
  const _QuestForm({required this.c});
  final OnboardingController c;

  @override
  Widget build(BuildContext context) {
    final step = c.habStep;
    final nextOn = step != 0 || c.hasDraftName;
    return RibbonPanel(
      title: '새 습관 퀘스트',
      gap: 12,
      children: [
        _StepTabs(step: step),
        if (step == 0) ..._what(),
        if (step == 1) ..._howMuch(),
        if (step == 2) ..._until(),
        Row(
          children: [
            if (step > 0) ...[
              SizedBox(
                width: 84,
                child: PixelButton(
                  label: '◀ 이전',
                  onPressed: c.habPrev,
                  color: AppColors.parchment,
                  shadowColor: AppColors.parchmentShadow,
                  textColor: AppColors.brownText,
                  height: 48,
                  depth: 4,
                  fontSize: 12,
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: PixelButton(
                label: step == 2 ? '퀘스트 등록!' : '다음 ▶',
                onPressed: nextOn && (step != 2 || c.canAddHabit) ? c.habNext : null,
                color: AppColors.yellowButton,
                shadowColor: AppColors.yellowShadow,
                textColor: AppColors.brownText,
                disabledTextColor: AppColors.brownText,
                height: 48,
                depth: 4,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 1. 무엇을 — 카테고리 · 추천 목록 · 직접 쓰기
  List<Widget> _what() {
    final cat = c.draftCat;
    return [
      Row(
        children: [
          for (var i = 0; i < c.picked.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: _DraftCategoryButton(c: c, id: c.picked[i])),
          ],
        ],
      ),
      if (cat != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, p) in (Catalog.habitPresets[cat.id] ?? const <(String, int, double)>[]).indexed) ...[
              if (i > 0) const SizedBox(height: 6),
              _PresetRow(
                label: p.$1,
                hint: cat.measures[p.$2].isOX ? 'O/X' : '${formatNum(p.$3)}${cat.measures[p.$2].unit}',
                on: c.draftName.text == p.$1,
                onTap: () => c.pickPreset(p),
              ),
            ],
          ],
        ),
      _DashedBox(
        child: Row(
          children: [
            const Text('직접 쓰기',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.brownMuted)),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Semantics(
                  label: '습관 이름',
                  child: TextField(
                    controller: c.draftName,
                    cursorColor: AppColors.brownText,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brownText),
                    decoration: pixelInputDecoration('예: 저녁 산책'),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => c.habNext(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// 2. 얼마나 — 측정 방식 · 하루 목표
  List<Widget> _howMuch() {
    final cat = c.draftCat!;
    final measure = c.draftMeasureInfo!;
    return [
      Text(c.draftName.text.trim(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.brownText)),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < cat.measures.length; i++)
            PressCard(
              onTap: () => c.pickMeasure(i),
              color: c.draftMeasure == i ? AppColors.skyCard : AppColors.white,
              depth: 0,
              minHeight: 34,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              child: Text('${cat.measures[i].label} · ${cat.measures[i].isOX ? 'O/X' : cat.measures[i].unit}',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.brownText)),
            ),
        ],
      ),
      if (c.draftNeedsTarget)
        Column(
          children: [
            const Text('하루에 얼마나?', style: TextStyle(fontSize: 10.5, color: AppColors.brownMuted)),
            const SizedBox(height: 6),
            _TargetStepper(c: c, unit: measure.unit),
          ],
        ),
      if (c.draftIsOX)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), 
            color: AppColors.parchment,
            border: Border.all(color: AppColors.ink, width: 3),
          ),
          child: const Text('했으면 O, 못 했으면 X\n매일 챗봇이 물어볼게요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, height: 1.7, color: AppColors.brownText)),
        ),
    ];
  }

  /// 3. 언제까지 — 기간(보상 상자) · 퀘스트 요약
  List<Widget> _until() {
    final cat = c.draftCat!;
    final m = c.draftMeasureInfo!;
    final amount = m.isOX ? '${m.label} O/X' : '${m.label} ${formatNum(c.draftTarget)}${m.unit}';
    final period = '${Catalog.periods[c.draftPeriod].$1} ${Catalog.periodMult(c.draftPeriod)}';
    return [
      Row(
        children: [
          for (var i = 0; i < Catalog.periods.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _PeriodButton(c: c, index: i)),
          ],
        ],
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), 
          color: AppColors.brownText,
          border: Border.all(color: AppColors.ink, width: 3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('퀘스트 요약', style: TextStyle(fontSize: 9.5, color: AppColors.purpleSoft)),
            const SizedBox(height: 4),
            Text(c.draftName.text.trim(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.butter)),
            const SizedBox(height: 4),
            Text('${cat.name} · $amount · $period',
                style: const TextStyle(fontSize: 10.5, color: AppColors.parchment)),
          ],
        ),
      ),
    ];
  }
}

/// 1. 무엇을 · 2. 얼마나 · 3. 언제까지 진행 막대.
class _StepTabs extends StatelessWidget {
  const _StepTabs({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    const labels = OnboardingController.habStepLabels;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), 
                    color: i <= step ? AppColors.gold : AppColors.disabled,
                    border: Border.all(color: AppColors.ink, width: 2),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${i + 1}. ${labels[i]}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: i == step ? AppColors.brownText : AppColors.slotStepOff,
                    )),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DraftCategoryButton extends StatelessWidget {
  const _DraftCategoryButton({required this.c, required this.id});
  final OnboardingController c;
  final String id;

  @override
  Widget build(BuildContext context) {
    final cat = Catalog.category(id);
    final cur = c.draftCategory == id;
    return PressCard(
      onTap: () => c.pickDraftCategory(id),
      sunk: cur,
      sinkBy: 3,
      depth: 4,
      color: cur ? AppColors.butter : AppColors.parchment,
      shadowColor: AppColors.tanShadow,
      minHeight: 44,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      semanticLabel: cat.name,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CategoryIcon(id, size: 18, outline: 0),
          const SizedBox(width: 5),
          Text(cat.short, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brownText)),
        ],
      ),
    );
  }
}

/// 추천 습관 한 줄: 이름 · 기본 목표 · ▶
class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.label, required this.hint, required this.on, required this.onTap});
  final String label;
  final String hint;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressCard(
      onTap: onTap,
      color: on ? AppColors.butter : AppColors.white,
      depth: 0,
      minHeight: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brownText)),
          ),
          const SizedBox(width: 8),
          Text(hint, style: const TextStyle(fontSize: 10, color: AppColors.brownMuted)),
          const SizedBox(width: 8),
          const Text('▶', style: TextStyle(fontSize: 12, color: AppColors.red)),
        ],
      ),
    );
  }
}

/// 점선 테두리 상자 (직접 쓰기 칸).
class _DashedBox extends StatelessWidget {
  const _DashedBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DashedBorderPainter(),
      child: Container(
        color: AppColors.parchment,
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  static const double _w = 3;
  static const double _dash = 9;
  static const double _gap = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.ink;
    void hLine(double y) {
      for (var x = 0.0; x < size.width; x += _dash + _gap) {
        canvas.drawRect(Rect.fromLTWH(x, y, (size.width - x).clamp(0, _dash), _w), paint);
      }
    }

    void vLine(double x) {
      for (var y = 0.0; y < size.height; y += _dash + _gap) {
        canvas.drawRect(Rect.fromLTWH(x, y, _w, (size.height - y).clamp(0, _dash)), paint);
      }
    }

    hLine(0);
    hLine(size.height - _w);
    vLine(0);
    vLine(size.width - _w);
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}

class _TargetStepper extends StatelessWidget {
  const _TargetStepper({required this.c, required this.unit});
  final OnboardingController c;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: PixelButton(
            label: '−',
            semanticLabel: '목표 줄이기',
            onPressed: c.decTarget,
            color: AppColors.skyCard,
            shadowColor: AppColors.skyCardShadow,
            textColor: AppColors.brownText,
            height: 52,
            depth: 4,
            fontSize: 24,
            padding: EdgeInsets.zero,
            // Galmuri에 '−' 글자가 없어서 막대로 그린다.
            child: Container(width: 14, height: 4, color: AppColors.brownText),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 52,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), 
              color: AppColors.brownText,
              border: Border.all(color: AppColors.ink, width: 3),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(formatNum(c.draftTarget),
                    style: const TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.butter)),
                const SizedBox(width: 6),
                Text(unit, style: const TextStyle(fontSize: 13, color: AppColors.parchment)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          child: PixelButton(
            label: '+',
            semanticLabel: '목표 늘리기',
            onPressed: c.incTarget,
            color: AppColors.yellowButton,
            shadowColor: AppColors.yellowShadow,
            textColor: AppColors.brownText,
            height: 52,
            depth: 4,
            fontSize: 24,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({required this.c, required this.index});
  final OnboardingController c;
  final int index;

  static const _chestSizes = [26.0, 30.0, 34.0];

  @override
  Widget build(BuildContext context) {
    final on = c.draftPeriod == index;
    final (lid, body, band) = PixelIcons.chestColors[index];
    return PressCard(
      onTap: () => c.pickPeriod(index),
      sunk: on,
      sinkBy: 3,
      depth: 4,
      color: on ? AppColors.butter : AppColors.parchment,
      shadowColor: AppColors.tanShadow,
      minHeight: 92,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _chestSizes.last,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: PixelIcon(layers: PixelIcons.chest(lid, body, band, highlight: false), size: _chestSizes[index], outline: 1.5),
            ),
          ),
          const SizedBox(height: 3),
          Text(Catalog.periods[index].$1,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brownText)),
          const SizedBox(height: 3),
          Text(Catalog.periodMult(index),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.goldDeep)),
        ],
      ),
    );
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow({required this.habit, required this.onRemove});
  final Habit habit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cat = Catalog.category(habit.categoryId);
    final m = cat.measures[habit.measureIndex];
    final meta = '${cat.name} · ${m.label}${m.isOX ? '' : ' ${formatNum(habit.target)}${m.unit}'}'
        ' · ${Catalog.periods[habit.periodIndex].$1} ${Catalog.periodMult(habit.periodIndex)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), 
        color: AppColors.parchment,
        border: Border.all(color: AppColors.ink, width: 3),
        boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          CategoryIcon(habit.categoryId, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(habit.name,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                const SizedBox(height: 3),
                Text(meta, style: const TextStyle(fontSize: 9.5, color: AppColors.brownMuted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          DeleteButton(onTap: onRemove, label: '퀘스트 삭제', size: 36, iconSize: 11),
        ],
      ),
    );
  }
}
