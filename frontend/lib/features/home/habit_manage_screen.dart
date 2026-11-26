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
import '../../data/pixel_icons.dart';
import '../../core/widgets/pixel_icon.dart';
import '../onboarding/onboarding_controller.dart';
import '../shell/game_action.dart';
import 'home_parts.dart';
import '../../core/theme/app_theme.dart';

/// 습관 관리: 새 습관 빠른 추가(한 화면) ↔ 내 습관 목록(그만두기).
/// 홈의 "습관" 아이콘 · 습관 탭에서 [startAdding]으로 열면 바로 새 습관 화면 (자리가 꽉 찼으면 목록).
/// 바로 열었으면 등록 뒤 화면을 닫고 안내 문구를 돌려준다 (부르는 쪽이 토스트) — 기획 2026-11-26-습관-빠른-추가.
/// 입력 값(분야 · 이름 · 재는 방법 · 목표 · 기간)은 온보딩과 같은 [OnboardingController]의 draft를 쓴다.
class HabitManageScreen extends StatefulWidget {
  const HabitManageScreen({super.key, this.startAdding = false});

  /// 열자마자 새 습관 화면으로 (자리가 남았을 때).
  final bool startAdding;

  /// 새 습관 화면을 열고, 등록하면 안내 문구를 받는다 (닫기만 하면 null).
  static Future<String?> open(BuildContext context) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const HabitManageScreen(startAdding: true)));

  @override
  State<HabitManageScreen> createState() => _HabitManageScreenState();
}

class _HabitManageScreenState extends State<HabitManageScreen> {
  late final OnboardingController _c = OnboardingController(onToast: _toast);
  Timer? _toastTimer;
  String? _toastText;
  bool _ready = false;
  bool _busy = false;

  /// 새 습관 화면을 보는 중인지 (아니면 목록).
  bool _adding = false;

