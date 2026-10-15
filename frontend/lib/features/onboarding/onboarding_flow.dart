import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/bgm.dart';
import '../../core/auth/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../shell/game_action.dart';
import '../shell/main_shell.dart';
import 'onboarding_controller.dart';
import 'step_categories.dart';
import 'step_goals.dart';
import 'step_habits.dart';

/// 온보딩 1~3단계 화면. 단계 전환 · 0.5초 박자 · 토스트를 맡는다.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late final OnboardingController _c = OnboardingController(onToast: _toast);
  Timer? _ticker;
  Timer? _toastTimer;
  int _tick = 0;
  String? _toastText;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) BgmScope.read(context).play(BgmTrack.intro); // 인트로 곡을 1~3단계까지 이어서
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _tick++);
    });
  }

  void _onChange() => setState(() {});

  void _toast(String text) {
    _toastTimer?.cancel();
    setState(() => _toastText = text);
    _toastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _toastText = null);
    });
  }

  Future<void> _enterHome() async {
    final ok = await runGameAction(context, (repo) async {
      await _c.commit(repo);
      return true;
    }, onError: _toast);
    if (ok != true || !mounted) return;
    AuthScope.maybeRead(context)?.completeOnboarding(); // 다음 로그인부터는 바로 홈
    // 처음 들어가는 홈이니 튜토리얼부터
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell(showTutorial: true)));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _toastTimer?.cancel();
    _c.removeListener(_onChange);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_c.step) {
      OnboardingStep.categories => StepCategories(c: _c, tick: _tick),
      OnboardingStep.habits => StepHabits(c: _c),
      OnboardingStep.goals => StepGoals(c: _c, onEnter: _enterHome),
    };
    return Scaffold(
      backgroundColor: AppColors.introSky,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(child: KeyedSubtree(key: ValueKey(_c.step), child: body)),
            if (_toastText != null)
              Positioned(
                left: 0,
                right: 0,
                top: 14,
                child: IgnorePointer(child: Center(child: PixelToast(text: _toastText!))),
              ),
          ],
        ),
      ),
    );
  }
}
