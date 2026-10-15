import 'dart:async';

import 'package:flutter/widgets.dart';

/// 로그인 수단 (DB `identity.auth_provider`).
enum AuthProvider { email, kakao, google }

/// 로그인된 사용자. 서버 응답(`backend/README.md` 인증 API)과 같은 모양.
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.provider,
    required this.accessToken,
    required this.refreshToken,
    this.email,
    this.nickname,
    this.onboardingDone = false,
  });

  final String userId;
  final AuthProvider provider;
  final String? email;
  final String? nickname;

  /// 온보딩을 끝냈는지 (DB `identity.users.onboarded_at`이 있으면 끝).
  final bool onboardingDone;

  final String accessToken;
  final String refreshToken;

  AuthSession copyWith({bool? onboardingDone}) => AuthSession(
        userId: userId,
        provider: provider,
        accessToken: accessToken,
        refreshToken: refreshToken,
        email: email,
        nickname: nickname,
        onboardingDone: onboardingDone ?? this.onboardingDone,
      );
}

/// 인증 오류. [code]는 서버 오류 코드와 같다.
class AuthException implements Exception {
  const AuthException(this.code, this.message);

  /// 서버: INVALID_CREDENTIALS · EMAIL_TAKEN · WEAK_PASSWORD · INVALID_EMAIL · INVALID_TOKEN · ACCOUNT_WITHDRAWN …
  /// 앱: CANCELED(사용자 취소) · NETWORK · SOCIAL_FAILED · UNSUPPORTED(웹) · SERVER
  final String code;

  /// 화면에 그대로 보여줄 문구.
  final String message;

  @override
  String toString() => 'AuthException($code)';
}

/// 로그인 · 회원가입 · 로그아웃. 화면은 이 인터페이스만 쓴다.
///
/// `API_BASE_URL`을 주고 빌드하면 [HttpAuthService](Spring 서버 + 카카오 · 구글 SDK),
/// 없으면 [FakeAuthService](앱 안에서만 동작)를 쓴다 — `main.dart`.
abstract class AuthService {
  /// 앱을 켤 때 저장된 로그인 복원 (없으면 null).
  Future<AuthSession?> restore();

  Future<AuthSession> signUpWithEmail({required String email, required String password});
  Future<AuthSession> signInWithEmail({required String email, required String password});

  /// 카카오 · 구글 로그인 (처음이면 자동 가입).
  Future<AuthSession> signInWithProvider(AuthProvider provider);

  /// 온보딩을 끝냈다고 서버에 알린다 (`PATCH /me/onboarding`).
  Future<void> completeOnboarding(AuthSession session);

  Future<void> signOut(AuthSession session);
}

/// 입력 검사 (서버도 같은 규칙으로 다시 검사한다).
class AuthRules {
  AuthRules._();
  static const int minPasswordLength = 8;
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  static String? emailError(String email) =>
      _email.hasMatch(normalizeEmail(email)) ? null : '이메일 주소를 확인해 주세요';

  static String? passwordError(String password) =>
      password.length >= minPasswordLength ? null : '비밀번호는 $minPasswordLength자 이상이에요';
}

/// 서버 없이 앱 안에서만 동작하는 가짜 인증 (개발 · 시연용). 앱을 끄면 가입 정보도 사라진다.
class FakeAuthService implements AuthService {
  FakeAuthService({this.delay = const Duration(milliseconds: 400)});

  /// 네트워크처럼 보이게 하는 지연.
  final Duration delay;

  final Map<String, ({String password, String userId, bool onboardingDone})> _emailUsers = {};
  final Map<AuthProvider, bool> _socialOnboarded = {};
  int _seq = 0;

  AuthSession _session(AuthProvider p, String userId, {String? email, bool onboardingDone = false}) => AuthSession(
        userId: userId,
        provider: p,
        email: email,
        onboardingDone: onboardingDone,
        accessToken: 'fake-access-$userId',
        refreshToken: 'fake-refresh-$userId-${_seq++}',
      );

