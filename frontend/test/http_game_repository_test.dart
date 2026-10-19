import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:habit_monster/core/api/api_client.dart';
import 'package:habit_monster/core/api/api_exception.dart';
import 'package:habit_monster/core/state/game_repository.dart';
import 'package:habit_monster/core/state/game_state.dart';
import 'package:habit_monster/core/state/http_game_repository.dart';
import 'package:habit_monster/core/state/local_game_repository.dart';
import 'package:habit_monster/data/models.dart';
import 'package:habit_monster/features/shell/game_loader.dart';

class _Tokens implements TokenSource {
  @override
  String? accessToken = 'access';

  @override
  Future<void> refreshOnce() async {}
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

/// 기본 온보딩(운동 · 공부) 직후 서버가 돌려줄 법한 응답 — 명세 v5 필드 이름 그대로.
Map<String, Object> _server({bool checkedIn = false, String date = '2026-10-18'}) => {
      'GET /me/status': {
        'businessDate': date, 'dayCount': 3, 'currentStreak': 2, 'gold': 120, 'ballCount': 2,
        'checkedInToday': checkedIn, 'exploreRemaining': checkedIn ? 2 : 0, 'exploreTotal': checkedIn ? 3 : 0,
        'endedHabitCount': 0,
      },
      'GET /me/today': {
        'businessDate': date, 'checkedIn': checkedIn, 'goldEarned': checkedIn ? 13 : null,
        'overallRate': checkedIn ? 65 : null,
        'habits': [
          {
            'habitId': 100, 'name': '아침 러닝', 'categoryCode': 'ex', 'unit': '분', 'dailyTarget': 30,
            'rewardedValue': checkedIn ? 20 : null, 'rewardedScore': checkedIn ? 13 : null,
            'counted': checkedIn ? true : null, 'filledDays': 0, 'periodDays': 30,
          },
        ],
      },
      'GET /categories': [
        for (final (code, opened) in [('ex', true), ('st', true), ('fd', false), ('md', false), ('sl', false), ('mn', false)])
          {'code': code, 'opened': opened},
      ],
      'GET /monsters': [
        {'userMonsterId': 10, 'imageKey': 'monkey', 'location': 'FIELD', 'isPartner': false},
        {'userMonsterId': 11, 'imageKey': 'mouse', 'location': 'BAG', 'isPartner': true},
        {'userMonsterId': 12, 'imageKey': 'unknown_new_species', 'location': 'BAG', 'isPartner': false},
      ],
      'GET /monsters/10': {
        'userMonsterId': 10, 'imageKey': 'monkey', 'level': 7, 'expInLevel': 40, 'expRequired': 125, 'affection': 6,
        'todayActions': {'pet': true, 'play': false}, 'location': 'FIELD', 'isPartner': false,
      },
      'GET /monsters/11': {
        'userMonsterId': 11, 'imageKey': 'mouse', 'level': 1, 'expInLevel': 0, 'expRequired': 125, 'affection': 3,
        'todayActions': {'pet': false, 'play': false}, 'location': 'BAG', 'isPartner': true,
      },
      'GET /inventory': {
        'items': [
          {'itemCode': 'POTION_M', 'name': '중급 경험치 물약', 'quantity': 2},
          {'itemCode': 'BALL', 'name': '성실볼', 'quantity': 2},
        ],
      },
      'GET /habits': [
        {
          'habitId': 100, 'categoryCode': 'ex', 'name': '아침 러닝', 'measureTypeId': 1, 'unit': '분', 'dailyTarget': 30,
          'periodCode': 'D30', 'startDate': date, 'filledDays': 0, 'periodDays': 30, 'status': 'ACTIVE',
        },
        {
          'habitId': 101, 'categoryCode': 'st', 'name': '오늘 복습', 'measureTypeId': 6, 'unit': '점', 'dailyTarget': 4,
          'periodCode': 'D100', 'startDate': date, 'filledDays': 0, 'periodDays': 100, 'status': 'ACTIVE',
        },
      ],
      'GET /goals': {
        'weekly': {
          'periodStart': '2026-10-12', 'slotsTotal': 3, 'slotsUsed': 2, 'rewardGold': 40,
          'goals': [
            {'goalId': 200, 'title': '헬스장 3번 가기', 'detail': null, 'status': 'ACTIVE'},
            {'goalId': 201, 'title': '책 1권', 'detail': '소설', 'status': 'COMPLETED'},
          ],
        },
        'monthly': {'periodStart': '2026-10-01', 'slotsTotal': 1, 'slotsUsed': 0, 'rewardGold': 150, 'goals': []},
      },
      // 실제 시드와 같은 id: 카테고리 안 순서대로
      'GET /measure-types': [
        {'categoryCode': 'ex', 'measureTypes': [{'id': 1}, {'id': 2}, {'id': 3}], 'presets': []},
        {'categoryCode': 'st', 'measureTypes': [{'id': 4}, {'id': 5}, {'id': 6}], 'presets': []},
        {'categoryCode': 'fd', 'measureTypes': [{'id': 7}, {'id': 8}, {'id': 9}, {'id': 10}, {'id': 11}], 'presets': []},
      ],
      'POST /onboarding': {'starters': [], 'partnerMonsterId': 11, 'habitIds': [100], 'goalIds': [200]},
      'POST /me/attendance': {'date': date, 'alreadyAttended': false, 'currentStreak': 3, 'longestStreak': 9},
    };

void main() {
  late List<http.Request> requests;

  HttpGameRepository repo(GameState state, Map<String, Object> routes) {
    requests = [];
    final api = ApiClient(
      baseUrl: 'http://server.test/api/v1',
      tokens: _Tokens(),
      retryDelay: Duration.zero,
      client: MockClient((r) async {
        requests.add(r);
        final key = '${r.method} ${r.url.path.replaceFirst('/api/v1', '')}';
        final body = routes[key];
        return body == null ? _json({'code': 'NOT_FOUND', 'message': '없음'}, 404) : _json(body, key == 'POST /onboarding' ? 201 : 200);
      }),
    );
    return HttpGameRepository(state, api);
  }

  test('load()가 서버 응답으로 빈 GameState를 채운다', () async {
    final s = GameState.empty();
    expect(s.loaded, isFalse);
    await repo(s, _server()).load();

    expect(s.loaded, isTrue);
    expect(s.gold, 120);
    expect(s.balls, 2);
    expect(s.dayCount, 3);
    expect(s.currentStreak, 2); // 아직 오늘 출석 전
    expect(s.checkedInToday, isFalse);
    expect(s.encountersLeft, 0);
    expect(s.pickedCategories, ['ex', 'st']);
    expect(s.inventory, {'s': 0, 'm': 2, 'l': 0});

    // 모르는 종(앱 그림이 없는 종)은 건너뛴다
    expect(s.monsters.map((m) => m.uid), ['10', '11']);
    final monkey = s.monsterByUid('10')!;
    expect((monkey.speciesId, monkey.level, monkey.exp, monkey.affection), ('monkey', 7, 40, 6));
    expect((monkey.inField, monkey.pettedToday, monkey.playedToday), (true, true, false));
    expect(s.monsterByUid('11')!.inField, isFalse);
    expect(s.chatPartnerUid, '11');
    expect(s.caughtSpecies, containsAll(['monkey', 'mouse']));

    expect(s.habits.map((h) => (h.id, h.categoryId, h.measureIndex, h.target, h.periodIndex)),
        [('100', 'ex', 0, 30.0, 1), ('101', 'st', 2, 4.0, 2)]);
    expect(s.goals.map((g) => (g.id, g.tier, g.title, g.detail, g.done)), [
      ('200', GoalTier.weekly, '헬스장 3번 가기', '', false),
      ('201', GoalTier.weekly, '책 1권', '소설', true),
    ]);

    // 몬스터 상세는 마리마다, 측정 항목 표는 한 번
    final paths = requests.map((r) => r.url.path).toList();
    expect(paths, containsAll(['/api/v1/monsters/10', '/api/v1/monsters/11']));
    expect(paths.where((p) => p.endsWith('/measure-types')), hasLength(1));
    expect(requests.every((r) => r.method == 'GET'), isTrue);
  });

  test('체크인한 날이면 첫 제출 값 · 점수 · 반영 여부를 옮긴다', () async {
    final s = GameState.empty();
    await repo(s, _server(checkedIn: true)).load();

    expect(s.checkedInToday, isTrue);
    expect(s.encountersLeft, 2);
    expect(s.todayRecords, {'100': 20.0});
    expect(s.rewardedScores, {'100': 13});
    expect(s.countedToday, {'100'});
    expect(s.todayScore, 13);
  });

  test('온보딩은 측정 항목을 서버 id로 바꿔 한 번에 보내고, 끝나면 다시 불러온다', () async {
    final s = GameState.empty();
    await repo(s, _server()).completeOnboarding(
      picked: ['fd', 'ex'],
      habits: [
        Habit(id: 'oh0', name: '영양제 먹기', categoryId: 'fd', measureIndex: 2, target: 1, periodIndex: 0),
        Habit(id: 'oh1', name: '스쿼트', categoryId: 'ex', measureIndex: 1, target: 30, periodIndex: 2),
      ],
      goals: [Goal(id: 'og0', tier: GoalTier.monthly, title: '책 2권')],
      starterCategory: 'fd',
    );

    final post = requests.firstWhere((r) => r.method == 'POST');
    expect(post.url.path, '/api/v1/onboarding');
    expect(post.headers['Idempotency-Key'], isNotEmpty);
    expect(jsonDecode(post.body), {
      'categories': ['fd', 'ex'],
      'partnerCategory': 'fd',
      'habits': [
        {'categoryCode': 'fd', 'measureTypeId': 9, 'name': '영양제 먹기', 'dailyTarget': 1.0, 'periodCode': 'D7'},
        {'categoryCode': 'ex', 'measureTypeId': 2, 'name': '스쿼트', 'dailyTarget': 30.0, 'periodCode': 'D100'},
      ],
      'goals': [
        {'goalType': 'MONTHLY', 'title': '책 2권'},
      ],
    });
    expect(s.loaded, isTrue); // 제출 뒤 load()
    expect(requests.last.method, 'GET');
  });

  test('출석: 오늘 포함 연속 일수를 반영, 날짜가 바뀌어 돌아왔으면 다시 불러온다', () async {
    final s = GameState.empty();
    final routes = _server();
    final r = repo(s, routes);
    await r.load();

    expect(await r.attend(), isTrue);
    expect(s.attendedToday, isTrue);
    expect(s.currentStreak, 3);

    routes['POST /me/attendance'] = {'date': '2026-10-19', 'alreadyAttended': false, 'currentStreak': 4, 'longestStreak': 9};
    final before = requests.length;
    await r.attend();
    expect(requests.skip(before).where((q) => q.url.path.endsWith('/me/status')), hasLength(1));
    expect(s.currentStreak, 4);
  });

  test('아직 서버 API가 없는 동작은 앱 안에서 계산한다 (3-5 전)', () async {
    final s = GameState.empty()..gold = 100;
    final r = repo(s, _server());
    expect(await r.buy(const ShopItem(id: 's', name: '하급', short: '하급', price: 20, exp: 20, asset: '')), isTrue);
    expect(s.gold, 80);
    expect(requests, isEmpty);
  });

  group('GameLoader', () {
    Widget app(GameState s, GameRepository r) => MaterialApp(
          home: GameScope(
            notifier: s,
            child: GameRepositoryScope(repository: r, child: const GameLoader(child: Text('홈'))),
          ),
        );

    testWidgets('빈 상태면 불러오는 동안 로딩, 끝나면 홈', (tester) async {
      final s = GameState.empty();
      await tester.pumpWidget(app(s, _SlowRepo(s)));
      expect(find.text('몬스터들을 깨우는 중…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('홈'), findsOneWidget);
    });

    testWidgets('실패하면 문구와 다시 시도 버튼', (tester) async {
      final s = GameState.empty();
      final r = _SlowRepo(s, fail: true);
      await tester.pumpWidget(app(s, r));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(ApiException.network.message), findsOneWidget);
      r.fail = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('홈'), findsOneWidget);
    });

    testWidgets('샘플 상태(서버 없음)는 바로 홈', (tester) async {
      final s = GameState.sample();
      await tester.pumpWidget(app(s, LocalGameRepository(s)));
      expect(find.text('홈'), findsOneWidget);
    });
  });
}

class _SlowRepo extends LocalGameRepository {
  _SlowRepo(super.state, {this.fail = false});

  bool fail;

  @override
  Future<void> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (fail) throw ApiException.network;
    state.markLoaded();
  }
}
