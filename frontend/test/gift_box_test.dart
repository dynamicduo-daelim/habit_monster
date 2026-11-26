import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_monster/core/api/api_client.dart';
import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/core/state/http_game_repository.dart';
import 'package:habit_monster/data/models.dart';
import 'package:habit_monster/features/gift/gift_box_screen.dart';
import 'package:habit_monster/features/shell/main_shell.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'game_harness.dart';

class _Tokens implements TokenSource {
  @override
  String? accessToken = 'access';

  @override
  Future<void> refreshOnce() async {}
}

/// 선물함 (기획 2026-11-26-선물함): 시연 모드는 받기를 눌러야 골드, 서버 모드는 GET /quests · 자동 지급.
void main() {
  group('시연 퀘스트 · 선물', () {
    test('체크인하면 "오늘의 기록"이 선물로 쌓이고, 받으면 3G · 두 번은 못 받는다', () {
      final s = GameState.sample(gold: 100);
      for (final m in s.monsters) {
        m.pettedToday = false;
      }
      final tue = DateTime(2026, 11, 24); // 화요일 — 이번 주 출석이 4일이 안 돼 주간 선물이 섞이지 않게
      expect(s.demoClaimable(now: tue), isEmpty);
      s.confirmCheckin({'h1': 0, 'h2': 0, 'h3': 0});
      final gold = s.gold;
      final gifts = s.demoClaimable(now: tue);
      expect(gifts.map((q) => q.code), ['DAILY_CHECKIN']);
      expect(s.claimQuestReward(gifts.single, now: tue), 3);
      expect(s.gold, gold + 3);
      expect(s.claimQuestReward(gifts.single, now: tue), 0);
      expect(s.demoClaimable(now: tue), isEmpty);
    });

    test('말 걸기 · 타이머 · 잠김', () {
      final s = GameState.sample();
      s.noteTalked();
      s.noteTimerUsed();
      final daily = {for (final q in s.demoDailyQuests()) q.code: q};
      expect(daily['DAILY_TALK']!.done, isTrue);
      expect(daily['DAILY_TIMER']!.done, isTrue); // 샘플에 "분" 습관(아침 러닝)이 있다
      // 연 카테고리가 3개 미만이면 카테고리 퀘스트는 잠김
      s.pickedCategories.removeLast();
      final weekly = {for (final q in s.demoWeeklyQuests()) q.code: q};
      expect(weekly['WEEKLY_CATEGORIES']!.status, QuestStatus.locked);
      expect(weekly['WEEKLY_CATEGORIES']!.lockReason, 'NOT_ENOUGH_CATEGORIES');
    });

    test('이번 주 출석은 월요일부터 오늘까지 센다', () {
      final s = GameState.sample(); // 어제까지 연속 11일
      s.attend();
      final wed = DateTime(2026, 11, 25); // 수요일
      final attend = s.demoWeeklyQuests(now: wed).firstWhere((q) => q.code == 'WEEKLY_ATTEND');
      expect(attend.progress, 3); // 월 · 화 · 수
      expect(attend.target, 4);
    });
  });

  testWidgets('홈 선물함 아이콘 배지 → 선물함에서 받기', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameState.sample(gold: 100);
    for (final m in s.monsters) {
      m.pettedToday = false;
    }
    s.confirmCheckin({'h1': 0, 'h2': 0, 'h3': 0});
    final gold = s.gold;
    await tester.pumpWidget(withGame(s, const MaterialApp(home: MainShell())));
    await tester.pump();
    // 받을 선물 수는 요일에 따라 주간 출석 선물이 더해질 수 있다
    final icon = find.bySemanticsLabel(RegExp(r'^선물함, 받을 선물 \d+개$'));
    expect(icon, findsOneWidget);

    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(find.byType(GiftBoxScreen), findsOneWidget);
    expect(find.text('오늘의 퀘스트'), findsOneWidget);
    expect(find.text('이번 주 퀘스트'), findsOneWidget);
    expect(find.text('선물함에 있어요'), findsWidgets);

    await tester.tap(find.text('3G 받기'));
    await tester.pumpAndSettle();
    expect(s.gold, gold + 3);
    expect(find.text('3G 받기'), findsNothing);
    expect(find.text('받음'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  test('서버 모드: GET /quests를 읽고 완료는 자동 지급 (받을 선물 없음)', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/api/v1/quests');
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'businessDate': '2026-11-25',
            'enabled': true,
            'daily': [
              {'code': 'DAILY_CHECKIN', 'title': '오늘의 기록', 'progress': 1, 'target': 1, 'rewardGold': 3, 'status': 'DONE'},
              {'code': 'DAILY_TIMER', 'title': '타이머 한 번 쓰기', 'progress': 0, 'target': 1, 'rewardGold': 1, 'status': 'LOCKED', 'lockReason': 'NO_TIMER_HABIT'},
            ],
            'weekStart': '2026-11-24',
            'weekly': [
              {'code': 'WEEKLY_ATTEND', 'title': '주 4일 출석', 'progress': 2, 'target': 4, 'rewardGold': 5, 'status': 'IN_PROGRESS'},
            ],
          })),
          200,
          headers: {'content-type': 'application/json'});
    });
    final repo = HttpGameRepository(GameState.empty(), ApiClient(baseUrl: 'http://x/api/v1', tokens: _Tokens(), retryDelay: Duration.zero, client: client));
    final b = await repo.loadQuests();
    expect(b.autoPaid, isTrue);
    expect(b.claimable, isEmpty);
    expect(b.daily.map((q) => (q.code, q.status)), [('DAILY_CHECKIN', QuestStatus.done), ('DAILY_TIMER', QuestStatus.locked)]);
    expect(b.daily.last.lockReason, 'NO_TIMER_HABIT');
    expect(b.weekly.single.weekly, isTrue);
    expect(await repo.claimQuestReward(b.daily.first), 0);
  });
}
