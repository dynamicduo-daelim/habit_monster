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
import 'package:habit_monster/data/catalog.dart';
import 'package:habit_monster/data/models.dart';
import 'package:habit_monster/data/results.dart';
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
      'GET /checkins/today': {
        'businessDate': date, 'submitted': checkedIn, 'revision': checkedIn ? 1 : 0,
        'partner': {'userMonsterId': 11, 'name': '찌릿 쥐', 'imageKey': 'mouse', 'affectionTier': 'LOW'},
        'tabs': [
          {
            'categoryCode': 'ex', 'categoryName': '운동',
            'habits': [
              {
                'habitId': 100, 'name': '아침 러닝', 'unit': '분', 'scoringMode': 'TARGET_RATIO',
                'options': [10, 15, 25, 30, 45, 60], 'previousValue': checkedIn ? 20 : null,
                'filledDays': checkedIn ? 1 : 0, 'periodDays': 30,
              },
            ],
          },
          if (!checkedIn)
            {
              'categoryCode': 'st', 'categoryName': '공부',
              'habits': [
                {
                  'habitId': 101, 'name': '오늘 복습', 'unit': '점', 'scoringMode': 'TARGET_RATIO',
                  'options': [1, 2, 3, 4], 'previousValue': null, 'filledDays': 0, 'periodDays': 100,
                },
              ],
            },
        ],
      },
      'POST /checkins/today': {
        'revision': 1,
        'habits': [
          {'habitId': 100, 'score': 17, 'counted': true},
          {'habitId': 101, 'score': 0, 'counted': true},
        ],
        'overallRate': 43, 'goldEarned': 37,
        'goldBreakdown': {'score': 17, 'levelUp': 20, 'periodBonus': 0},
        'categoryExp': [
          {'categoryCode': 'ex', 'expGained': 17, 'levelBefore': 1, 'levelAfter': 2, 'levelUpGold': 20, 'expInLevel': 7, 'expRequired': 20},
          {'categoryCode': 'st', 'expGained': 0, 'levelBefore': 1, 'levelAfter': 1, 'levelUpGold': 0, 'expInLevel': 0, 'expRequired': 10},
        ],
        'periodBonuses': [], 'unlockedSpecies': [], 'exploreTotal': 3, 'gold': 157,
      },
      'PUT /checkins/today': {
        'revision': 2,
        'habits': [
          {'habitId': 100, 'value': 45, 'score': 25},
          {'habitId': 101, 'value': 3, 'score': 15},
        ],
        'overallRate': 88,
      },
    };

/// 라우트 값이 이것이면 204 (본문 없음).
const _noContent = 'NO_CONTENT';

