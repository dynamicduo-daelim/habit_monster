import 'dart:async';
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

/// 로그인 계열 응답 (API 명세 v5): 토큰 + 온보딩 여부만.
Map<String, Object?> _tokens(String access, String refresh, {bool onboarded = false}) =>
    {'accessToken': access, 'refreshToken': refresh, 'onboarded': onboarded};

/// GET /me 응답.
Map<String, Object?> _me({String provider = 'EMAIL', bool onboarded = false}) =>
    {'userId': 7, 'email': 'me@habit.kr', 'provider': provider, 'onboarded': onboarded};

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

http.Response _expired() => _json({'code': 'TOKEN_EXPIRED', 'message': '로그인이 만료됐어요'}, 401);

void main() {
  late List<http.Request> requests;
  late MemoryTokenStore store;
  late _FakeSocial social;

  HttpAuthService service(Future<http.Response> Function(http.Request r) handler) {
    requests = [];
    return HttpAuthService(
      baseUrl: 'http://server.test/api/v1/',
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

  test('이메일 로그인: 토큰 저장 → GET /me로 계정 정보', () async {
    final s = service((r) async =>
        r.url.path.endsWith('/me') ? _json(_me(onboarded: true)) : _json(_tokens('a1', 'r1', onboarded: true)));
    final session = await s.signInWithEmail(email: 'me@habit.kr', password: 'password1');
    expect(requests.map((r) => '${r.method} ${r.url}'), [
      'POST http://server.test/api/v1/auth/login',
      'GET http://server.test/api/v1/me',
    ]);
    expect(jsonDecode(requests.first.body), {'email': 'me@habit.kr', 'password': 'password1'});
    expect(requests.last.headers['Authorization'], 'Bearer a1');
    expect(session.userId, '7');
    expect(session.provider, AuthProvider.email);
    expect(session.email, 'me@habit.kr');
    expect(session.onboardingDone, isTrue);
    expect(session.refreshToken, 'r1');
    expect(store.value, 'r1');
  });

  test('서버 오류 {code, message} → AuthException 그대로', () async {
    final s = service((r) async => _json({
          'code': 'EMAIL_REGISTERED_WITH_OTHER_METHOD',
          'message': '카카오로 가입된 이메일이에요. 카카오로 로그인해 주세요',
          'provider': 'kakao',
        }, 409));
    expect(
      s.signUpWithEmail(email: 'me@habit.kr', password: 'password1'),
      throwsA(isA<AuthException>()
          .having((e) => e.code, 'code', 'EMAIL_REGISTERED_WITH_OTHER_METHOD')
          .having((e) => e.message, 'message', '카카오로 가입된 이메일이에요. 카카오로 로그인해 주세요')),
    );
  });

  test('서버에 연결 못 하면 NETWORK', () async {
    final s = service((r) async => throw http.ClientException('connection refused'));
    expect(s.signInWithEmail(email: 'a@b.co', password: 'password1'),
        throwsA(isA<AuthException>().having((e) => e.code, 'code', 'NETWORK')));
  });

  test('카카오: SDK 토큰을 providerToken으로', () async {
    final s = service((r) async =>
        r.url.path.endsWith('/me') ? _json(_me(provider: 'KAKAO')) : _json({..._tokens('a1', 'r1'), 'isNewUser': true}));
    final session = await s.signInWithProvider(AuthProvider.kakao);
    expect(requests.first.url.path, '/api/v1/auth/social/kakao');
    expect(jsonDecode(requests.first.body), {'providerToken': 'kakao-sdk-token'});
    expect(session.provider, AuthProvider.kakao);
  });

  test('소셜 취소면 서버를 부르지 않음', () async {
    social.fail = const AuthException('CANCELED', '로그인을 취소했어요');
    final s = service((r) async => _json(_tokens('a1', 'r1')));
    await expectLater(s.signInWithProvider(AuthProvider.google),
        throwsA(isA<AuthException>().having((e) => e.code, 'code', 'CANCELED')));
    expect(requests, isEmpty);
  });

  test('앱 시작: 저장된 refresh로 재발급 → GET /me, 폐기된 토큰이면 지우고 로그인 화면', () async {
    store.value = 'r0';
    var s = service((r) async => r.url.path.endsWith('/me') ? _json(_me(onboarded: true)) : _json(_tokens('a1', 'r1')));
    final session = await s.restore();
    expect(requests.first.url.path, '/api/v1/auth/refresh');
    expect(jsonDecode(requests.first.body), {'refreshToken': 'r0'});
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

  test('access 만료(TOKEN_EXPIRED)면 한 번 재발급하고 다시 보냄', () async {
    var patches = 0;
    final s = service((r) async {
      if (r.url.path.endsWith('/auth/login')) return _json(_tokens('old', 'r1'));
      if (r.url.path.endsWith('/auth/refresh')) return _json(_tokens('new', 'r2'));
      if (r.url.path.endsWith('/me')) return _json(_me());
      patches++;
      return r.headers['Authorization'] == 'Bearer old' ? _expired() : _json(_me(onboarded: true));
    });
    final session = await s.signInWithEmail(email: 'me@habit.kr', password: 'password1');
    await s.completeOnboarding(session);
    expect(patches, 2);
    expect(requests.last.method, 'PATCH');
    expect(requests.last.headers['Authorization'], 'Bearer new');
    expect(store.value, 'r2');
  });

  test('위조 · 폐기(INVALID_TOKEN)면 재발급하지 않고 그대로 실패', () async {
    final s = service((r) async {
      if (r.url.path.endsWith('/auth/login')) return _json(_tokens('a1', 'r1'));
      if (r.url.path.endsWith('/me')) return _json(_me());
      return _json({'code': 'INVALID_TOKEN', 'message': '다시 로그인해 주세요'}, 401);
    });
    final session = await s.signInWithEmail(email: 'me@habit.kr', password: 'password1');
    await expectLater(s.completeOnboarding(session),
        throwsA(isA<AuthException>().having((e) => e.code, 'code', 'INVALID_TOKEN')));
    expect(requests.where((r) => r.url.path.endsWith('/auth/refresh')), isEmpty);
  });

  test('동시에 여러 요청이 만료돼도 재발급은 한 번만', () async {
    final release = Completer<void>();
    var refreshes = 0;
    final s = service((r) async {
      if (r.url.path.endsWith('/auth/login')) return _json(_tokens('old', 'r1'));
      if (r.url.path.endsWith('/auth/refresh')) {
        refreshes++;
        await release.future; // 재발급이 끝나기 전에 다른 요청도 만료되게
        return _json(_tokens('new', 'r2'));
      }
      if (r.headers['Authorization'] == 'Bearer old' && r.method == 'PATCH') return _expired();
      return _json(_me());
    });
    final session = await s.signInWithEmail(email: 'me@habit.kr', password: 'password1');
    final both = Future.wait([s.completeOnboarding(session), s.completeOnboarding(session)]);
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await both;
    expect(refreshes, 1);
    expect(store.value, 'r2');
  });

  test('로그아웃: 서버에 refresh 폐기 요청 + 저장소 비움 + SDK 로그아웃', () async {
    final s = service((r) async {
      if (r.url.path.endsWith('/auth/logout')) return http.Response('', 204);
      if (r.url.path.endsWith('/me')) return _json(_me(provider: 'GOOGLE'));
      return _json(_tokens('a1', 'r1'));
    });
    final session = await s.signInWithProvider(AuthProvider.google);
    await s.signOut(session);
    expect(requests.last.url.path, '/api/v1/auth/logout');
    expect(jsonDecode(requests.last.body), {'refreshToken': 'r1'});
    expect(store.value, isNull);
    expect(social.signedOut, [AuthProvider.google]);
  });
}
