import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_service.dart';

/// 이 기기에 남겨 두는 로그인 편의 설정 (기획 2026-10-29-로그인-편의).
/// 비밀번호는 저장하지 않는다 — 자동 로그인은 refresh 토큰([TokenStore])으로 한다.
class LoginPrefs {
  const LoginPrefs({this.lastProvider, this.savedEmail, this.rememberEmail = true, this.autoLogin = true});

  /// 마지막으로 로그인에 성공한 수단 (로그인 화면 말풍선). 로그아웃해도 남는다.
  final AuthProvider? lastProvider;

  /// "아이디 저장"을 켜고 로그인한 이메일 (이메일 화면에 미리 채운다).
  final String? savedEmail;

  final bool rememberEmail;

  /// 꺼져 있으면 앱을 켤 때 저장된 로그인을 쓰지 않는다.
  final bool autoLogin;
}

/// [LoginPrefs] 보관함. 앱에선 폰의 안전한 저장소, 테스트 · 기본값은 메모리.
abstract class LoginPrefsStore {
  Future<LoginPrefs> read();
  Future<void> write(LoginPrefs prefs);
}

class MemoryLoginPrefsStore implements LoginPrefsStore {
  MemoryLoginPrefsStore([this.value = const LoginPrefs()]);
  LoginPrefs value;

  @override
  Future<LoginPrefs> read() async => value;

  @override
  Future<void> write(LoginPrefs prefs) async => value = prefs;
}

/// refresh 토큰과 같은 저장소(flutter_secure_storage)에 키 4개로 둔다.
class SecureLoginPrefsStore implements LoginPrefsStore {
  static const _provider = 'login_last_provider';
  static const _email = 'login_saved_email';
  static const _remember = 'login_remember_email';
  static const _auto = 'login_auto';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<LoginPrefs> read() async {
    final all = await _storage.readAll();
    final p = all[_provider];
    return LoginPrefs(
      lastProvider: AuthProvider.values.where((e) => e.name == p).firstOrNull,
      savedEmail: all[_email],
      rememberEmail: all[_remember] != 'false',
      autoLogin: all[_auto] != 'false',
    );
  }

  @override
  Future<void> write(LoginPrefs prefs) async {
    Future<void> put(String key, String? v) => v == null ? _storage.delete(key: key) : _storage.write(key: key, value: v);
    await put(_provider, prefs.lastProvider?.name);
    await put(_email, prefs.savedEmail);
    await put(_remember, '${prefs.rememberEmail}');
    await put(_auto, '${prefs.autoLogin}');
  }
}