  @override
  Future<AuthSession?> restore() async => null;

  @override
  Future<AuthSession> signUpWithEmail({required String email, required String password}) async {
    await Future<void>.delayed(delay);
    final e = AuthRules.normalizeEmail(email);
    final emailErr = AuthRules.emailError(e);
    if (emailErr != null) throw AuthException('INVALID_EMAIL', emailErr);
    final pwErr = AuthRules.passwordError(password);
    if (pwErr != null) throw AuthException('WEAK_PASSWORD', pwErr);
    if (_emailUsers.containsKey(e)) throw const AuthException('EMAIL_TAKEN', '이미 가입된 이메일이에요');
    final id = 'u${_seq++}';
    _emailUsers[e] = (password: password, userId: id, onboardingDone: false);
    return _session(AuthProvider.email, id, email: e);
  }

  @override
  Future<AuthSession> signInWithEmail({required String email, required String password}) async {
    await Future<void>.delayed(delay);
    final e = AuthRules.normalizeEmail(email);
    final u = _emailUsers[e];
    if (u == null || u.password != password) {
      throw const AuthException('INVALID_CREDENTIALS', '이메일 또는 비밀번호가 맞지 않아요');
    }
    return _session(AuthProvider.email, u.userId, email: e, onboardingDone: u.onboardingDone);
  }

  @override
  Future<AuthSession> signInWithProvider(AuthProvider provider) async {
    await Future<void>.delayed(delay);
    return _session(provider, 'social-${provider.name}', onboardingDone: _socialOnboarded[provider] ?? false);
  }

  @override
  Future<void> completeOnboarding(AuthSession session) async {
    if (session.provider == AuthProvider.email && session.email != null) {
      final u = _emailUsers[session.email!];
      if (u != null) _emailUsers[session.email!] = (password: u.password, userId: u.userId, onboardingDone: true);
    } else {
      _socialOnboarded[session.provider] = true;
    }
  }

  @override
  Future<void> signOut(AuthSession session) async {}
}

/// 현재 로그인 상태. 화면은 `AuthScope.of(context)`로 쓴다.
class AuthController extends ChangeNotifier {
  AuthController(this.service, {this.onSignedOut});

  final AuthService service;

  /// 로그아웃하면 (앱이 게임 상태를 비운다).
  final VoidCallback? onSignedOut;

  AuthSession? session;
  bool busy = false;

  /// 저장된 로그인 복원이 끝났는지 (끝나기 전엔 로그인 화면 대신 빈 화면).
  bool ready = false;

  Future<T> _run<T>(Future<T> Function() f) async {
    busy = true;
    notifyListeners();
    try {
      return await f();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> restore() async {
    try {
      session = await service.restore();
    } catch (_) {
      session = null;
    }
    ready = true;
    notifyListeners();
  }

  Future<AuthSession> signUpWithEmail(String email, String password) =>
      _run(() async => session = await service.signUpWithEmail(email: email, password: password));

  Future<AuthSession> signInWithEmail(String email, String password) =>
      _run(() async => session = await service.signInWithEmail(email: email, password: password));

  Future<AuthSession> signInWithProvider(AuthProvider p) =>
      _run(() async => session = await service.signInWithProvider(p));

  Future<void> completeOnboarding() async {
    final s = session;
    if (s == null || s.onboardingDone) return;
    await service.completeOnboarding(s);
    session = s.copyWith(onboardingDone: true);
    notifyListeners();
  }

  Future<void> signOut() async {
    final s = session;
    if (s != null) await service.signOut(s);
    session = null;
    notifyListeners();
    onSignedOut?.call();
  }
}

class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({super.key, required AuthController super.notifier, required super.child});

  static AuthController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope가 위젯 트리에 없습니다.');
    return scope!.notifier!;
  }

  /// 셸 · 온보딩 단독 테스트처럼 AuthScope가 없을 수도 있는 곳에서.
  static AuthController? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AuthScope>()?.notifier;
}
