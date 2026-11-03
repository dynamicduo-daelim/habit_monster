import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_monster/app.dart';
import 'package:habit_monster/core/audio/bgm.dart';
import 'package:habit_monster/core/auth/auth_service.dart';
import 'package:habit_monster/core/auth/login_prefs.dart';
import 'package:habit_monster/features/auth/login_screen.dart';
import 'package:habit_monster/features/onboarding/onboarding_screen.dart';
import 'package:habit_monster/features/shell/main_shell.dart';

Matcher _code(String code) => throwsA(isA<AuthException>().having((e) => e.code, 'code', code));

void main() {
  group('FakeAuthService 규칙', () {
    late FakeAuthService svc;
    setUp(() => svc = FakeAuthService(delay: Duration.zero));

    test('같은 이메일은 다시 가입 불가 (대소문자 · 앞뒤 공백 무시)', () async {
      final s = await svc.signUpWithEmail(email: ' Test@Mail.com ', password: 'password1');
      expect(s.email, 'test@mail.com');
      expect(s.onboardingDone, isFalse);
      expect(svc.signUpWithEmail(email: 'test@mail.com', password: 'password2'), _code('EMAIL_TAKEN'));
    });

    test('비밀번호 8자 미만 · 이메일 형식 오류', () {
      expect(svc.signUpWithEmail(email: 'a@b.co', password: 'short'), _code('WEAK_PASSWORD'));
      expect(svc.signUpWithEmail(email: 'not-email', password: 'password1'), _code('INVALID_EMAIL'));
    });

    test('틀린 비밀번호 → INVALID_CREDENTIALS, 온보딩 완료는 다음 로그인에도 남는다', () async {
      final s = await svc.signUpWithEmail(email: 'b@b.co', password: 'password1');
      expect(svc.signInWithEmail(email: 'b@b.co', password: 'wrong-pass'), _code('INVALID_CREDENTIALS'));
      await svc.completeOnboarding(s);
      final again = await svc.signInWithEmail(email: 'b@b.co', password: 'password1');
      expect(again.onboardingDone, isTrue);
    });
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('이메일 가입 → 온보딩 → 홈, 로그아웃 → 로그인 화면, 다시 로그인 → 바로 홈', (tester) async {
    phone(tester);
    await tester.pumpWidget(HabitMonsterApp(authService: FakeAuthService(delay: Duration.zero), bgm: SilentBgm()));
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);

    // 이메일 → 회원가입 탭
    await tester.tap(find.text('이메일로 시작하기'));
    await settle(tester);
    await tester.tap(find.text('회원가입'));
    await tester.pump();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'me@habit.kr');
    await tester.enterText(fields.at(1), 'short');
    await tester.enterText(fields.at(2), 'short');
    await tester.tap(find.text('가입하고 시작하기'));
    await tester.pump();
    expect(find.text('비밀번호는 8자 이상이에요'), findsOneWidget);

    await tester.enterText(fields.at(1), 'password1');
    await tester.enterText(fields.at(2), 'password2');
    await tester.tap(find.text('가입하고 시작하기'));
    await tester.pump();
    expect(find.text('비밀번호가 서로 달라요'), findsOneWidget);

    await tester.enterText(fields.at(2), 'password1');
    await tester.tap(find.text('가입하고 시작하기'));
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget); // 처음 가입 → 온보딩

    // 온보딩 끝 (화면 흐름은 onboarding_test에서 검사) → 홈
    final auth = AuthScope.of(tester.element(find.byType(OnboardingScreen)));
    await auth.completeOnboarding();
    await settle(tester);
    expect(find.byType(MainShell), findsOneWidget);

    // 설정 → 계정 표시 → 로그아웃 → 로그인 화면
    await tester.tap(find.bySemanticsLabel('설정'));
    await settle(tester);
    expect(find.text('이메일 계정으로 로그인됨\nme@habit.kr'), findsOneWidget);
    await tester.tap(find.text('로그아웃'));
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
    expect(find.text('최근에 이메일로 로그인했어요'), findsOneWidget); // 최근 로그인 말풍선

    // 틀린 비밀번호 → 오류, 맞으면 온보딩 없이 바로 홈
    await tester.tap(find.text('이메일로 시작하기'));
    await settle(tester);
    final f2 = find.byType(TextField);
    expect(tester.widget<TextField>(f2.at(0)).controller!.text, 'me@habit.kr'); // 아이디 저장으로 미리 채움
    await tester.enterText(f2.at(0), 'ME@habit.kr');
    await tester.enterText(f2.at(1), 'password9');
    await tester.tap(find.text('로그인').last);
    await settle(tester);
    expect(find.text('이메일 또는 비밀번호가 맞지 않아요'), findsOneWidget);
    await tester.enterText(f2.at(1), 'password1');
    await tester.tap(find.text('로그인').last);
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(MainShell), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('카카오 로그인 (처음) → 온보딩', (tester) async {
    phone(tester);
    await tester.pumpWidget(HabitMonsterApp(authService: FakeAuthService(delay: Duration.zero), bgm: SilentBgm()));
    await tester.pump();
    await tester.tap(find.text('카카오로 시작하기'));
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  group('로그인 편의 (AuthController)', () {
    test('로그인하면 최근 수단 · 이메일을 저장, 아이디 저장을 끄면 이메일을 지운다', () async {
      final store = MemoryLoginPrefsStore();
      final auth = AuthController(FakeAuthService(delay: Duration.zero), prefsStore: store);
      await auth.restore();
      await auth.signUpWithEmail('a@b.co', 'password1');
      expect(store.value.lastProvider, AuthProvider.email);
      expect(store.value.savedEmail, 'a@b.co');
      await auth.setRememberEmail(false);
      expect(store.value.savedEmail, isNull);
      await auth.signOut();
      await auth.signInWithProvider(AuthProvider.kakao);
      expect(store.value.lastProvider, AuthProvider.kakao);
      expect(store.value.savedEmail, isNull);
    });

    test('자동 로그인이 꺼져 있으면 저장된 로그인을 쓰지 않고 지운다', () async {
      final svc = _SavedLoginAuth();
      final on = AuthController(svc, prefsStore: MemoryLoginPrefsStore());
      await on.restore();
      expect(on.session, isNotNull);

      final off = AuthController(svc, prefsStore: MemoryLoginPrefsStore(const LoginPrefs(autoLogin: false)));
      await off.restore();
      expect(off.session, isNull);
      expect(svc.forgotten, isTrue);
      expect(off.ready, isTrue);
    });
  });
}

/// 저장된 로그인이 있는 것처럼 복원해 주는 가짜 인증.
class _SavedLoginAuth extends FakeAuthService {
  _SavedLoginAuth() : super(delay: Duration.zero);
  bool forgotten = false;

  @override
  Future<AuthSession?> restore() async => const AuthSession(
      userId: 'u1', provider: AuthProvider.kakao, accessToken: 'a', refreshToken: 'r', onboardingDone: true);

  @override
  Future<void> forgetSavedLogin() async => forgotten = true;
}