/// 탐색에서 깡총 불토끼(안 가진 종)가 처음 나온 응답 — 명세 v5 모양, 그림은 `imageKey`.
const _rabbit = {
  'exploreId': 500, 'result': 'ENCOUNTER',
  'species': {'speciesId': 2, 'name': '깡총 불토끼', 'imageKey': 'rabbit', 'categoryCode': 'ex', 'rarity': 1, 'captureRate': 0.8},
  'newlySeen': true, 'goldAwarded': 0, 'gold': 157, 'skippedExploreId': null, 'exploreRemaining': 1,
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
        if (body == _noContent) return http.Response('', 204);
        if (body is http.Response) return body; // 오류 응답을 그대로
        return body == null
            ? _json({'code': 'NOT_FOUND', 'message': '없음'}, 404)
            : _json(body, key.startsWith('POST /onboarding') || key == 'POST /checkins/today' ? 201 : 200);
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

  test('체크인 대상 · 선택지를 불러오고, 입력값은 가장 가까운 선택지로 맞춘다', () async {
    final s = GameState.empty();
    await repo(s, _server()).load();

    expect(s.serverCheckinIds, ['100', '101']);
    expect(s.checkinHabits.map((h) => h.id), ['100', '101']);
    final run = s.checkinHabits.first;
    expect(s.checkinOptions['100'], [10, 15, 25, 30, 45, 60]);
    expect(s.recordableValue(run, 27), 25);
    expect(s.recordableValue(run, 20), 15); // 15와 25 사이 같은 거리 → 작은 쪽
    expect(s.recordableValue(run, 500), 60);
    expect(s.recordableValue(run, 0), 0); // 못 했어는 그대로
    expect(GameState.sample().recordableValue(run, 27), 27); // 로컬 모드는 입력값 그대로
  });

  test('체크인 제출: 날짜 · 했는지 · 값을 보내고 서버가 계산한 보상을 그대로 반영한다', () async {
    final s = GameState.empty();
    final r = repo(s, _server());
    await r.load();

    final res = await r.confirmCheckin({'100': 25, '101': 0});
    final post = requests.last;
    expect((post.method, post.url.path), ('POST', '/api/v1/checkins/today'));
    expect(post.headers['Idempotency-Key'], isNotEmpty);
    expect(jsonDecode(post.body), {
      'businessDate': '2026-10-18',
      'answers': [
        {'habitId': 100, 'done': true, 'value': 25.0},
        {'habitId': 101, 'done': false},
      ],
    });

    expect(res!.goldEarned, 37);
    expect(res.levelUps, {'ex': 2});
    expect(res.exploreCount, 3);
    expect(res.scores.map((x) => (x.habit.id, x.value, x.score, x.counted)), [('100', 25.0, 17, true), ('101', 0.0, 0, true)]);
    expect(s.gold, 157);
    expect(s.checkedInToday, isTrue);
    expect(s.encountersLeft, 3);
    expect(s.todayRecords, {'100': 25.0, '101': 0.0});
    expect(s.countedToday, {'100', '101'});
    expect(s.categoryLevel('ex').level, 2);
    expect(s.categoryLevel('ex').current, 7);
    expect(s.exploreCategoriesToday, {'ex', 'st'}); // 연 카테고리 전부 (B4)
  });

  test('다시 체크: 값 · 점수만 바뀌고 골드는 그대로', () async {
    final s = GameState.empty();
    final r = repo(s, _server());
    await r.load();
    await r.confirmCheckin({'100': 25, '101': 0});

    final res = await r.resubmitCheckin({'100': 45, '101': 3});
    expect(requests.last.method, 'PUT');
    expect(res!.goldEarned, 0);
    expect(s.gold, 157);
    expect(s.todayRecords, {'100': 45.0, '101': 3.0});
    expect(s.scoreOf(s.habits.first), 25);
    expect(s.rewardedScores['100'], 17); // 보상 기준은 첫 제출
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

  group('탐색 · 포획 (3-4)', () {
    Future<(GameState, HttpGameRepository, Map<String, Object>)> checkedIn() async {
      final s = GameState.empty();
      final routes = _server(checkedIn: true);
      final r = repo(s, routes);
      await r.load();
      return (s, r, routes);
    }

    test('안 가진 종이 나오면 서버 번호 · 처음 본 종 · 포획률을 담고 도감에 "본 종"으로', () async {
      final (s, r, routes) = await checkedIn();
      routes['POST /explores'] = _rabbit;
      final e = await r.explore();
      final post = requests.last;
      expect((post.method, post.url.path), ('POST', '/api/v1/explores'));
      expect(post.headers['Idempotency-Key'], isNotEmpty);
      expect(jsonDecode(post.body), {'businessDate': '2026-10-18'});
      expect(e!.species!.id, 'rabbit');
      expect((e.exploreId, e.newlySeen, e.captureRate, e.catchable), ('500', true, 0.8, true));
      expect(s.encountersLeft, 1);
      expect(s.discoveredSpecies, contains('rabbit'));
      expect(s.caughtSpecies, isNot(contains('rabbit')));
    });

    test('가진 종은 볼 없이 골드, 꽝은 아무도 없음', () async {
      final (s, r, routes) = await checkedIn();
      routes['POST /explores'] = {
        'exploreId': 501, 'result': 'DUPLICATE',
        'species': {'speciesId': 1, 'name': '불씨 원숭이', 'imageKey': 'monkey', 'categoryCode': 'ex', 'rarity': 1, 'captureRate': null},
        'newlySeen': false, 'goldAwarded': 15, 'gold': 135, 'skippedExploreId': null, 'exploreRemaining': 1,
      };
      final dup = await r.explore();
      expect((dup!.alreadyOwned, dup.gold, dup.catchable), (true, 15, false));
      expect(s.gold, 135);

      routes['POST /explores'] = {
        'exploreId': 502, 'result': 'MISS', 'species': null, 'newlySeen': false, 'goldAwarded': 0, 'gold': 135,
        'skippedExploreId': null, 'exploreRemaining': 0,
      };
      final miss = await r.explore();
      expect(miss!.found, isFalse);
      expect(s.encountersLeft, 0);
      expect(await r.explore(), isNull); // 남은 횟수가 없으면 서버를 부르지 않는다
      expect(requests.where((q) => q.url.path.endsWith('/explores')), hasLength(2));
    });

    test('볼 던지기: 등장 번호로 부르고, 잡으면 새 몬스터 · 남은 볼을 반영', () async {
      final (s, r, routes) = await checkedIn();
      routes['POST /explores'] = _rabbit;
      routes['POST /explores/500/capture'] = {
        'outcome': 'CAPTURED',
        'monster': {'userMonsterId': 15, 'name': '깡총 불토끼', 'imageKey': 'rabbit', 'location': 'BAG'},
        'ballCount': 1, 'dex': {'dexCount': 3, 'newSlotAvailable': false},
      };
      final e = await r.explore();
      final c = await r.throwBall(e!);
      expect(requests.last.url.path, '/api/v1/explores/500/capture');
      expect(requests.last.headers['Idempotency-Key'], isNotEmpty);
      expect((c!.caught, c.toField, c.monster!.uid), (true, false, '15'));
      expect(s.balls, 1);
      expect(s.monsterByUid('15')!.inField, isFalse);
      expect(s.caughtSpecies, contains('rabbit'));
    });

    test('놓치면 볼만 줄고 몬스터는 그대로', () async {
      final (s, r, routes) = await checkedIn();
      routes['POST /explores'] = _rabbit;
      routes['POST /explores/500/capture'] = {
        'outcome': 'ESCAPED', 'monster': null, 'ballCount': 1, 'dex': {'dexCount': 2, 'newSlotAvailable': false},
      };
      final before = s.monsters.length;
      final c = await r.throwBall((await r.explore())!);
      expect(c!.kind, CatchKind.escaped);
      expect(s.balls, 1);
      expect(s.monsters, hasLength(before));
    });

    test('남은 등장: 있으면 되살리고(처음 본 게 아님), 없으면 204 → null', () async {
      final (_, r, routes) = await checkedIn();
      routes['GET /explores/pending'] = _noContent;
      expect(await r.pendingEncounter(), isNull);

      routes['GET /explores/pending'] = {..._rabbit, 'newlySeen': false};
      final e = await r.pendingEncounter();
      expect((e!.exploreId, e.species!.id, e.newlySeen), ('500', 'rabbit', false));
    });
  });

  group('성장 · 교감 (3-5)', () {
    Future<(GameState, HttpGameRepository, Map<String, Object>)> loaded() async {
      final s = GameState.empty();
      final routes = _server();
      final r = repo(s, routes);
      await r.load();
      return (s, r, routes);
    }

    test('구매: 서버 아이템 코드 · 수량을 보내고 골드 · 가방 개수를 서버 값으로', () async {
      final (s, r, routes) = await loaded();
      routes['POST /shop/purchases'] = {'purchaseId': 300, 'totalPrice': 100, 'gold': 20, 'itemCode': 'BALL', 'quantity': 4};
      expect(await r.buy(Catalog.seongsilBall, count: 2), isTrue);
      final post = requests.last;
      expect(post.headers['Idempotency-Key'], isNotEmpty);
      expect(jsonDecode(post.body), {'itemCode': 'BALL', 'quantity': 2});
      expect((s.gold, s.balls), (20, 4));
    });

    test('물약: 레벨은 서버 값, 남은 물약 반영', () async {
      final (s, r, routes) = await loaded();
      final potion = Catalog.itemByServerCode('POTION_M')!;
      routes['POST /monsters/10/feed'] = {
        'expGained': 100, 'levelBefore': 7, 'levelAfter': 8, 'stageBefore': 0, 'stageAfter': 0, 'evolved': false,
        'remainingQuantity': 1,
      };
      final m = s.monsterByUid('10')!;
      expect(await r.feed(m, potion), 1);
      expect(jsonDecode(requests.last.body), {'itemCode': 'POTION_M'});
      expect(requests.last.headers['Idempotency-Key'], isNotEmpty);
      expect((m.level, s.inventory[potion.id]), (8, 1));
    });

    test('교감: 오른 호감도 반영, 오늘 이미 했으면 표시하고 안내 문구를 올린다', () async {
      final (s, r, routes) = await loaded();
      routes['POST /monsters/10/affection'] = {'gain': 1, 'affection': 7, 'affectionTier': 'HIGH'};
      final monkey = s.monsterByUid('10')!;
      expect(await r.play(monkey), 1);
      expect(jsonDecode(requests.last.body), {'action': 'PLAY'});
      expect((monkey.affection, monkey.playedToday), (7, true));

      routes['POST /monsters/11/affection'] =
          _json({'code': 'ALREADY_DONE_TODAY', 'message': '오늘은 이미 했어요. 내일 또 해 주세요'}, 409);
      final mouse = s.monsterByUid('11')!;
      await expectLater(r.pet(mouse), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'ALREADY_DONE_TODAY')));
      expect(mouse.pettedToday, isTrue);
    });

    test('필드/가방: 서버로 옮기고, 필드 마지막 1마리는 서버를 부르지 않고 false', () async {
      final (s, r, routes) = await loaded();
      final monkey = s.monsterByUid('10')!; // 필드에 혼자
      final before = requests.length;
      expect(await r.moveMonster(monkey, toField: false), isFalse);
      expect(requests, hasLength(before));

      routes['PATCH /monsters/11/location'] = {'userMonsterId': 11, 'location': 'FIELD', 'fieldCount': 2};
      final mouse = s.monsterByUid('11')!;
      expect(await r.moveMonster(mouse, toField: true), isTrue);
      expect(jsonDecode(requests.last.body), {'location': 'FIELD'});
      expect(mouse.inField, isTrue);
    });

    test('대화 상대 · 말 걸기는 서버, 필드 끌기 호감도는 서버 모드에서 0 (D-46)', () async {
      final (s, r, routes) = await loaded();
      routes['PUT /me/partner'] = {'partnerMonsterId': 10};
      await r.setPartner(s.monsterByUid('10')!);
      expect(jsonDecode(requests.last.body), {'userMonsterId': 10});
      expect(s.chatPartnerUid, '10');

      routes['GET /monsters/10/line'] = {'affectionTier': 'MID', 'line': '오늘도 뛸 거지?'};
      expect(await r.talk(s.monsterByUid('10')!), '오늘도 뛸 거지?');

      final before = requests.length;
      final monkey = s.monsterByUid('10')!;
      final affection = monkey.affection;
      expect(await r.dragMonster(monkey), 0);
      expect((monkey.affection, requests.length), (affection, before));
    });
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
