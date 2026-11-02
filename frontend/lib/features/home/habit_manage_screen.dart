import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../core/widgets/popup_card.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../onboarding/onboarding_controller.dart';
import '../shell/game_action.dart';
import 'home_parts.dart';
import '../../core/theme/app_theme.dart';

/// 홈의 "습관" 아이콘 → 내 습관 목록(그만두기) ↔ 새 습관 추가(무엇을 → 얼마나 → 언제까지).
/// 입력 상태와 검사는 온보딩과 같은 [OnboardingController]를 쓰고, 화면은 홈과 같은 어두운 테마로 따로 그린다.
class HabitManageScreen extends StatefulWidget {
  const HabitManageScreen({super.key});

  @override
  State<HabitManageScreen> createState() => _HabitManageScreenState();
}

class _HabitManageScreenState extends State<HabitManageScreen> {
  late final OnboardingController _c = OnboardingController(onToast: _toast);
  Timer? _toastTimer;
  String? _toastText;
  bool _ready = false;

  /// 추가 폼을 보는 중인지 (아니면 목록).
  bool _adding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    // 지금 열려 있는 카테고리에서만 고를 수 있다.
    _c.picked.addAll(GameScope.read(context).pickedCategories);
    _c.addListener(_onForm);
  }

  /// 폼이 등록한 습관을 게임 상태로 옮기고 목록으로 돌아간다.
  Future<void> _onForm() async {
    if (_c.habits.isNotEmpty) {
      final drafts = [..._c.habits];
      _c.habits.clear();
      _adding = false;
      for (final h in drafts) {
        await runGameAction(
          context,
          (r) => r.addHabit(
            name: h.name,
            categoryId: h.categoryId,
            measureIndex: h.measureIndex,
            target: h.target,
            periodIndex: h.periodIndex,
          ),
          onError: _toast,
        );
        if (!mounted) return;
      }
    }
    if (mounted) setState(() {});
  }

  void _toast(String text) {
    _toastTimer?.cancel();
    setState(() => _toastText = text);
    _toastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _toastText = null);
    });
  }

  void _startAdd() {
    _c.habStep = 0;
    _c.draftName.clear();
    if (_c.picked.isNotEmpty) _c.pickDraftCategory(_c.picked.first);
    setState(() => _adding = true);
  }

  /// ◀: 추가 중이면 앞 단계(첫 단계면 목록)로, 목록이면 홈으로.
  void _back() {
    if (!_adding) {
      Navigator.of(context).pop();
    } else if (_c.habStep > 0) {
      _c.habPrev();
    } else {
      setState(() => _adding = false);
    }
  }

  Future<void> _confirmRemove(GameState s, Habit h) async {
    if (!s.canRemoveHabit) {
      _toast('습관은 1개 이상 있어야 해요');
      return;
    }
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '그만두기 취소',
      barrierColor: AppColors.black.withValues(alpha: 0),
      pageBuilder: (ctx, _, __) => _RemoveConfirm(habit: h),
    );
    if (ok != true || !mounted) return;
    final removed = await runGameAction(context, (r) => r.removeHabit(h), onError: _toast);
    if (removed == true) _toast('${h.name} 습관을 그만뒀어요');
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _c.removeListener(_onForm);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.night,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(
                  title: _adding ? '새 습관' : '내 습관',
                  badge: _adding ? '${_c.habStep + 1} / 3' : '${s.habits.length} / ${Economy.maxActiveHabits}',
                  backLabel: _adding ? '이전으로' : '홈으로',
                  onBack: _back,
                ),
                Expanded(child: _adding ? _AddForm(c: _c) : _list(s)),
                _bottom(s),
              ],
            ),
            if (_toastText != null)
              Positioned(
                left: 0,
                right: 0,
                top: 70,
                child: IgnorePointer(child: Center(child: PixelToast(text: _toastText!))),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- 목록 ----------
  Widget _list(GameState s) {
    final empty = Economy.maxActiveHabits - s.habits.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Text(
          s.checkedInToday
              ? '오늘 체크는 이미 끝났어요. 지금 추가한 습관은 내일부터 성실도에 반영돼요.'
              : '매일 챗봇이 물어보는 습관이에요. 하루 성실도에는 점수가 높은 ${Economy.dailyHabitCap}개가 반영돼요.',
          style: const TextStyle(fontSize: 12, height: 1.7, color: AppColors.textMuted),
        ),
        const SizedBox(height: 14),
        for (final h in s.habits) ...[
          _HabitCard(habit: h, onRemove: () => _confirmRemove(s, h)),
          const SizedBox(height: 10),
        ],
        for (var i = 0; i < empty; i++) ...[
          _EmptySlot(onTap: _startAdd),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ---------- 아래 버튼 ----------
  Widget _bottom(GameState s) {
    final Widget child;
    if (!_adding) {
      child = PixelButton(
        label: s.canAddHabit ? '+ 새 습관 추가' : '습관이 꽉 찼어요 (${s.habits.length}/${Economy.maxActiveHabits})',
        onPressed: s.canAddHabit ? _startAdd : null,
        disabledColor: AppColors.nightLine2,
        disabledShadowColor: AppColors.ink,
        disabledTextColor: AppColors.textMuted,
      );
    } else {
      final step = _c.habStep;
      final ok = step == 0 ? _c.hasDraftName : (step == 2 ? _c.canAddHabit : true);
      child = PixelButton(
        label: step == 2 ? '등록하기' : '다음',
        onPressed: ok ? _c.habNext : null,
        disabledColor: AppColors.nightLine2,
        disabledShadowColor: AppColors.ink,
        disabledTextColor: AppColors.textMuted,
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.nightDeep,
        border: Border(top: BorderSide(color: AppColors.nightLine, width: 3)),
      ),
      child: child,
    );
  }
}

/// 위 막대: ◀ · 제목 · 개수(또는 단계).
class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.badge, required this.backLabel, required this.onBack});
  final String title;
  final String badge;
  final String backLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      decoration: const BoxDecoration(
        color: AppColors.nightDeep,
        border: Border(bottom: BorderSide(color: AppColors.nightLine, width: 3)),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: backLabel,
            excludeSemantics: true,
            onTap: onBack,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBack,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.nightRaised,
                  border: Border.all(color: AppColors.nightLine2, width: 3),
                ),
                child: const Text('◀', style: TextStyle(fontSize: 14, color: AppColors.text)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: const TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.nightRaised,
              border: Border.all(color: AppColors.gold, width: 2),
            ),
            child: Text(badge, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold)),
          ),
        ],
      ),
    );
  }
}

