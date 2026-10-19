import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../onboarding/onboarding_screen.dart';
import '../shell/game_loader.dart';
import '../shell/main_shell.dart';
import 'login_screen.dart';

/// 첫 화면 결정: 로그인 전 → 로그인, 온보딩 전 → 온보딩(인트로부터), 그 밖 → 홈.
/// 서버 모드면 홈 전에 내 데이터를 불러온다 ([GameLoader] — 앱 시작 순서: 로그인 복원 → 불러오기 → 홈 → 출석).
/// 로그아웃하면 이 화면으로 돌아온다 ([MainShellState] 설정 창).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    if (!auth.ready) return const Scaffold(backgroundColor: AppColors.introSky);
    final session = auth.session;
    if (session == null) return const LoginScreen();
    return session.onboardingDone ? const GameLoader(child: MainShell()) : const OnboardingScreen();
  }
}
