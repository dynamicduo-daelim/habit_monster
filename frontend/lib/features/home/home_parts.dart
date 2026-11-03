import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../data/pixel_icons.dart';

/// 홈 위에 덮는 창(상점 · 가방 · 몬스터 정보)의 어두운 배경 + 아래 붙은 패널.
/// 배경을 누르면 닫힌다. [heightFactor]가 있으면 높이를 고정, 없으면 내용만큼 (최대 [maxHeightFactor]).
class HomeOverlay extends StatelessWidget {
  const HomeOverlay({
    super.key,
    required this.child,
    required this.onClose,
    this.heightFactor,
    this.maxHeightFactor = 0.95,
  });
  final Widget child;
  final VoidCallback onClose;
  final double? heightFactor;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(onTap: onClose, child: const ColoredBox(color: AppColors.scrim)),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: heightFactor != null ? h * heightFactor! : h * maxHeightFactor),
              child: heightFactor != null ? SizedBox(height: h * heightFactor!, child: child) : child,
            ),
          ),
        ],
      );
    });
  }
}

/// 40×40 ✕ 닫기 버튼 (갈색 테두리).
class BrownCloseButton extends StatelessWidget {
  const BrownCloseButton({
    super.key,
    required this.onTap,
    this.color = AppColors.redSoft,
    this.iconColor = AppColors.white,
    this.shadow = true,
    this.radius = 0,
  });
  final VoidCallback onTap;
  final Color color;
  final Color iconColor;
  final bool shadow;

  /// 둥근 모서리 (상점 · 2026-10-29 시안은 10).
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '닫기',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: radius > 0 ? BorderRadius.circular(radius) : null,
            border: Border.all(color: AppColors.inkBrown, width: radius > 0 ? 2 : 3),
            boxShadow: shadow ? const [BoxShadow(color: AppColors.redShadow, offset: Offset(0, 3))] : null,
          ),
          child: PixelIcon(
            layers: [PixelLayer(PixelIcons.crossStroke, iconColor)],
            size: 14,
            strokeWidth: 3.5,
          ),
        ),
      ),
    );
  }
}

/// repeating-conic-gradient 체크무늬.
class CheckerPainter extends CustomPainter {
  const CheckerPainter(this.a, this.b, {this.cell = 6});
  final Color a;
  final Color b;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = b);
    final p = Paint()..color = a;
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        if ((x + y).isEven) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckerPainter old) => old.a != a || old.b != b || old.cell != cell;
}

/// 점선 테두리 (CSS `border: dashed`).
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({required this.color, this.width = 2, this.dash = 6, this.gap = 4});
  final Color color;
  final double width;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    void hLine(double y) {
      for (double x = 0; x < size.width; x += dash + gap) {
        canvas.drawRect(Rect.fromLTWH(x, y, (dash).clamp(0, size.width - x), width), p);
      }
    }

    void vLine(double x) {
      for (double y = 0; y < size.height; y += dash + gap) {
        canvas.drawRect(Rect.fromLTWH(x, y, width, (dash).clamp(0, size.height - y)), p);
      }
    }

    hLine(0);
    hLine(size.height - width);
    vLine(0);
    vLine(size.width - width);
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter old) => old.color != color || old.width != width;
}

/// 금화 아이콘 (구매 버튼 · 토스트).
class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 14, this.color = AppColors.gold});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => PixelIcon(
        layers: [PixelLayer(PixelIcons.coin, color), const PixelLayer(PixelIcons.coinBand, AppColors.yellowShadow)],
        size: size,
      );
}

/// 몬스터 대사 말풍선 꼬리 (아래 가운데).
class BubbleTail extends StatelessWidget {
  const BubbleTail({super.key, required this.color, this.borderColor = AppColors.inkBrown, this.width = 10});
  final Color color;
  final Color borderColor;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width + 6,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        border: Border(
          left: BorderSide(color: borderColor, width: 3),
          right: BorderSide(color: borderColor, width: 3),
          bottom: BorderSide(color: borderColor, width: 3),
        ),
      ),
    );
  }
}