/// 작은 정보 칩 (분야 · 하루 목표 · 기간).
class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.nightRaised,
        border: Border.all(color: AppColors.nightLine2, width: 2),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.chatSoftText)),
    );
  }
}

/// 목록의 습관 한 칸: 아이콘 · 이름 · 정보 칩 · 그만두기.
class _HabitCard extends StatelessWidget {
  const _HabitCard({required this.habit, required this.onRemove});
  final Habit habit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cat = Catalog.category(habit.categoryId);
    final m = cat.measures[habit.measureIndex];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.nightPanel,
        border: Border.all(color: AppColors.nightLine, width: 3),
      ),
      child: Row(
        children: [
          CategoryIcon(habit.categoryId, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(habit.name,
                    style: const TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    _Chip(cat.short),
                    _Chip(m.isOX ? '했다 / 못 했다' : '하루 ${formatNum(habit.target)}${m.unit}'),
                    _Chip('${Catalog.periods[habit.periodIndex].$1} 도전'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            container: true, // 이름 · 칩과 한 덩어리로 읽히지 않게
            button: true,
            label: '${habit.name} 그만두기',
            excludeSemantics: true,
            onTap: onRemove,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(border: Border.all(color: AppColors.nightLine2, width: 2)),
                child: const Text('그만두기', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 아직 비어 있는 습관 자리. 누르면 추가로 간다.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CustomPaint(
        foregroundPainter: const DashedBorderPainter(color: AppColors.nightLine2, width: 3, dash: 6, gap: 4),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          child: const Text('+ 빈 자리', style: TextStyle(fontSize: 12.5, color: AppColors.lavender)),
        ),
      ),
    );
  }
}

// ---------- 추가 폼 ----------

/// 새 습관: 한 화면에 한 가지씩 묻는다 (무엇을 → 얼마나 → 언제까지).
class _AddForm extends StatelessWidget {
  const _AddForm({required this.c});
  final OnboardingController c;

  static const _questions = ['어떤 습관을 시작할까요?', '하루에 얼마나 할까요?', '언제까지 해 볼까요?'];
  static const _hints = [
    '추천에서 고르거나 직접 적어 주세요.',
    '무엇으로 잴지, 하루 목표를 정해요.',
    '기간을 정하면 그 동안 매일 챗봇이 물어봐요.',
  ];

  @override
  Widget build(BuildContext context) {
    final step = c.habStep;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      children: [
        _Progress(step: step),
        const SizedBox(height: 20),
        Text(_questions[step],
            style: const TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 19, height: 1.3, fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 6),
        Text(_hints[step], style: const TextStyle(fontSize: 12, height: 1.6, color: AppColors.textMuted)),
        const SizedBox(height: 18),
        if (step == 0) ..._what(),
        if (step == 1) ..._howMuch(),
        if (step == 2) ..._until(),
      ],
    );
  }

  static Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.purpleSoft)),
      );

  /// 1. 무엇을 — 분야 · 추천 습관 · 직접 입력
  List<Widget> _what() {
    final cat = c.draftCat;
    final presets = cat == null ? const <(String, int, double)>[] : (Catalog.habitPresets[cat.id] ?? const []);
    return [
      _label('분야'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final id in c.picked)
            _Choice(
              selected: c.draftCategory == id,
              semanticLabel: Catalog.category(id).name,
              onTap: () => c.pickDraftCategory(id),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CategoryIcon(id, size: 20, outline: 0),
                  const SizedBox(width: 7),
                  _ChoiceText(Catalog.category(id).short, selected: c.draftCategory == id),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 20),
      if (cat != null && presets.isNotEmpty) ...[
        _label('추천 습관'),
        for (final p in presets) ...[
          _Choice(
            selected: c.draftName.text == p.$1,
            expand: true,
            onTap: () => c.pickPreset(p),
            child: Row(
              children: [
                Expanded(child: _ChoiceText(p.$1, selected: c.draftName.text == p.$1, size: 14.5)),
                Text(cat.measures[p.$2].isOX ? '했다 / 못 했다' : '하루 ${formatNum(p.$3)}${cat.measures[p.$2].unit}',
                    style: TextStyle(
                        fontSize: 12, color: c.draftName.text == p.$1 ? AppColors.brownText : AppColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
      ],
      _label('직접 입력'),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.nightPanel,
          border: Border.all(color: AppColors.nightLine2, width: 3),
        ),
        child: Semantics(
          label: '습관 이름',
          child: TextField(
            controller: c.draftName,
            cursorColor: AppColors.gold,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '예: 저녁 산책',
              hintStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textMuted),
            ),
            textInputAction: TextInputAction.done,
          ),
        ),
      ),
    ];
  }

  /// 2. 얼마나 — 재는 방법 · 하루 목표
  List<Widget> _howMuch() {
    final cat = c.draftCat!;
    final measure = c.draftMeasureInfo!;
    return [
      _NameBanner(categoryId: cat.id, name: c.draftName.text.trim()),
      const SizedBox(height: 20),
      _label('무엇으로 잴까요?'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < cat.measures.length; i++)
            _Choice(
              selected: c.draftMeasure == i,
              onTap: () => c.pickMeasure(i),
              child: _ChoiceText(
                cat.measures[i].isOX ? '${cat.measures[i].label} (했다 / 못 했다)' : '${cat.measures[i].label} (${cat.measures[i].unit})',
                selected: c.draftMeasure == i,
              ),
            ),
        ],
      ),
      const SizedBox(height: 22),
      if (c.draftNeedsTarget) ...[
        _label('하루 목표'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.nightPanel,
            border: Border.all(color: AppColors.nightLine, width: 3),
          ),
          child: Row(
            children: [
              _StepButton(label: '−', semanticLabel: '목표 줄이기', onTap: c.decTarget),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: formatNum(c.draftTarget)),
                    TextSpan(
                        text: ' ${measure.unit}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.textMuted)),
                  ]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.gold),
                ),
              ),
              _StepButton(label: '+', semanticLabel: '목표 늘리기', onTap: c.incTarget),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('목표를 채우면 20점, 더 하면 최대 ${Economy.maxSincerityPerHabit}점까지 받아요.',
            style: TextStyle(fontSize: 11.5, height: 1.6, color: AppColors.textMuted)),
      ],
      if (c.draftIsOX)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.nightPanel,
            border: Border.all(color: AppColors.nightLine, width: 3),
          ),
          child: const Text('매일 챗봇이 "오늘 했어?"라고 물어봐요.\n했으면 20점, 못 했으면 0점이에요.',
              style: TextStyle(fontSize: 13, height: 1.7, color: AppColors.text)),
        ),
    ];
  }

  /// 3. 언제까지 — 기간 · 확인
  List<Widget> _until() {
    final cat = c.draftCat!;
    final m = c.draftMeasureInfo!;
    return [
      _label('기간'),
      Row(
        children: [
          for (var i = 0; i < Catalog.periods.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _Choice(
                selected: c.draftPeriod == i,
                expand: true,
                semanticLabel: '${Catalog.periods[i].$1} 도전',
                onTap: () => c.pickPeriod(i),
                child: Column(
                  children: [
                    _ChoiceText(Catalog.periods[i].$1, selected: c.draftPeriod == i, size: 17),
                    const SizedBox(height: 3),
                    Text('보너스 ${Catalog.periodMult(i)}',
                        style: TextStyle(
                            fontSize: 10.5, color: c.draftPeriod == i ? AppColors.brownText : AppColors.textMuted)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 22),
      _label('이대로 등록할까요?'),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        decoration: BoxDecoration(
          color: AppColors.nightPanel,
          border: Border.all(color: AppColors.nightLine, width: 3),
        ),
        child: Column(
          children: [
            _SummaryRow('습관', c.draftName.text.trim()),
            _SummaryRow('분야', cat.name),
            _SummaryRow('하루 목표', m.isOX ? '${m.label} · 했다 / 못 했다' : '${m.label} ${formatNum(c.draftTarget)}${m.unit}'),
            _SummaryRow('기간', '${Catalog.periods[c.draftPeriod].$1} 도전'),
          ],
        ),
      ),
    ];
  }
}

/// 1 무엇을 · 2 얼마나 · 3 언제까지 진행 막대.
class _Progress extends StatelessWidget {
  const _Progress({required this.step});
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 8, color: i <= step ? AppColors.gold : AppColors.nightLine2),
                const SizedBox(height: 6),
                Text('${i + 1} ${labels[i]}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: i == step ? FontWeight.w700 : FontWeight.w400,
                      color: i == step ? AppColors.gold : AppColors.textMuted,
                    )),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 고르는 칸: 고르면 금색으로 채워진다.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.onTap,
    required this.child,
    this.expand = false,
    this.semanticLabel,
  });
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final bool expand;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: expand ? double.infinity : null,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.gold : AppColors.nightPanel,
            border: Border.all(color: selected ? AppColors.goldLight : AppColors.nightLine2, width: 3),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ChoiceText extends StatelessWidget {
  const _ChoiceText(this.text, {required this.selected, this.size = 13.5});
  final String text;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w700,
          color: selected ? AppColors.night : AppColors.text,
        ));
  }
}

