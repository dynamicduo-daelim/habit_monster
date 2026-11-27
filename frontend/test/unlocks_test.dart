import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/core/state/unlocks.dart';
import 'package:habit_monster/features/shell/main_shell.dart';

import 'game_harness.dart';

/// 단계별 열기 (기획 2026-11-26-단계별-열기, D-100).
void main() {
  group('조건', () {
    test('기록이 없는 사람(기존 · 시연)은 전부 열림', () async {
      final u = Unlocks(MemoryUnlockStore());
      await u.load();
      expect(u.fresh, isFalse);
      for (final f in Feature.values) {
        expect(u.isOpen(f), isTrue);
      }
    });

    test('새로 시작: 오늘 · 챗봇만 → 체크인하면 필드, 2마리면 가방, 3일째 도감 · 통계, 한 번 열리면 계속', () async {
      final store = MemoryUnlockStore();
      final s = GameState.sample();
      s.monsters.removeRange(1, s.monsters.length); // 처음엔 1마리
      // 목요일 이후엔 샘플 출석으로 주간 퀘스트 선물이 생긴다 → 요일과 무관하게 선물 없이 시작
      for (final g in s.demoGifts()) {
        s.claimedQuestRewards.add(g.id);
      }
      final u = Unlocks(store);
      await u.load();
      await u.startFresh(s.dayCount);
      expect(u.evaluate(s), isEmpty);
      expect(Feature.values.where(u.isOpen), isEmpty);

      s.confirmCheckin({'h1': 30, 'h2': 0, 'h3': 0});
      expect(u.evaluate(s), contains(Feature.field));
      expect(u.isOpen(Feature.bag), isFalse);

      s.dayCount += 2;
      expect(u.evaluate(s), containsAll([Feature.dex, Feature.stats]));

      // 다시 켜도 그대로 (저장됨)
      final again = Unlocks(store);
      await again.load();
      expect((again.fresh, again.isOpen(Feature.field), again.isOpen(Feature.dex), again.isOpen(Feature.bag)), (true, true, true, false));
    });
  });

  testWidgets('새로 시작한 사람: 아래 탭 5칸은 보이고 잠긴 칸은 누르면 조건 안내 → 체크인하면 "필드" 축하 창 → 보러 가기 → 필드 탭', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameState.sample();
    s.monsters.removeRange(1, s.monsters.length);
    s.streakDays = 0; // 이번 주 출석 선물이 먼저 생기지 않게 (선물함 축하 창이 앞에 끼지 않게)
    final u = Unlocks(MemoryUnlockStore());
    await u.load();
    await u.startFresh(s.dayCount);
    await tester.pumpWidget(UnlocksScope(unlocks: u, child: withGame(s, const MaterialApp(home: MainShell()))));
    await tester.pump();
    // 탭은 5칸 다 있고, 잠긴 3칸은 자물쇠
    for (final t in ['오늘', '챗봇', '필드', '도감', '통계']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.byIcon(Icons.lock_rounded), findsNWidgets(3));
    // 잠긴 칸을 누르면 여는 조건만 알려 주고 탭은 그대로
    await tester.tap(find.text('필드'));
    await tester.pump();
    expect(find.text(Feature.field.lockHint), findsOneWidget);
    expect(find.bySemanticsLabel('상점'), findsNothing);
    await tester.pump(const Duration(seconds: 2));

    s.confirmCheckin({'h1': 30, 'h2': 0, 'h3': 0});
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('필드가 열렸어요!'), findsOneWidget);
    await tester.tap(find.text('보러 가기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('필드'), findsWidgets); // 아래 탭 + 비추기 안내
    expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2)); // 필드 자물쇠가 풀림
    await tester.tap(find.text('시작하기!'));
    await tester.pump(const Duration(milliseconds: 400));
    // 체크인으로 선물도 생겨 이어서 선물함 축하 창 → 나중에
    if (find.text('나중에').evaluate().isNotEmpty) {
      await tester.tap(find.text('나중에'));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.bySemanticsLabel('상점'), findsOneWidget); // 필드 탭으로 왔다
    expect(find.bySemanticsLabel('가방'), findsNothing); // 가방은 아직 (1마리)
    await tester.pump(const Duration(seconds: 7));
  });
}
