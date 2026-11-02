import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/bgm.dart';
import '../../core/auth/auth_service.dart';
import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../onboarding/onboarding_parts.dart' show DotGridPainter;
import 'email_auth_screen.dart';
import 'login_parts.dart';
import '../../core/theme/app_theme.dart';

/// 첫 화면: 로고 + 카카오 · 구글 · 이메일로 시작하기.
/// 지난번에 쓴 수단 위에 말풍선, 아래에 자동 로그인 체크 (기획 2026-10-29-로그인-편의).
/// 처음 로그인하면 온보딩, 이미 온보딩을 마친 계정이면 바로 홈 ([AuthGate]가 정한다).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String? _toastText;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) BgmScope.read(context).play(BgmTrack.intro);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  void _toast(String text) {
    _toastTimer?.cancel();
    setState(() => _toastText = text);
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastText = null);
    });
  }

  Future<void> _social(AuthProvider p) async {
    try {
      await AuthScope.of(context).signInWithProvider(p);
    } on AuthException catch (e) {
      if (e.code != 'CANCELED' && mounted) _toast(e.message);
    }
  }

  /// 지난번에 이 수단으로 로그인했으면 말풍선을 붙인다.
  Widget _recent(AuthController auth, AuthProvider p, Widget button) =>
      auth.prefs.lastProvider == p ? RecentLoginMark(provider: p, child: button) : button;

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.introSky,
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: DotGridPainter())),
          SafeArea(
            child: AbsorbPointer(
              absorbing: auth.busy,
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 128,
                              height: 128,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.ink, width: 3),
                                boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(0, 5))],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: const PixelImage(AppAssets.logo, fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(height: 22),
                            const Text('모아루틴',
                                style: TextStyle(fontFamily: AppTheme.pixelFont, 
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                  letterSpacing: 1,
                                  shadows: [Shadow(color: AppColors.ink, offset: Offset(0, 3))],
                                )),
                            const SizedBox(height: 8),
                            const Text('습관이 쌓이면, 루틴몬이 자라요',
                                style: TextStyle(fontSize: 13, color: AppColors.purpleSoft)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                    decoration: const BoxDecoration(
                      color: AppColors.nightPanel,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      border: Border(top: BorderSide(color: AppColors.nightLine, width: 2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _recent(
                          auth,
                          AuthProvider.kakao,
                          RoundBlockButton(label: '카카오로 시작하기', onPressed: () => _social(AuthProvider.kakao), color: AppColors.kakao),
                        ),
                        const SizedBox(height: 12),
                        _recent(
                          auth,
                          AuthProvider.google,
                          RoundBlockButton(label: 'Google로 계속하기', onPressed: () => _social(AuthProvider.google), color: AppColors.white),
                        ),
                        const SizedBox(height: 12),
                        _recent(
                          auth,
                          AuthProvider.email,
                          RoundBlockButton(label: '이메일로 시작하기', onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const EmailAuthScreen())), color: AppColors.parchment),
                        ),
                        const SizedBox(height: 6),
                        PixelCheckbox(
                          label: '자동 로그인',
                          hint: '앱을 다시 켜도 로그인 유지',
                          value: auth.prefs.autoLogin,
                          onChanged: auth.setAutoLogin,
                        ),
                        const SizedBox(height: 6),
                        const Text('카카오 · Google은 처음이면 자동으로 가입돼요',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (auth.busy)
            const Positioned.fill(
              child: ColoredBox(
                color: AppColors.scrimLight,
                child: Center(child: PixelToast(text: '로그인 중…')),
              ),
            ),
          if (_toastText != null)
            Positioned(
              left: 0,
              right: 0,
              top: MediaQuery.paddingOf(context).top + 14,
              child: IgnorePointer(child: Center(child: PixelToast(text: _toastText!))),
            ),
        ],
      ),
    );
  }
}