/// 2단계 위에 보이는 "지금 만드는 습관".
class _NameBanner extends StatelessWidget {
  const _NameBanner({required this.categoryId, required this.name});
  final String categoryId;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.introFloor,
        border: Border.all(color: AppColors.purple, width: 3),
      ),
      child: Row(
        children: [
          CategoryIcon(categoryId, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name, style: const TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
          ),
        ],
      ),
    );
  }
}

/// 하루 목표 − / + 버튼.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.label, required this.semanticLabel, required this.onTap});
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.nightRaised,
            border: Border.all(color: AppColors.purple, width: 3),
          ),
          child: Text(label, style: const TextStyle(fontSize: 22, height: 1, color: AppColors.text)),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 76, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
          ),
        ],
      ),
    );
  }
}

class _RemoveConfirm extends StatelessWidget {
  const _RemoveConfirm({required this.habit});
  final Habit habit;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(false),
        child: PopupCard(
          title: '습관 그만두기',
          ribbonColor: AppColors.redSoft,
          ribbonText: AppColors.white,
          maxWidth: 300,
          children: [
            GestureDetector(
              onTap: () {}, // 카드 안을 눌러도 닫히지 않게
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text("'${habit.name}' 습관을 그만둘까요?",
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                  const SizedBox(height: 6),
                  const Text('지금까지 받은 골드와 몬스터는 그대로예요. 그만둔 습관은 되돌릴 수 없어요.',
                      style: TextStyle(fontSize: 11, height: 1.6, color: AppColors.brownMuted)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: PixelButton(
                          label: '취소',
                          onPressed: () => Navigator.of(context).pop(false),
                          color: AppColors.parchment,
                          shadowColor: AppColors.parchmentShadow,
                          textColor: AppColors.brownText,
                          height: 42,
                          depth: 4,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PixelButton(
                          label: '그만두기',
                          semanticLabel: '그만두기 확인',
                          onPressed: () => Navigator.of(context).pop(true),
                          color: AppColors.redSoft,
                          shadowColor: AppColors.redShadow,
                          textColor: AppColors.white,
                          height: 42,
                          depth: 4,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
