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

/// Spring 서버(backend/server)의 인증 API를 부르는 [AuthService].
/// 오류 응답 `{code, message}`는 그대로 [AuthException]이 되어 화면에 message가 뜬다.
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

  static const _timeout = Duration(seconds: 15);
  static const _network = AuthException('NETWORK', '서버에 연결할 수 없어요. 잠시 후 다시 시도해 주세요');

  @override
  Future<AuthSession?> restore() async {
    final refresh = await store.readRefresh();
    if (refresh == null) return null;
    try {
      return await _refresh(refresh);
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
    return _login('/auth/social/${provider.name}', {'token': token});
  }

  @override
  Future<void> completeOnboarding(AuthSession session) async {
    const body = <String, Object?>{}; // 본문 없음: 서버가 완료 시각(onboarded_at)을 찍는다
    try {
      await _send('PATCH', '/me/onboarding', body, access: _accessToken ?? session.accessToken);
    } on AuthException catch (e) {
      if (e.code != 'INVALID_TOKEN') rethrow;
      // access 토큰이 만료됐으면 한 번 갱신하고 다시
      final refresh = await store.readRefresh();
      if (refresh == null) rethrow;
      await _refresh(refresh);
      await _send('PATCH', '/me/onboarding', body, access: _accessToken);
    }
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

  Future<AuthSession> _refresh(String refresh) => _login('/auth/refresh', {'refreshToken': refresh});

  Future<AuthSession> _login(String path, Map<String, Object?> body) async {
    final json = await _send('POST', path, body) as Map<String, dynamic>;
    final user = json['user'] as Map<String, dynamic>;
    final session = AuthSession(
      userId: user['id'] as String,
      provider: AuthProvider.values.byName((user['provider'] as String).toLowerCase()),
      email: user['email'] as String?,
      nickname: user['nickname'] as String?,
      onboardingDone: user['onboardingDone'] as bool? ?? false,
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );
    _accessToken = session.accessToken;
    await store.writeRefresh(session.refreshToken);
    return session;
  }

  /// 요청을 보내고 JSON 본문을 돌려준다 (204면 null). 실패하면 [AuthException].
  Future<Object?> _send(String method, String path, Map<String, Object?> body, {String? access}) async {
    final req = http.Request(method, _base.replace(path: '${_base.path}$path'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
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
