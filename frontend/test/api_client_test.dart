import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:habit_monster/core/api/api_client.dart';
import 'package:habit_monster/core/api/api_exception.dart';
import 'package:habit_monster/core/api/idempotency_key.dart';
import 'package:habit_monster/data/catalog.dart';

class _Tokens implements TokenSource {
  @override
  String? accessToken = 'old';
  int refreshes = 0;
  bool fail = false;

  @override
  Future<void> refreshOnce() async {
    refreshes++;
    if (fail) throw Exception('refresh 실패');
    accessToken = 'new';
  }
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

http.Response _err(String code, int status) => _json({'code': code, 'message': '$code 문구'}, status);

void main() {
  late List<http.Request> requests;
  late _Tokens tokens;

  ApiClient client(Future<http.Response> Function(http.Request r) handler, {void Function()? onDateChanged}) {
    requests = [];
    return ApiClient(
      baseUrl: 'http://server.test/api/v1',
      tokens: tokens,
      retryDelay: Duration.zero,
      onBusinessDateChanged: onDateChanged,
      client: MockClient((r) {
        requests.add(r);
        return handler(r);
      }),
    );
  }

  setUp(() => tokens = _Tokens());

  test('Bearer · JSON 본문 · 쿼리를 붙여 보낸다', () async {
    final c = client((r) async => _json({'gold': 340}));
    final res = await c.send('POST', '/shop/purchases', body: {'itemCode': 'BALL', 'quantity': 1}, query: {'x': '1'});
    expect(res, {'gold': 340});
    final r = requests.single;
    expect(r.url.toString(), 'http://server.test/api/v1/shop/purchases?x=1');
    expect(r.headers['Authorization'], 'Bearer old');
    expect(jsonDecode(r.body), {'itemCode': 'BALL', 'quantity': 1});
    expect(r.headers.containsKey('Idempotency-Key'), isFalse);
  });

  test('중복 방지 키: 요청마다 새 키, 연결이 끊겨 다시 보낼 땐 같은 키', () async {
    var calls = 0;
    final c = client((r) async {
      calls++;
      if (calls == 1) throw http.ClientException('끊김');
      return _json({'ok': true});
    });
    await c.send('POST', '/explores', body: {}, idempotent: true);
    expect(requests, hasLength(2));
    final k1 = requests[0].headers['Idempotency-Key'];
    expect(k1, isNotNull);
    expect(requests[1].headers['Idempotency-Key'], k1);

    requests.clear();
    await c.send('POST', '/explores', body: {}, idempotent: true);
    expect(requests.single.headers['Idempotency-Key'], isNot(k1));
  });

  test('처리 중(409 REQUEST_IN_PROGRESS)이면 같은 키로 다시', () async {
    var calls = 0;
    final c = client((r) async => ++calls == 1 ? _err('REQUEST_IN_PROGRESS', 409) : _json({'ok': true}));
    expect(await c.send('POST', '/checkins/today', body: {}, idempotent: true), {'ok': true});
    expect(requests[0].headers['Idempotency-Key'], requests[1].headers['Idempotency-Key']);
  });

  test('키가 없는 쓰기 요청은 연결이 끊겨도 다시 보내지 않는다 (두 번 처리될 수 있어서)', () async {
    final c = client((r) async => throw http.ClientException('끊김'));
    await expectLater(c.send('PATCH', '/goals/1', body: {}),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK')));
    expect(requests, hasLength(1));
  });

  test('TOKEN_EXPIRED면 한 번 재발급하고 새 토큰으로 다시, INVALID_TOKEN은 그대로', () async {
    final c = client((r) async => r.headers['Authorization'] == 'Bearer old' ? _err('TOKEN_EXPIRED', 401) : _json({}));
    await c.get('/me/status');
    expect(tokens.refreshes, 1);
    expect(requests.last.headers['Authorization'], 'Bearer new');

    tokens = _Tokens();
    final c2 = client((r) async => _err('INVALID_TOKEN', 401));
    await expectLater(c2.get('/me/status'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_TOKEN')));
    expect(tokens.refreshes, 0);
  });

  test('재발급이 실패하면 INVALID_TOKEN (로그인 화면으로)', () async {
    tokens.fail = true;
    final c = client((r) async => _err('TOKEN_EXPIRED', 401));
    await expectLater(c.get('/me/status'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_TOKEN')));
  });

  test('날짜가 바뀌었으면(409 BUSINESS_DATE_CHANGED) 새로 불러오라고 알린다', () async {
    var reloads = 0;
    final c = client((r) async => _err('BUSINESS_DATE_CHANGED', 409), onDateChanged: () => reloads++);
    await expectLater(c.send('POST', '/explores', body: {}, idempotent: true),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)));
    expect(reloads, 1);
    expect(requests, hasLength(1)); // 다시 보내지 않음
  });

  test('오류 응답 {code, message, provider} → ApiException, 형식을 모르면 SERVER', () async {
    final c = client((r) async => _json({'code': 'NOT_ENOUGH_GOLD', 'message': '골드가 부족해요'}, 422));
    await expectLater(
        c.send('POST', '/shop/purchases', body: {}),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'NOT_ENOUGH_GOLD')
            .having((e) => e.message, 'message', '골드가 부족해요')
            .having((e) => e.status, 'status', 422)));

    final c2 = client((r) async => http.Response('<html>502</html>', 502));
    await expectLater(c2.get('/x'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'SERVER')));
  });

  test('UUID v4 모양', () {
    final k = newIdempotencyKey();
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(k), isTrue);
    expect(newIdempotencyKey(), isNot(k));
  });

  test('상점 아이템 코드: 서버 ↔ 앱', () {
    expect(Catalog.serverCodeOf(Catalog.seongsilBall), 'BALL');
    expect(Catalog.serverCodeOf(Catalog.items.first), 'POTION_S');
    expect(Catalog.itemByServerCode('POTION_L')?.id, 'l');
    expect(Catalog.itemByServerCode('NOPE'), isNull);
  });
}
