import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:habit_monster/core/auth/auth_service.dart';
import 'package:habit_monster/core/auth/http_auth_service.dart';
import 'package:habit_monster/core/auth/social_login.dart';

class _FakeSocial implements SocialLogin {
  final List<AuthProvider> signedOut = [];
  AuthException? fail;

  @override
  Future<String> token(AuthProvider provider) async {
    if (fail != null) throw fail!;
    return '${provider.name}-sdk-token';
  }

  @override
  Future<void> signOut(AuthProvider provider) async => signedOut.add(provider);
}

Map<String, Object?> _authBody(String access, String refresh, {String provider = 'EMAIL', bool done = false}) => {
      'accessToken': access,
      'refreshToken': refresh,
      'user': {'id': '7', 'provider': provider, 'email': 'me@habit.kr', 'nickname': null, 'onboardingDone': done},
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

void main() {
  late List<http.Request> requests;
  late MemoryTokenStore store;
  late _FakeSocial social;

  HttpAuthService service(Future<http.Response> Function(http.Request r) handler) {
    requests = [];
    return HttpAuthService(
      baseUrl: 'http://server.test/',
      social: social,
      store: store,
      client: MockClient((r) {
        requests.add(r);
        return handler(r);
      }),
    );
  }

  setUp(() {
    store = MemoryTokenStore();
    social = _FakeSocial();
  });

  test('이메일 로그인: 응답 → 세션, refresh는 저장소에', () async {
    final s = service((r) async => _json(_authBody('a1', 'r1', done: true)));
    final session = await s.signInWithEmail(email: 'me@habit.kr', password: 'password1');
    expect(requests.single.url.toString(), 'http://server.test/auth/login');
    expect(jsonDecode(requests.single.body), {'email': 'me@habit.kr', 'password': 'password1'});
    expect(session.userId, '7');
    expect(session.provider, AuthProvider.email);
    expect(session.onboardingDone, isTrue);
    expect(store.value, 'r1');
  });

  test('서버 오류 {code, message} → AuthException 그대로', () async {
    final s = service((r) async => _json({'code': 'EMAIL_TAKEN', 'message': '이미 가입된 이메일이에요'}, 409));
    expect(
      s.signUpWithEmail(email: 'me@habit.kr', password: 'password1'),
      throwsA(isA<AuthException>()
          .having((e) => e.code, 'code', 'EMAIL_TAKEN')
          .having((e) => e.message, 'message', '이미 가입된 이메일이에요')),
    );
  });

  test('서버에 연결 못 하면 NETWORK', () async {
    final s = service((r) async => throw http.ClientException('connection refused'));
    expect(s.signInWithEmail(email: 'a@b.co', password: 'password1'),
        throwsA(isA<AuthException>().having((e) => e.code, 'code', 'NETWORK')));
  });

  test('카카오: SDK 토큰을 /auth/social/kakao로', () async {
    final s = service((r) async => _json(_authBody('a1', 'r1', provider: 'KAKAO')));
    final session = await s.signInWithProvider(AuthProvider.kakao);
    expect(requests.single.url.path, '/auth/social/kakao');
    expect(jsonDecode(requests.single.body), {'token': 'kakao-sdk-token'});
    expect(session.provider, AuthProvider.kakao);
  });

  test('소셜 취소면 서버를 부르지 않음', () async {
    social.fail = const AuthException('CANCELED', '로그인을 취소했어요');
    final s = service((r) async => _json(_authBody('a1', 'r1')));
    await expectLater(s.signInWithProvider(AuthProvider.google),
        throwsA(isA<AuthException>().having((e) => e.code, 'code', 'CANCELED')));
    expect(requests, isEmpty);
  });

  test('앱 시작: 저장된 refresh로 자동 로그인, 만료면 지우고 로그인 화면', () async {
    store.value = 'r0';
    var s = service((r) async => _json(_authBody('a1', 'r1', done: true)));
    final session = await s.restore();
    expect(jsonDecode(requests.single.body), {'refreshToken': 'r0'});
    expect(session?.onboardingDone, isTrue);
    expect(store.value, 'r1'); // 교체된 토큰

    s = service((r) async => _json({'code': 'INVALID_TOKEN', 'message': '다시 로그인해 주세요'}, 401));
    expect(await s.restore(), isNull);
    expect(store.value, isNull);
  });

  test('서버가 꺼져 있으면 토큰은 남겨 둔다', () async {
    store.value = 'r0';
    final s = service((r) async => throw http.ClientException('down'));
    expect(await s.restore(), isNull);
    expect(store.value, 'r0');
  });

  test('온보딩 완료: Bearer로 PATCH, access 만료면 갱신 후 다시', () async {
    var patches = 0;
    final s = service((r) async {
      if (r.url.path == '/auth/login') return _json(_authBody('old', 'r1'));
      if (r.url.path == '/auth/refresh') return _json(_authBody('new', 'r2'));
      patches++;
      if (r.headers['Authorization'] == 'Bearer old') {
        return _json({'code': 'INVALID_TOKEN', 'message': '다시 로그인해 주세요'}, 401);
      }
      return _json({'id': '7', 'provider': 'EMAIL', 'onboardingDone': true});
    });
    final session = await s.signInWithEmail(email: 'me@habit.kr', password: 'password1');
    await s.completeOnboarding(session);
    expect(patches, 2);
    expect(requests.last.method, 'PATCH');
    expect(requests.last.headers['Authorization'], 'Bearer new');
    expect(jsonDecode(requests.last.body), isEmpty);
  });

  test('로그아웃: 서버에 refresh 폐기 요청 + 저장소 비움 + SDK 로그아웃', () async {
    final s = service((r) async =>
        r.url.path == '/auth/logout' ? http.Response('', 204) : _json(_authBody('a1', 'r1', provider: 'GOOGLE')));
    final session = await s.signInWithProvider(AuthProvider.google);
    await s.signOut(session);
    expect(requests.last.url.path, '/auth/logout');
    expect(jsonDecode(requests.last.body), {'refreshToken': 'r1'});
    expect(store.value, isNull);
    expect(social.signedOut, [AuthProvider.google]);
  });
}
