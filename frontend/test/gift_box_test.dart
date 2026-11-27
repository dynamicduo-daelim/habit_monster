import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_monster/core/api/api_client.dart';
import 'package:habit_monster/core/api/api_exception.dart';
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

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

/// 선물함 (기획 2026-11-26-선물함 · 명세 v10 11장): 퀘스트 보상은 선물로 쌓이고 [받기]로 들어온다.
void main() {
  group('시연 퀘스트 · 선물', () {
    test('체크인하면 "오늘의 기록" 선물이 생기고, 받으면 3G · 두 번은 못 받는다', () {
      final s = GameState.sample(gold: 100);
      for (final m in s.monsters) {
        m.pettedToday = false;
      }
      final tue = DateTime(2026, 11, 24); // 화요일 — 이번 주 출석이 4일이 안 돼 주간 선물이 섞이지 않게
      expect(s.demoGifts(now: tue), isEmpty);
      s.confirmCheckin({'h1': 0, 'h2': 0, 'h3': 0});
      final gold = s.gold;
      final gifts = s.demoGifts(now: tue);
      expect(gifts.map((g) => (g.title, g.gold)), [('오늘의 기록', 3)]);
      expect(s.claimDemoGift(gifts.single), 3);
      expect(s.gold, gold + 3);
      expect(s.claimDemoGift(gifts.single), 0);
      expect(s.demoGifts(now: tue), isEmpty);
    });

    test('말 걸기 · 타이머 · 잠김', () {
      final s = GameState.sample();
      s.noteTalked();
      s.noteTimerUsed();
      final daily = {for (final q in s.demoDailyQuests()) q.code: q};
      expect(daily['DAILY_TALK']!.done, isTrue);
      expect(daily['DAILY_TIMER']!.done, isTrue); // 샘플에 "분" 습관(아침 러닝)이 있다
      s.pickedCategories.removeLast();
      final weekly = {for (final q in s.demoWeeklyQuests()) q.code: q};
      expect(weekly['WEEKLY_CATEGORIES']!.status, QuestStatus.locked);
      expect(weekly['WEEKLY_CATEGORIES']!.lockReason, 'NOT_ENOUGH_CATEGORIES');
    });

    test('이번 주 출석은 월요일부터 오늘까지, 성실도 80%는 샘플 하루 + 오늘 (시연에서도 끝낼 수 있게)', () {
      final s = GameState.sample(); // 어제까지 연속 11일
      s.attend();
      final wed = DateTime(2026, 11, 25); // 수요일
      final w = {for (final q in s.demoWeeklyQuests(now: wed)) q.code: q};
      expect((w['WEEKLY_ATTEND']!.progress, w['WEEKLY_ATTEND']!.target), (3, 4)); // 월 · 화 · 수
      expect(w['WEEKLY_GOOD_DAYS']!.progress, 1);
      s.confirmCheckin({'h1': 30, 'h2': 60, 'h3': 2}); // 60점 이상
      expect(s.demoWeeklyQuests(now: wed).firstWhere((q) => q.code == 'WEEKLY_GOOD_DAYS').done, isTrue);
    });
  });

  testWidgets('홈 선물함 점 → 선물함에서 받기', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = GameState.sample(gold: 100);
    for (final m in s.monsters) {
      m.pettedToday = false;
    }
    s.confirmCheckin({'h1': 0, 'h2': 0, 'h3': 0});
    final gold = s.gold;
    await tester.pumpWidget(withGame(s, const MaterialApp(home: MainShell(initialTab: MainShell.homeTab))));
    await tester.pump();
    final icon = find.bySemanticsLabel('선물함, 받을 선물 있음'); // 개수 없이 점만 (명세 v10)
    expect(icon, findsOneWidget);

    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(find.byType(GiftBoxScreen), findsOneWidget);
    expect(find.text('받을 선물'), findsOneWidget);
    expect(find.text('오늘의 퀘스트'), findsNothing); // 선물함은 받을 보상만 (11-26)

    await tester.tap(find.text('3G 받기'));
    await tester.pumpAndSettle();
    expect(s.gold, gold + 3);
    expect(find.text('3G 받기'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  group('서버 모드 (명세 v10)', () {
    late List<http.Request> requests;
    late Map<String, http.Response> routes;

    HttpGameRepository repo(GameState s) {
      requests = [];
      return HttpGameRepository(
        s,
        ApiClient(
          baseUrl: 'http://x/api/v1',
          tokens: _Tokens(),
          retryDelay: Duration.zero,
          client: MockClient((r) async {
            requests.add(r);
            return routes['${r.method} ${r.url.path.replaceFirst('/api/v1', '')}'] ??
                _json({'code': 'NOT_FOUND', 'message': '없음'}, 404);
          }),
        ),
      );
    }

    setUp(() {
      routes = {
        'GET /quests': _json({
          'businessDate': '2026-11-26',
          'enabled': true,
          'daily': [
            {'code': 'DAILY_CHECKIN', 'title': '오늘의 기록', 'progress': 1, 'target': 1, 'rewardGold': 3, 'status': 'DONE'},
            {
              'code': 'DAILY_TIMER',
              'title': '타이머 한 번 쓰기',
              'progress': 0,
              'target': 1,
              'rewardGold': 1,
              'status': 'LOCKED',
              'lockReason': 'NO_TIMER_HABIT'
            },
          ],
          'weekStart': '2026-11-24',
          'weekly': [
            {'code': 'WEEKLY_ATTEND', 'title': '주 4일 출석', 'progress': 4, 'target': 4, 'rewardGold': 5, 'status': 'DONE'},
          ],
        }),
        'GET /gifts': _json({
          'gifts': [
            {'id': 42, 'source': 'QUEST_WEEKLY', 'title': '주 4일 출석', 'gold': 5, 'itemCode': null, 'itemName': null, 'quantity': 0},
            {'id': 41, 'source': 'QUEST_DAILY', 'title': '오늘의 기록', 'gold': 3, 'itemCode': null, 'itemName': null, 'quantity': 0},
          ],
        }),
      };
    });

    test('GET /quests + GET /gifts → 퀘스트 · 받지 않은 선물, hasGift', () async {
      final s = GameState.empty()..serverGifts = true;
      final b = await repo(s).loadQuests();
      expect(b.daily.map((q) => (q.code, q.status)), [('DAILY_CHECKIN', QuestStatus.done), ('DAILY_TIMER', QuestStatus.locked)]);
      expect(b.gifts.map((g) => (g.id, g.title, g.gold, g.weekly)), [('42', '주 4일 출석', 5, true), ('41', '오늘의 기록', 3, false)]);
      expect(s.hasPendingGift, isTrue);
    });

    test('받기: 키와 함께 POST, 잔액 · 볼은 서버 값, 이미 받았으면 "이미 받은 선물이에요"', () async {
      final s = GameState.empty()..serverGifts = true;
      final r = repo(s);
      final b = await r.loadQuests();
      routes['POST /gifts/41/claim'] = _json({'claimedCount': 1, 'goldReceived': 3, 'items': [], 'gold': 345, 'ballCount': 2});
      expect(await r.claimGift(b.gifts.last), 3);
      expect(requests.last.headers['Idempotency-Key'], isNotEmpty);
      expect((s.gold, s.balls), (345, 2));

      routes['POST /gifts/42/claim'] = _json({'code': 'GIFT_ALREADY_CLAIMED', 'message': 'already'}, 409);
      await expectLater(
          r.claimGift(b.gifts.first),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'GIFT_ALREADY_CLAIMED')
              .having((e) => e.message, 'message', '이미 받은 선물이에요')));
    });

    test('모두 받기 → 합계, 점이 꺼진다', () async {
      final s = GameState.empty()..serverGifts = true;
      final r = repo(s);
      await r.loadQuests();
      routes['POST /gifts/claim-all'] = _json({'claimedCount': 2, 'goldReceived': 8, 'items': [], 'gold': 400, 'ballCount': 1});
      expect(await r.claimAllGifts(), 8);
      expect(requests.last.headers['Idempotency-Key'], isNotEmpty);
      expect(s.gold, 400);
      expect(s.hasPendingGift, isFalse);
    });
  });
}
