import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/core/state/local_game_repository.dart';
import 'package:habit_monster/data/models.dart';
import 'package:habit_monster/features/onboarding/onboarding_controller.dart';
import 'package:habit_monster/features/onboarding/onboarding_flow.dart';
import 'game_harness.dart';

void main() {
  group('OnboardingController', () {
    late List<String> toasts;
    late OnboardingController c;

    setUp(() {
      toasts = [];
      c = OnboardingController(onToast: toasts.add);
    });
    tearDown(() => c.dispose());

    test('카테고리는 최대 3개, 빼면 파트너도 풀린다', () {
      for (final id in ['ex', 'st', 'fd', 'md']) {
        c.toggleCategory(id);
      }
      expect(c.picked, ['ex', 'st', 'fd']);
      expect(toasts.last, '카테고리는 최대 3개');

      c.pickStarter(0);
      expect(c.starter, 'ex');
      c.toggleCategory('ex');
      expect(c.starter, isNull);
    });

    test('빈 파트너 자리를 누르면 안내만', () {
      c.pickStarter(0);
      expect(c.starter, isNull);
      expect(toasts.last, '먼저 위에서 길을 골라주세요');
    });

    test('습관 초안: 기본 목표 · 단위별 증감 · 등록', () {
      c.toggleCategory('fd');
      c.confirmCategories();
      expect(c.step, OnboardingStep.habits);
      expect(c.draftTarget, 2); // 물 섭취량 2L
      c.incTarget();
      expect(c.draftTarget, 2.5);
      for (var i = 0; i < 10; i++) {
        c.decTarget();
      }
      expect(c.draftTarget, 0.5); // 한 칸 아래로는 안 내려감

      expect(c.canAddHabit, isFalse);
      c.pickPreset(('영양제 먹기', 2, 1));
      expect(c.draftIsOX, isTrue);
      c.addHabit();
      expect(c.habits.single.name, '영양제 먹기');
      expect(c.draftName.text, '');
      c.finishHabits();
      expect(c.step, OnboardingStep.goals);
    });

    test('퀘스트 단계: 무엇을 → 얼마나 → 언제까지 → 등록하면 처음으로', () {
      c.toggleCategory('ex');
      c.confirmCategories();
      expect(c.habStep, 0);
      c.habNext(); // 이름 없음
      expect(c.habStep, 0);
      expect(toasts.last, '습관을 고르거나 적어주세요');

      c.draftName.text = '저녁 산책';
      c.habNext();
      expect(c.habStep, 1);
      c.habPrev();
      expect(c.habStep, 0);
      c.habNext();
      c.habNext();
      expect(c.habStep, 2);
      c.habNext(); // 등록
      expect(c.habits.single.name, '저녁 산책');
      expect(c.habStep, 0);
      expect(c.draftName.text, '');

      c.pickPreset(('아침 러닝', 0, 30));
      expect(c.habStep, 1); // 추천은 바로 '얼마나'
    });

    test('목표 칸 수 제한', () {
      for (final t in ['a', 'b', 'c', 'd']) {
        c.goalInputs[GoalTier.weekly]!.text = t;
        c.addGoal(GoalTier.weekly);
      }
      expect(c.goals[GoalTier.weekly]!.length, 3);
      expect(c.goalInputs[GoalTier.weekly]!.text, 'd');
      c.addGoal(GoalTier.monthly);
      expect(toasts.last, '목표를 적어주세요');
    });

    test('완료하면 첫 파트너가 필드에 들어온다', () async {
      final s = GameState.sample(gold: 1240, balls: 1);
      c.toggleCategory('sl');
      c.pickStarter(0);
      c.confirmCategories();
      c.draftName.text = '7시간 자기';
      c.addHabit();
      await c.commit(LocalGameRepository(s));
      expect(s.pickedCategories, ['sl']);
      expect(s.habits.single.name, '7시간 자기');
      expect(s.goals, isEmpty);
      final squirrel = s.monsters.firstWhere((m) => m.speciesId == 'squirrel');
      expect(squirrel.level, 1);
      expect(squirrel.affection, 3);
      expect(squirrel.inField, isTrue);
      expect(s.chatPartnerUid, squirrel.uid);
    });
  });

  testWidgets('온보딩 1→2→3단계 화면 흐름', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = GameState.sample(gold: 1240, balls: 1);
    await tester.pumpWidget(withGame(state, const MaterialApp(home: OnboardingFlow())));

    expect(find.text('STEP 1 / 3 · 모험의 길 고르기'), findsOneWidget);
    await tester.tap(find.text('운동'));
    await tester.pump();
    expect(find.text('1/3'), findsOneWidget);
    await tester.tap(find.text('이 길로 간다 ▶'));
    await tester.pump();

    expect(find.text('STEP 2 / 3 · 습관 퀘스트 만들기'), findsOneWidget);
    // 1. 무엇을: 추천을 고르면 바로 2. 얼마나
    await tester.tap(find.text('아침 러닝'));
    await tester.pump();
    expect(find.text('하루에 얼마나?'), findsOneWidget);
    await tester.ensureVisible(find.text('다음 ▶'));
    await tester.tap(find.text('다음 ▶'));
    await tester.pump();
    // 3. 언제까지: 요약 확인 후 등록
    expect(find.text('퀘스트 요약'), findsOneWidget);
    await tester.ensureVisible(find.text('퀘스트 등록!'));
    await tester.tap(find.text('퀘스트 등록!'));
    await tester.pump();
    expect(find.text('등록한 퀘스트 · 1개'), findsOneWidget);
    expect(find.text('1. 무엇을'), findsOneWidget); // 다시 처음 단계로
    await tester.tap(find.text('모험 시작 ▶'));
    await tester.pump();

    expect(find.text('STEP 3 / 3 · 목표 세우기'), findsOneWidget);
    expect(find.text('목표 없이 시작 ▶'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // 토스트 타이머 정리
  });
}
