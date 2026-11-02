import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../data/pixel_icons.dart';
import '../../core/theme/app_theme.dart';

/// 온보딩 1~3단계 공통 틀: 점박이 밤하늘 + 스크롤 본문 + 아래 고정 바.
class OnboardingFrame extends StatelessWidget {
  const OnboardingFrame({super.key, required this.children, required this.bottom});
  final List<Widget> children;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.introSky,
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: const DotGridPainter(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      children[i],
                    ],
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: const BoxDecoration(
              color: AppColors.nightDeep,
              border: Border(top: BorderSide(color: AppColors.nightLine, width: 3)),
            ),
            child: SafeArea(top: false, child: bottom),
          ),
        ],
      ),
    );
  }
}

/// radial-gradient(#ffffff1f 1px, transparent 1px) / 14px 격자.
class DotGridPainter extends CustomPainter {
  const DotGridPainter({this.color = AppColors.skyDot});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (double y = 6; y < size.height; y += 14) {
      for (double x = 6; x < size.width; x += 14) {
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DotGridPainter old) => old.color != color;
}

/// STEP n / 3 진행 막대.
class StepHeader extends StatelessWidget {
  const StepHeader({super.key, required this.step, required this.title});
  final int step;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 3; i++) ...[
          Container(
            width: 22,
            height: 8,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), 
              color: i <= step ? AppColors.gold : AppColors.nightLine2,
              border: Border.all(color: AppColors.ink, width: 2),
            ),
          ),
          const SizedBox(width: 6),
        ],
        const SizedBox(width: 4),
        Text('STEP $step / 3 · $title', style: const TextStyle(fontSize: 10, color: AppColors.purpleSoft)),
      ],
    );
  }
}

/// 박사 얼굴 + 말풍선.
class ProfessorTip extends StatelessWidget {
  const ProfessorTip({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    // 시트를 프레임 104×190 크기로 그려서 첫 프레임의 얼굴 부분만 보여준다.
    const frameH = 190.0;
    const scale = frameH / AppAssets.professorFrameH;
    const frameW = AppAssets.professorFrameW * scale;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 60,
          height: 64,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), 
            color: AppColors.purpleDeep,
            border: Border.all(color: AppColors.ink, width: 3),
          ),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Transform.translate(
                offset: const Offset(-24, -2),
                child: Image.asset(
                  AppAssets.professorSheet,
                  width: frameW * AppAssets.professorCols,
                  height: frameH * AppAssets.professorRows,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                  isAntiAlias: false,
                  semanticLabel: '대림대 박사',
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), 
                  color: AppColors.cream,
                  border: Border.all(color: AppColors.ink, width: 3),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('대림대 박사',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.red)),
                    Text(text, style: const TextStyle(fontSize: 11.5, height: 1.75, color: AppColors.brownText)),
                  ],
                ),
              ),
              // 말풍선 꼬리 (왼쪽 테두리를 덮는다)
              Positioned(
                left: -6,
                bottom: 13,
                child: Container(
                  width: 9,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: AppColors.cream,
                    border: Border(
                      left: BorderSide(color: AppColors.ink, width: 3),
                      top: BorderSide(color: AppColors.ink, width: 3),
                      bottom: BorderSide(color: AppColors.ink, width: 3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 위에 리본 제목이 걸린 크림 카드 (예: "새 습관 퀘스트").
class RibbonPanel extends StatelessWidget {
  const RibbonPanel({
    super.key,
    required this.title,
    required this.children,
    this.ribbonColor = AppColors.red,
    this.gap = 14,
  });
  final String title;
  final List<Widget> children;
  final Color ribbonColor;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 22, 12, 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), 
              color: AppColors.cream,
              border: Border.all(color: AppColors.ink, width: 4),
              boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(5, 5))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) SizedBox(height: gap),
                  children[i],
                ],
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: -14,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), 
                  color: ribbonColor,
                  border: Border.all(color: AppColors.ink, width: 3),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppTheme.pixelFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                    shadows: ribbonColor == AppColors.red
                        ? const [Shadow(color: AppColors.redShadow, offset: Offset(1, 1))]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 폼 항목 제목: 검은 번호 배지 + 제목 (+ 회색 보조 설명).
class NumberedLabel extends StatelessWidget {
  const NumberedLabel({super.key, required this.badge, required this.title, this.hint, this.fontSize = 11});
  final String badge;
  final String title;
  final String? hint;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          color: AppColors.brownText,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: Text(badge,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: AppColors.butter)),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: title),
              if (hint != null)
                TextSpan(
                  text: title.isEmpty ? hint : ' $hint',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w400, color: AppColors.brownMuted),
                ),
            ]),
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: AppColors.brownText),
          ),
        ),
      ],
    );
  }
}

/// 빨간 ✕ 지우기 버튼.
class DeleteButton extends StatelessWidget {
  const DeleteButton({super.key, required this.onTap, required this.label, this.size = 38, this.iconSize = 12});
  final VoidCallback onTap;
  final String label;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), 
            color: AppColors.redSoft,
            border: Border.all(color: AppColors.ink, width: 3),
          ),
          child: PixelIcon(
            layers: const [PixelLayer(PixelIcons.crossStroke, AppColors.white)],
            size: iconSize,
            strokeWidth: 3.5,
          ),
        ),
      ),
    );
  }
}

/// 크림색 입력칸 공통 꾸밈 (테두리는 바깥 Container가 그린다).
InputDecoration pixelInputDecoration(String hint) => InputDecoration(
      isDense: true,
      border: InputBorder.none,
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.brownMuted, fontWeight: FontWeight.w400),
      contentPadding: EdgeInsets.zero,
    );
