import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/bgm.dart';
import '../../core/auth/auth_service.dart';
import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../onboarding/onboarding_parts.dart' show DotGridPainter;
import 'email_auth_screen.dart';

/// 첫 화면: 로고 + 카카오 · 구글 · 이메일로 시작하기.
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
                                border: Border.all(color: AppColors.ink, width: 4),
                                boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(5, 5))],
                              ),
                              child: const PixelImage(AppAssets.logo, fit: BoxFit.cover),
                            ),
                            const SizedBox(height: 22),
                            const Text('모아루틴',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                  letterSpacing: 1,
                                  shadows: [Shadow(color: AppColors.nightLine2, offset: Offset(3, 3))],
                                )),
                            const SizedBox(height: 8),
                            const Text('습관을 지키면 루틴몬이 자라요',
                                style: TextStyle(fontSize: 12.5, color: AppColors.purpleSoft)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                    decoration: const BoxDecoration(
                      color: AppColors.nightDeep,
                      border: Border(top: BorderSide(color: AppColors.nightLine, width: 3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PixelButton(
                          label: '카카오로 시작하기',
                          onPressed: () => _social(AuthProvider.kakao),
                          color: AppColors.kakao,
                          shadowColor: AppColors.yellowShadow,
                          textColor: AppColors.brownText,
                          height: 48,
                        ),
                        const SizedBox(height: 10),
                        PixelButton(
                          label: 'Google로 계속하기',
                          onPressed: () => _social(AuthProvider.google),
                          color: AppColors.white,
                          shadowColor: AppColors.chipShadow,
                          textColor: AppColors.brownText,
                          height: 48,
                        ),
                        const SizedBox(height: 10),
                        PixelButton(
                          label: '이메일로 시작하기',
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const EmailAuthScreen())),
                          color: AppColors.parchment,
                          shadowColor: AppColors.parchmentShadow,
                          textColor: AppColors.brownText,
                          height: 48,
                        ),
                        const SizedBox(height: 12),
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
