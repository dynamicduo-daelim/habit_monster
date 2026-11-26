import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/constants/economy.dart';
import '../../core/state/game_repository.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';

enum OnboardingStep { categories, habits }

/// 온보딩 1~2단계의 입력 상태와 동작. 시안의 state(picked, starter, draft, habits)와
/// renderVals 안의 toggle / pick / addHabit 를 옮겼다. 3단계(목표)는 목표 기능과 함께 없앴다 (기획 2026-11-25).
class OnboardingController extends ChangeNotifier {
  OnboardingController({required this.onToast}) {
    draftName.addListener(notifyListeners);
  }

  /// 토스트 띄우기 (화면 쪽에서 처리).
  final void Function(String text) onToast;

  OnboardingStep step = OnboardingStep.categories;

  // ---------- 1단계: 카테고리 + 첫 파트너 ----------
  static const int maxCategories = Economy.baseCategorySlots;
  final List<String> picked = [];
  String? starter; // 고른 카테고리 id

  void toggleCategory(String id) {
    if (picked.contains(id)) {
      picked.remove(id);
      if (starter == id) starter = null;
    } else if (picked.length < maxCategories) {
      picked.add(id);
    } else {
      onToast('카테고리는 최대 $maxCategories개');
      return;
    }
    notifyListeners();
  }

  /// [slot]번째 파트너 자리를 누른다.
  void pickStarter(int slot) {
    if (slot >= picked.length) {
      onToast('먼저 위에서 길을 골라주세요');
      return;
    }
    final cid = picked[slot];
    starter = cid;
    notifyListeners();
    final spId = Catalog.starters[cid];
    if (spId != null) onToast('${Catalog.speciesById(spId).name}…? 두근두근!');
  }

  void confirmCategories() {
    if (picked.isEmpty) return;
    _setDraftCategory(picked.first);
    step = OnboardingStep.habits;
    notifyListeners();
  }

  // ---------- 2단계: 습관 퀘스트 ----------
  final TextEditingController draftName = TextEditingController();
  String? draftCategory;
  int draftMeasure = 0;
  double draftTarget = 0;
  int draftPeriod = 1;
  final List<Habit> habits = [];
  int _habitSeq = 0;

  /// 퀘스트 만들기 단계: 0 무엇을 · 1 얼마나 · 2 언제까지 (시안 habStep).
  int habStep = 0;
  static const List<String> habStepLabels = ['무엇을', '얼마나', '언제까지'];

  HabitCategory? get draftCat => draftCategory == null ? null : Catalog.category(draftCategory!);
  Measure? get draftMeasureInfo => draftCat?.measures[draftMeasure];
  bool get draftNeedsTarget => draftMeasureInfo != null && !draftMeasureInfo!.isOX;
  bool get draftIsOX => draftMeasureInfo?.isOX ?? false;

  bool get canAddHabit =>
      draftName.text.trim().isNotEmpty && draftCat != null && (!draftNeedsTarget || draftTarget > 0);

  /// 1단계(무엇을)에서 다음으로 갈 수 있는지.
  bool get hasDraftName => draftName.text.trim().isNotEmpty && draftCat != null;

  void _setDraftCategory(String id) {
    draftCategory = id;
    draftMeasure = 0;
    draftTarget = Catalog.category(id).measures.first.defaultTarget;
  }

  void pickDraftCategory(String id) {
    _setDraftCategory(id);
    notifyListeners();
  }

  void pickPreset((String, int, double) p) {
    draftMeasure = p.$2;
    draftTarget = p.$3;
    draftName.text = p.$1; // 리스너가 notifyListeners 호출
    habStep = 1; // 추천을 고르면 바로 '얼마나'로
    notifyListeners();
  }

  void habPrev() {
    if (habStep == 0) return;
    habStep--;
    notifyListeners();
  }

  /// 다음 ▶ / 마지막 단계에선 퀘스트 등록.
  void habNext() {
    switch (habStep) {
      case 0:
        if (!hasDraftName) {
          onToast('습관을 고르거나 적어주세요');
          return;
        }
        habStep = 1;
        notifyListeners();
      case 1:
        habStep = 2;
        notifyListeners();
      default:
        addHabit();
    }
  }

  void pickMeasure(int i) {
    draftMeasure = i;
    draftTarget = draftCat!.measures[i].defaultTarget;
    notifyListeners();
  }

  double get _step => Catalog.targetSteps[draftMeasureInfo?.unit] ?? 1;
  static double _round1(double v) => (v * 10).round() / 10;

  void decTarget() {
    draftTarget = math.max(_step, _round1(draftTarget - _step));
    notifyListeners();
  }

  void incTarget() {
    draftTarget = _round1(draftTarget + _step);
    notifyListeners();
  }

  void pickPeriod(int i) {
    draftPeriod = i;
    notifyListeners();
  }

  void addHabit() {
    if (!canAddHabit) return;
    if (habits.length >= Economy.maxActiveHabits) {
      onToast('습관 퀘스트는 최대 ${Economy.maxActiveHabits}개까지');
      return;
    }
    final h = Habit(
      id: 'oh${_habitSeq++}',
      name: draftName.text.trim(),
      categoryId: draftCategory!,
      measureIndex: draftMeasure,
      target: draftNeedsTarget ? draftTarget : 1,
      periodIndex: draftPeriod,
    );
    habits.add(h);
    draftName.clear();
    habStep = 0;
    notifyListeners();
    onToast('퀘스트 등록! ${h.name}');
  }

  void removeHabit(Habit h) {
    habits.remove(h);
    notifyListeners();
  }

  /// 홈으로 들어간다 (2단계의 "모험 시작"). 서버 모드면 `POST /onboarding` 일괄 제출.
  Future<void> commit(GameRepository repo) {
    return repo.completeOnboarding(
      picked: picked,
      habits: habits,
      starterCategory: starter,
    );
  }

  @override
  void dispose() {
    draftName.dispose();
    super.dispose();
  }
}