  /// 고른 추천 번호 (없으면 null) · 직접 적는 중인지.
  int? _preset;
  bool _custom = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    final s = GameScope.read(context);
    // 지금 열려 있는 카테고리에서만 고를 수 있다.
    _c.picked.addAll(s.pickedCategories);
    _c.addListener(_onChange);
    if (widget.startAdding && s.canAddHabit) _startAdd();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _toast(String text) {
    _toastTimer?.cancel();
    setState(() => _toastText = text);
    _toastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _toastText = null);
    });
  }

  void _resetDraft() {
    _preset = null;
    _custom = false;
    _c.draftName.clear();
    _c.draftPeriod = 1; // 30일
  }

  void _startAdd() {
    _resetDraft();
    if (_c.picked.isNotEmpty) _c.pickDraftCategory(_c.draftCategory ?? _c.picked.first);
    _adding = true;
  }

  void _pickCategory(String id) {
    final typed = _preset == null ? _c.draftName.text : ''; // 직접 적던 이름은 분야를 바꿔도 남긴다
    _resetDraft();
    _c.draftName.text = typed;
    _c.pickDraftCategory(id);
  }

  void _pickPreset(int i, (String, int, double) p) {
    if (GameScope.read(context).hasHabitNamed(p.$1)) {
      _toast('이미 있는 습관이에요 · ${p.$1}');
      return;
    }
    _preset = i;
    _custom = false;
    _c.pickPreset(p);
    _openSheet();
  }

  /// 맨 위 칸에 직접 적고 [만들기] (또는 자판의 완료) → 확인 창 (11-26 — 직접 적기를 더 쉽게).
  void _pickTyped() {
    if (_c.draftName.text.trim().isEmpty) return;
    if (GameScope.read(context).hasHabitNamed(_c.draftName.text)) {
      _toast('이미 있는 습관이에요');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _preset = null;
    _custom = false;
    _c.pickMeasure(0);
    _openSheet();
  }

  /// 고른 습관의 확인 창 (아래에서 올라옴). 등록하기를 누르면 창을 닫고 등록한다.
  Future<void> _openSheet() async {
    final submit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (ctx) => _DraftSheet(c: _c, custom: _custom, onSubmit: () => Navigator.of(ctx).pop(true)),
    );
    if (submit == true && mounted) {
      await _submit();
    } else if (mounted) {
      setState(() {
        if (_preset != null) _c.draftName.clear(); // 추천을 골랐다 닫으면 위 칸에 추천 이름이 남지 않게
        _preset = null;
        _custom = false;
      });
    }
  }

  /// 확인 창의 "○○ 등록하기". 바로 열었으면 닫으면서 문구를 돌려주고, 목록에서 왔으면 목록으로.
  Future<void> _submit() async {
    if (_busy || !_c.canAddHabit) return;
    final s = GameScope.read(context);
    final name = _c.draftName.text.trim();
    if (s.hasHabitNamed(name)) {
      _toast('이미 있는 습관이에요 · $name'); // 같은 습관 중복 등록 막기 (11-26, 서버 모드도 보내기 전에)
      return;
    }
    setState(() => _busy = true);
    final h = await runGameAction(
      context,
      (r) => r.addHabit(
        name: name,
        categoryId: _c.draftCategory!,
        measureIndex: _c.draftMeasure,
        target: _c.draftNeedsTarget ? _c.draftTarget : 1,
        periodIndex: _c.draftPeriod,
      ),
      onError: _toast,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (h == null) return;
    s.lastAddedHabitId = h.id;
    final msg = '$name 등록! ${s.checkedInToday ? '내일' : '오늘'}부터 챗봇이 물어봐요';
    if (widget.startAdding) {
      Navigator.of(context).pop(msg);
    } else {
      setState(() => _adding = false);
      _toast(msg);
    }
  }

  /// ◀: 바로 열었거나 목록이면 닫기, 목록에서 온 새 습관 화면이면 목록으로.
  void _back() {
    if (_adding && !widget.startAdding) {
      setState(() => _adding = false);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _openList() => setState(() => _adding = false);

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
    _c.removeListener(_onChange);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final count = '${s.habits.length}/${Economy.maxActiveHabits}';
    final listCount = '${s.habits.length} / ${Economy.maxActiveHabits}';
    return Scaffold(
      backgroundColor: AppColors.night,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(
                  title: _adding ? '새 습관' : '내 습관',
                  badge: _adding ? '내 습관 $count ›' : listCount,
                  onBadgeTap: _adding ? _openList : null,
                  backLabel: _adding && !widget.startAdding ? '내 습관으로' : '닫기',
                  onBack: _back,
                ),
                Expanded(
                  child: _adding
                      ? _AddForm(
                          c: _c,
                          preset: _preset,
                          custom: _custom,
                          onCategory: _pickCategory,
                          onPreset: _pickPreset,
                          onCustom: _pickTyped,
                        )
                      : _list(s),
                ),
                if (!_adding) _bottom(s),
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
          _EmptySlot(onTap: () => setState(_startAdd)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ---------- 아래 버튼 ----------
  Widget _bottom(GameState s) {
    final child = PixelButton(
      label: s.canAddHabit ? '+ 새 습관 추가' : '습관이 꽉 찼어요 (${s.habits.length}/${Economy.maxActiveHabits})',
      onPressed: s.canAddHabit ? () => setState(_startAdd) : null,
      disabledColor: AppColors.nightLine2,
      disabledShadowColor: AppColors.ink,
      disabledTextColor: AppColors.textMuted,
    );
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
  const _TopBar({required this.title, required this.badge, required this.backLabel, required this.onBack, this.onBadgeTap});
  final String title;
  final String badge;
  final String backLabel;
  final VoidCallback onBack;

  /// 오른쪽 칩을 누르면 (새 습관 화면의 "내 습관 n/5 ›" → 목록).
  final VoidCallback? onBadgeTap;

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
          Semantics(
            button: onBadgeTap != null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBadgeTap,
              child: Container(
                constraints: BoxConstraints(minHeight: onBadgeTap != null ? 44 : 0),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.nightRaised,
                  border: Border.all(color: AppColors.gold, width: 2),
                ),
                child: Text(badge, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold)),
              ),
            ),
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
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
              CategoryIcon(habit.categoryId, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(habit.name,
                        style: const TextStyle(
                            fontFamily: AppTheme.pixelFont, fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
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
            ],
          ),
          // 그만두기는 카드 아래 오른쪽에 작게 (11-26 — 눈에 덜 띄게, 실수로 누르지 않게)
          Align(
            alignment: Alignment.centerRight,
            child: Semantics(
              container: true,
              button: true,
              label: '${habit.name} 그만두기',
              excludeSemantics: true,
              onTap: onRemove,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 2, 8),
                  child: Text('그만두기',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textMuted, decoration: TextDecoration.underline, decorationColor: AppColors.textMuted)),
                ),
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
/// 새 습관 화면: 분야 칩 + 추천 목록 + 직접 적기만. 누르면 [_DraftSheet] 확인 창에서 목표 · 기간을 보고 바로 등록
/// (기획 2026-11-26-습관-빠른-추가, 같은 날 "화면이 복잡함" 피드백으로 카드를 확인 창으로 옮김).
class _AddForm extends StatelessWidget {
  const _AddForm({
    required this.c,
    required this.preset,
    required this.custom,
    required this.onCategory,
    required this.onPreset,
    required this.onCustom,
  });
  final OnboardingController c;
  final int? preset;
  final bool custom;
  final void Function(String id) onCategory;
  final void Function(int i, (String, int, double) p) onPreset;
  final VoidCallback onCustom;

  static Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.purpleSoft)),
      );


  @override
  Widget build(BuildContext context) {
    final cat = c.draftCat;
    final presets = cat == null ? const <(String, int, double)>[] : (Catalog.habitPresets[cat.id] ?? const []);
    final typed = c.draftName.text.trim().isNotEmpty && preset == null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      children: [
        // 1. 직접 적기: 맨 위에 바로 입력 (11-26 — 추천을 고르지 않아도 한 번에)
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: AppColors.nightPanel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: typed ? AppColors.gold : AppColors.purple, width: 3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('어떤 습관을 시작할까요?',
                  style: TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (cat != null) ...[CategoryIcon(cat.id, size: 26), const SizedBox(width: 8)],
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.nightDeep,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.nightLine2, width: 2),
                      ),
                      child: Semantics(
                        label: '습관 이름 직접 적기',
                        child: TextField(
                          controller: c.draftName,
                          cursorColor: AppColors.gold,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                            hintText: '예: 저녁 산책, 영어 단어 외우기',
                            hintStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w400, color: AppColors.textMuted),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => onCustom(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    enabled: typed,
                    label: '만들기',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: typed ? onCustom : null,
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: typed ? AppColors.gold : AppColors.nightLine2,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('만들기',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700, color: typed ? AppColors.night : AppColors.textMuted)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // 2. 분야: 얇은 탭 한 줄 (11-26 — 박스가 많아 한눈에 안 들어온다는 피드백)
        _label('분야'),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final id in c.picked) ...[
                _CategoryTab(id: id, selected: c.draftCategory == id, onTap: () => onCategory(id)),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        // 3. 추천: 줄로 나뉜 목록 하나 (누르면 바로 등록 창, 이미 있는 습관은 "등록됨")
        _label('추천 — 누르면 바로 등록 창'),
        if (cat != null)
          Container(
            decoration: BoxDecoration(
              color: AppColors.nightPanel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.nightLine, width: 2),
            ),
            child: Column(
              children: [
                for (var i = 0; i < presets.length; i++) ...[
                  if (i > 0) const Divider(height: 1, thickness: 1, color: AppColors.nightLine),
                  _PresetRow(
                    name: presets[i].$1,
                    meta: cat.measures[presets[i].$2].isOX
                        ? '했다 / 못 했다'
                        : '하루 ${formatNum(presets[i].$3)}${cat.measures[presets[i].$2].unit}',
                    exists: GameScope.of(context).hasHabitNamed(presets[i].$1),
                    onTap: () => onPreset(i, presets[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// 추천 · 직접 적기를 누르면 아래에서 올라오는 작은 확인 창: 이름 → 하루 목표 → 기간 → [등록하기].
/// 재는 방법은 기본값이 맞는 경우가 많아 "자세히" 안에 숨긴다 (11-26 피드백 "화면이 복잡함").
class _DraftSheet extends StatefulWidget {
  const _DraftSheet({required this.c, required this.custom, required this.onSubmit});
  final OnboardingController c;
  final bool custom;
  final VoidCallback onSubmit;

  @override
  State<_DraftSheet> createState() => _DraftSheetState();
}

class _DraftSheetState extends State<_DraftSheet> {
  bool _more = false;

  static Widget _small(String text) => Text(text, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.c,
      builder: (context, _) {
        final c = widget.c;
        final cat = c.draftCat!;
        final m = c.draftMeasureInfo!;
        final name = c.draftName.text.trim();
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: const BoxDecoration(
              color: AppColors.nightDeep,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(top: BorderSide(color: AppColors.purple, width: 3)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Container(width: 46, height: 5, color: AppColors.sheetHandle)),
                    const SizedBox(height: 14),
                    // 이름
                    Row(
                      children: [
                        CategoryIcon(cat.id, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: widget.custom
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.nightPanel,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.gold, width: 2),
                                  ),
                                  child: Semantics(
                                    label: '습관 이름',
                                    child: TextField(
                                      controller: c.draftName,
                                      autofocus: true,
                                      cursorColor: AppColors.gold,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                                        hintText: '습관 이름 (예: 저녁 산책)',
                                        hintStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textMuted),
                                      ),
                                      textInputAction: TextInputAction.done,
                                    ),
                                  ),
                                )
                              : Text(name,
                                  style: const TextStyle(
                                      fontFamily: AppTheme.pixelFont, fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.text)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // 하루 목표
                    if (c.draftNeedsTarget)
                      Row(
                        children: [
                          SizedBox(width: 64, child: _small('하루 목표')),
                          _StepButton(label: '−', semanticLabel: '목표 줄이기', onTap: c.decTarget),
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(text: formatNum(c.draftTarget)),
                                TextSpan(
                                    text: ' ${m.unit}',
                                    style: const TextStyle(
                                        fontFamily: AppTheme.bodyFont,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: AppColors.textMuted)),
                              ]),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontFamily: AppTheme.pixelFont, fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.gold),
                            ),
                          ),
                          _StepButton(label: '+', semanticLabel: '목표 늘리기', onTap: c.incTarget),
                        ],
                      )
                    else
                      const Text('매일 챗봇이 "오늘 했어?"라고 물어봐요.',
                          style: TextStyle(fontSize: 13, height: 1.6, color: AppColors.text)),
                    const SizedBox(height: 16),
                    // 기간
                    Row(
                      children: [
                        SizedBox(width: 64, child: _small('기간')),
                        for (var i = 0; i < Catalog.periods.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: _Choice(
                              selected: c.draftPeriod == i,
                              expand: true,
                              semanticLabel: '${Catalog.periods[i].$1} 도전',
                              onTap: () => c.pickPeriod(i),
                              child: Center(
                                child: Text(Catalog.periods[i].$1,
                                    style: TextStyle(
                                        fontFamily: AppTheme.pixelFont,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: c.draftPeriod == i ? AppColors.night : AppColors.text)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 64),
                      child: Text('끝까지 지키면 보너스 ${Catalog.periodMult(c.draftPeriod)}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ),
                    const SizedBox(height: 10),
                    // 자세히: 재는 방법
                    Semantics(
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _more = !_more),
                        child: SizedBox(
                          height: 40,
                          child: Row(
                            children: [
                              Text(_more ? '자세히 ▲' : '자세히 ▼',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.purpleSoft)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('재는 방법: ${m.isOX ? '${m.label} (했다/못 했다)' : '${m.label} (${m.unit})'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_more) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0; i < cat.measures.length; i++)
                            _MeasureChip(
                              label: cat.measures[i].isOX
                                  ? '${cat.measures[i].label} (했다/못 했다)'
                                  : '${cat.measures[i].label} (${cat.measures[i].unit})',
                              selected: c.draftMeasure == i,
                              onTap: () => c.pickMeasure(i),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 6),
                    PixelButton(
                      label: c.canAddHabit ? '$name 등록하기' : '습관 이름을 적어 주세요',
                      onPressed: c.canAddHabit ? widget.onSubmit : null,
                      disabledColor: AppColors.nightLine2,
                      disabledShadowColor: AppColors.ink,
                      disabledTextColor: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 재는 방법 칩 (작게, 고르면 보라색).
class _MeasureChip extends StatelessWidget {
  const _MeasureChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.purpleDeep : AppColors.nightDeep,
            border: Border.all(color: selected ? AppColors.purpleSoft : AppColors.nightLine2, width: 2),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: selected ? AppColors.text : AppColors.textMuted)),
        ),
      ),
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
          width: 44,
          height: 44,
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

/// 분야 탭 (알약 모양, 높이 38): 고르면 금색.
class _CategoryTab extends StatelessWidget {
  const _CategoryTab({required this.id, required this.selected, required this.onTap});
  final String id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: Catalog.category(id).name,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.gold : AppColors.nightPanel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? AppColors.goldLight : AppColors.nightLine2, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CategoryIcon(id, size: 16, outline: 0),
              const SizedBox(width: 6),
              Text(Catalog.category(id).short,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? AppColors.night : AppColors.text)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 추천 한 줄: 이름 · 하루 목표 · 오른쪽 + (이미 있으면 "등록됨"으로 흐리게).
class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.name, required this.meta, required this.exists, required this.onTap});
  final String name;
  final String meta;
  final bool exists;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !exists,
      label: exists ? '$name, 이미 등록됨' : '$name, $meta',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: exists ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Expanded(child: Text(name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text))),
                Text(exists ? '등록됨' : meta, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(width: 10),
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: exists ? AppColors.nightLine2 : AppColors.gold,
                    shape: BoxShape.circle,
                  ),
                  child: PixelIcon(
                      layers: [
                        PixelLayer(exists ? PixelIcons.checkStroke : PixelIcons.plus, exists ? AppColors.textMuted : AppColors.night)
                      ],
                      size: 12,
                      strokeWidth: exists ? 3.5 : null),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
