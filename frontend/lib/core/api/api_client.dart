import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'idempotency_key.dart';

/// 지금 access 토큰을 주고, 만료되면 다시 받아 오는 쪽 (로그인 — [HttpAuthService]).
/// 재발급은 앱 전체에서 한 번에 하나만 하므로, 게임 API도 로그인 쪽 재발급을 같이 쓴다.
abstract class TokenSource {
  String? get accessToken;

  /// refresh 토큰으로 access를 다시 받는다. 이미 진행 중이면 그 결과를 기다린다. 실패하면 예외.
  Future<void> refreshOnce();
}

/// 게임 API(`/api/v1/…`)를 부르는 공용 통신기. 서버 공통 규칙(API 명세 v5 "공통 규칙")을 한곳에서 지킨다.
///
/// - `Authorization: Bearer <access>`를 붙인다.
/// - [idempotent] 요청엔 `Idempotency-Key`를 새로 만들어 붙이고, **다시 보낼 때는 같은 키**를 쓴다.
/// - 401 `TOKEN_EXPIRED`면 한 번 재발급하고 다시 보낸다. `INVALID_TOKEN`은 그대로 올린다 (로그인 화면으로).
/// - 연결이 끊겼거나(NETWORK) 같은 키가 처리 중(409 `REQUEST_IN_PROGRESS`)이면 잠시 뒤 같은 키로 다시 보낸다.
///   (같은 키라서 서버가 두 번 처리하지 않는다. 키가 없는 쓰기 요청은 다시 보내지 않는다.)
/// - 409 `BUSINESS_DATE_CHANGED`면 [onBusinessDateChanged]를 불러 화면을 새로 불러오게 한다.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.tokens,
    http.Client? client,
    this.onBusinessDateChanged,
    this.retryDelay = const Duration(milliseconds: 800),
    this.maxRetries = 2,
  })  : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl),
        _client = client ?? http.Client();

  final Uri _base;
  final http.Client _client;
  final TokenSource tokens;

  /// 날짜가 바뀌어 서버가 요청을 거절했을 때 (앱: 오늘 데이터를 다시 불러온다).
  void Function()? onBusinessDateChanged;

  final Duration retryDelay;
  final int maxRetries;

  static const _timeout = Duration(seconds: 15);
  static const _relogin = ApiException('INVALID_TOKEN', '다시 로그인해 주세요', status: 401);

  Future<Object?> get(String path, {Map<String, String>? query}) => send('GET', path, query: query);

  /// 요청을 보내고 JSON 본문을 돌려준다 (204면 null). 실패하면 [ApiException].
  Future<Object?> send(String method, String path,
      {Object? body, Map<String, String>? query, bool idempotent = false}) async {
    final key = idempotent ? newIdempotencyKey() : null;
    final safeToRepeat = key != null || method == 'GET';
    var refreshed = false;
    var retries = 0;
    while (true) {
      try {
        return await _once(method, path, body, query, key);
      } on ApiException catch (e) {
        if (e.code == 'TOKEN_EXPIRED' && !refreshed) {
          refreshed = true;
          try {
            await tokens.refreshOnce();
          } catch (_) {
            throw _relogin;
          }
          continue;
        }
        final busy = e.code == 'NETWORK' || e.code == 'REQUEST_IN_PROGRESS';
        if (busy && safeToRepeat && retries < maxRetries) {
          retries++;
          await Future<void>.delayed(retryDelay);
          continue;
        }
        if (e.code == 'BUSINESS_DATE_CHANGED') onBusinessDateChanged?.call();
        rethrow;
      }
    }
  }

  Future<Object?> _once(String method, String path, Object? body, Map<String, String>? query, String? key) async {
    final uri = _base.replace(path: '${_base.path}$path', queryParameters: query);
    final req = http.Request(method, uri);
    if (body != null) {
      req
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    final access = tokens.accessToken;
    if (access != null) req.headers['Authorization'] = 'Bearer $access';
    if (key != null) req.headers['Idempotency-Key'] = key;

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(_timeout));
    } catch (_) {
      throw ApiException.network;
    }

    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return text.isEmpty ? null : jsonDecode(text);
    }
    Map<String, dynamic>? err;
    try {
      err = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      err = null;
    }
    if (err == null || err['code'] is! String) {
      throw ApiException('SERVER', '서버 오류가 났어요 (${res.statusCode})', status: res.statusCode);
    }
    throw ApiException(err['code'] as String, (err['message'] as String?) ?? '',
        status: res.statusCode, provider: err['provider'] as String?);
  }
}
