import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'social_login.dart';

/// refresh 토큰 보관함. 앱에선 폰의 안전한 저장소, 테스트에선 메모리.
abstract class TokenStore {
  Future<String?> readRefresh();
  Future<void> writeRefresh(String token);
  Future<void> clear();
}

/// Android Keystore / iOS Keychain에 저장 (flutter_secure_storage).
class SecureTokenStore implements TokenStore {
  static const _key = 'refresh_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> readRefresh() => _storage.read(key: _key);

  @override
  Future<void> writeRefresh(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemoryTokenStore implements TokenStore {
  String? value;

  @override
  Future<String?> readRefresh() async => value;

  @override
  Future<void> writeRefresh(String token) async => value = token;

  @override
  Future<void> clear() async => value = null;
}

/// Spring 서버(backend/server)의 인증 API(API 명세 v5 "1. 회원 · 설정")를 부르는 [AuthService].
/// 오류 응답 `{code, message}`는 그대로 [AuthException]이 되어 화면에 message가 뜬다.
///
/// 로그인 응답에는 토큰과 온보딩 여부만 오므로, 계정 정보(이메일 · 가입 방법)는 로그인 직후 `GET /me`로 받는다.
class HttpAuthService implements AuthService {
  HttpAuthService({
    required String baseUrl,
    required this.social,
    TokenStore? store,
    http.Client? client,
  })  : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl),
        store = store ?? SecureTokenStore(),
        _client = client ?? http.Client();

  final Uri _base;
  final SocialLogin social;
  final TokenStore store;
  final http.Client _client;

  /// 가장 최근 access 토큰 (30분짜리). 만료되면 refresh로 다시 받는다.
  String? _accessToken;

  /// 진행 중인 토큰 재발급. 요청 여러 개가 동시에 만료돼도 재발급은 한 번만 한다 —
  /// refresh 토큰은 쓸 때마다 바뀌어서, 두 번 동시에 쓰면 두 번째가 "재사용"으로 걸려 로그아웃되기 때문 (API 명세 공통 규칙).
  Future<void>? _refreshing;

  static const _timeout = Duration(seconds: 15);
  static const _network = AuthException('NETWORK', '서버에 연결할 수 없어요. 잠시 후 다시 시도해 주세요');
  static const _relogin = AuthException('INVALID_TOKEN', '다시 로그인해 주세요');

  @override
  Future<AuthSession?> restore() async {
    final refresh = await store.readRefresh();
    if (refresh == null) return null;
    try {
      await _rotate(refresh);
      return await _me();
    } on AuthException catch (e) {
      // 토큰이 만료 · 폐기됐으면 지우고 로그인 화면으로. 서버가 꺼져 있을 땐 토큰은 남겨 둔다.
      if (e.code != 'NETWORK') await store.clear();
      return null;
    }
  }

  @override
  Future<AuthSession> signUpWithEmail({required String email, required String password}) =>
      _login('/auth/signup', {'email': email, 'password': password});

  @override
  Future<AuthSession> signInWithEmail({required String email, required String password}) =>
      _login('/auth/login', {'email': email, 'password': password});

  @override
  Future<AuthSession> signInWithProvider(AuthProvider provider) async {
    final token = await social.token(provider);
    return _login('/auth/social/${provider.name}', {'providerToken': token});
  }

  @override
  Future<void> completeOnboarding(AuthSession session) async {
    _accessToken ??= session.accessToken;
    // 본문 없음: 서버가 완료 시각(onboarded_at)을 찍는다. 3단계에서 POST /onboarding(일괄 제출)으로 바뀐다.
    await _authed('PATCH', '/me/onboarding', const {});
  }

  @override
  Future<void> signOut(AuthSession session) async {
    final refresh = await store.readRefresh();
    await store.clear();
    _accessToken = null;
    if (refresh != null) {
      try {
        await _send('POST', '/auth/logout', {'refreshToken': refresh});
      } on AuthException {
        // 서버에 못 알려도 이 기기에선 로그아웃 (토큰은 이미 지움)
      }
    }
    await social.signOut(session.provider);
  }

  /// 가입 · 로그인 → 토큰 저장 → `GET /me`로 계정 정보.
  Future<AuthSession> _login(String path, Map<String, Object?> body) async {
    final json = await _send('POST', path, body) as Map<String, dynamic>;
    await _keep(json);
    return _me();
  }

  /// refresh 토큰으로 access를 다시 받는다 (refresh도 새것으로 바뀐다).
  Future<void> _rotate(String refresh) async {
    final json = await _send('POST', '/auth/refresh', {'refreshToken': refresh}) as Map<String, dynamic>;
    await _keep(json);
  }

  Future<void> _keep(Map<String, dynamic> json) async {
    _accessToken = json['accessToken'] as String;
    await store.writeRefresh(json['refreshToken'] as String);
  }

  /// 재발급을 한 번만 진행하고, 동시에 부른 쪽은 같은 결과를 기다린다.
  Future<void> _refreshOnce() => _refreshing ??= () async {
        try {
          final refresh = await store.readRefresh();
          if (refresh == null) throw _relogin;
          await _rotate(refresh);
        } finally {
          _refreshing = null;
        }
      }();

  /// 로그인이 필요한 요청. access가 만료(TOKEN_EXPIRED)일 때만 한 번 재발급하고 다시 보낸다.
  /// 위조 · 폐기(INVALID_TOKEN)는 재발급해도 소용없으므로 그대로 올려 보낸다 → 로그인 화면.
  Future<Object?> _authed(String method, String path, Map<String, Object?>? body) async {
    try {
      return await _send(method, path, body, access: _accessToken);
    } on AuthException catch (e) {
      if (e.code != 'TOKEN_EXPIRED') rethrow;
      await _refreshOnce();
      return _send(method, path, body, access: _accessToken);
    }
  }

  Future<AuthSession> _me() async {
    final me = await _authed('GET', '/me', null) as Map<String, dynamic>;
    return AuthSession(
      userId: '${me['userId']}',
      provider: AuthProvider.values.byName((me['provider'] as String).toLowerCase()),
      email: me['email'] as String?,
      onboardingDone: me['onboarded'] as bool? ?? false,
      accessToken: _accessToken!,
      refreshToken: (await store.readRefresh())!,
    );
  }

  /// 요청을 보내고 JSON 본문을 돌려준다 (204면 null). 실패하면 [AuthException].
  Future<Object?> _send(String method, String path, Map<String, Object?>? body, {String? access}) async {
    final req = http.Request(method, _base.replace(path: '${_base.path}$path'));
    if (body != null) {
      req
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    if (access != null) req.headers['Authorization'] = 'Bearer $access';

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(_timeout));
    } on TimeoutException {
      throw _network;
    } on http.ClientException {
      throw _network;
    } catch (_) {
      throw _network;
    }

    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return text.isEmpty ? null : jsonDecode(text);
    }
    try {
      final err = jsonDecode(text) as Map<String, dynamic>;
      throw AuthException(err['code'] as String, err['message'] as String);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw AuthException('SERVER', '서버 오류가 났어요 (${res.statusCode})');
    }
  }
}
