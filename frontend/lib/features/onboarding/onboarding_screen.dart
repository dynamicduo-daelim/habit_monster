import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/audio/bgm.dart';
import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../core/widgets/sprite_sheet.dart';
import '../../data/catalog.dart';
import '../home/home_parts.dart' show CheckerPainter;
import 'onboarding_parts.dart' show DotGridPainter;
import 'onboarding_flow.dart';

/// 온보딩 0단계: 대림대 박사 인트로 (대사 타이핑 + 스프라이트 애니메이션).
/// 끝나거나 건너뛰면 1~3단계([OnboardingFlow])로 넘어간다.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _lines = Catalog.professorIntro;
  int _line = 0;
  String _typed = '';
  Timer? _typer;

  bool get _isTyping => _typed.length < _lines[_line].length;

  @override
  void initState() {
    super.initState();
    _type(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) BgmScope.read(context).play(BgmTrack.intro);
    });
  }

  void _type(int index) {
    _typer?.cancel();
    final text = _lines[index];
    var n = 0;
    setState(() {
      _line = index;
      _typed = '';
    });
    _typer = Timer.periodic(const Duration(milliseconds: 38), (t) {
      if (!mounted) return;
      n += 1;
      setState(() => _typed = text.substring(0, n));
      if (n >= text.length) t.cancel();
    });
  }

  void _next() {
    if (_isTyping) {
      _typer?.cancel();
      setState(() => _typed = _lines[_line]);
      return;
    }
    if (_line < _lines.length - 1) {
      _type(_line + 1);
    } else {
      _finish();
    }
  }

  void _finish() {
    _typer?.cancel();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const OnboardingFlow()));
  }

  @override
  void dispose() {
    _typer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nextLabel = _isTyping ? '▶ 넘기기' : (_line < _lines.length - 1 ? '다음 ▶' : '시작하기');
    return Scaffold(
      backgroundColor: AppColors.introSky,
      body: SafeArea(
        child: Column(
          children: [
            // 무대: 화면 가로를 꽉 채운다 (예전엔 Stack이 박사 그림 폭(156px)으로 줄어 바닥 · 실루엣이 깨졌음)
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                final floorH = box.maxHeight * 0.24;
                // 화면이 낮으면 박사를 줄인다 (머리가 잘리지 않게, 최대 285px)
                final profH = math.min(285.0, box.maxHeight - 40);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    const CustomPaint(painter: DotGridPainter()),
                    // 보라 체크 바닥 (높이 24%, 위 테두리)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: floorH,
                      child: Container(
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: AppColors.nightLine2, width: 3)),
                        ),
                        child: const CustomPaint(painter: CheckerPainter(AppColors.introFloorDark, AppColors.introFloor, cell: 12)),
                      ),
                    ),
                    // 아직 못 만난 몬스터 실루엣
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 18,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final a in const [AppAssets.monkey, AppAssets.mouse, AppAssets.turtle, AppAssets.squirrel])
                            Opacity(
                              opacity: 0.55,
                              child: ColorFiltered(
                                colorFilter: const ColorFilter.mode(AppColors.black, BlendMode.srcIn),
                                child: PixelImage(a, height: 46),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 22,
                      child: Center(
                        child: SpriteSheetPlayer(
                          asset: AppAssets.professorSheet,
                          columns: AppAssets.professorCols,
                          rows: AppAssets.professorRows,
                          frameWidth: AppAssets.professorFrameW,
                          frameHeight: AppAssets.professorFrameH,
                          displayHeight: profH,
                          playing: _isTyping,
                        ),
                      ),
                    ),
                    // 발밑 그림자
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Center(
                        child: Container(width: 96, height: 10, color: AppColors.ink.withValues(alpha: 0.25)),
                      ),
                    ),
                  ],
                );
              }),
            ),
            Container(
              color: AppColors.nightDeep,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      PixelPanel(
                        borderWidth: 4,
                        shadowOffset: 5,
                        padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
                        child: SizedBox(
                          height: 84,
                          width: double.infinity,
                          child: Text(
                            _typed,
                            style: const TextStyle(fontSize: 13.5, height: 1.95, color: AppColors.brownText),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        top: -14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            border: Border.all(color: AppColors.ink, width: 3),
                          ),
                          child: const Text('대림대 박사',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      SizedBox(
                        width: 104,
                        child: PixelButton(
                          label: '건너뛰기',
                          onPressed: _finish,
                          color: AppColors.parchment,
                          shadowColor: const Color(0xFF8A7A6A),
                          textColor: AppColors.brownText,
                          fontSize: 11.5,
                          height: 48,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(child: PixelButton(label: nextLabel, onPressed: _next, height: 48, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
