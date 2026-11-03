import 'package:flutter/material.dart';

import '../../data/pixel_icons.dart';
import '../constants/app_assets.dart';
import '../theme/app_colors.dart';
import 'pixel_icon.dart';
import '../theme/app_theme.dart';

/// 픽셀 그림이 흐려지지 않게 그리는 이미지.
class PixelImage extends StatelessWidget {
  const PixelImage(this.asset, {super.key, this.width, this.height, this.fit = BoxFit.contain, this.alignment = Alignment.center});
  final String asset;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.none,
      isAntiAlias: false,
    );
  }
}

/// 두꺼운 테두리 + 아래 그림자가 있는 게임 카드.
class PixelPanel extends StatelessWidget {
  const PixelPanel({
    super.key,
    required this.child,
    this.color = AppColors.cream,
    this.borderColor = AppColors.ink,
    this.shadowColor = AppColors.ink,
    this.borderWidth = 3,
    this.shadowOffset = 4,
    this.padding = const EdgeInsets.all(12),
  });
  final Widget child;
  final Color color;
  final Color borderColor;
  final Color shadowColor;
  final double borderWidth;
  final double shadowOffset;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: shadowOffset > 0 ? [BoxShadow(color: shadowColor, offset: Offset(0, shadowOffset))] : null,
      ),
      child: child,
    );
  }
}

/// 눌리면 그림자만큼 내려가는 블록 버튼.
class PixelButton extends StatefulWidget {
  const PixelButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.gold,
    this.shadowColor = AppColors.goldShadow,
    this.textColor = AppColors.night,
    this.disabledColor = AppColors.disabled,
    this.disabledShadowColor = AppColors.disabledShadow,
    this.disabledTextColor = AppColors.disabledText,
    this.height = 50,
    this.depth = 5,
    this.fontSize = 14,
    this.expand = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
    this.semanticLabel,
    this.borderColor = AppColors.ink,
    this.child,
    this.radius = 10,
  });
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color shadowColor;
  final Color textColor;
  final Color disabledColor;

  /// 모서리 둥글기 (2026-10-29부터 기본 10, D-54). 0이면 네모 픽셀 (교감 창).
  final double radius;
  final Color disabledShadowColor;
  final Color disabledTextColor;
  final double height;

  /// 아래 그림자 두께 = 눌렸을 때 내려가는 거리.
  final double depth;
  final double fontSize;
  final bool expand;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;
  final Color borderColor;

  /// 글자 대신 넣을 내용 (아이콘 등). 있으면 [label]은 읽어주기용으로만 쓴다.
  final Widget? child;

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final bg = enabled ? widget.color : widget.disabledColor;
    final shadow = enabled ? widget.shadowColor : widget.disabledShadowColor;
    final fg = enabled ? widget.textColor : widget.disabledTextColor;
    final depth = widget.depth;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      // 자식 의미 정보를 지웠으니 탭 동작을 직접 단다 (웹에서 클릭이 의미 노드로 들어올 때 필요).
      onTap: widget.onPressed,
      // 콜백 구성을 활성/비활성과 상관없이 고정한다. 비활성→활성으로 바뀐 직후의
      // 첫 클릭이 웹에서 사라지는 문제가 있어서, 안에서 활성 여부를 확인한다.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (widget.onPressed != null) setState(() => _down = true);
        },
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () => widget.onPressed?.call(),
        child: SizedBox(
          height: widget.height + depth,
          width: widget.expand ? double.infinity : null,
          child: Stack(
            children: [
              Positioned(
                left: 0, right: 0, bottom: 0, height: widget.height,
                child: Container(
                  decoration: BoxDecoration(color: shadow, borderRadius: BorderRadius.circular(widget.radius)),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 60),
                left: 0, right: 0,
                top: _down ? depth : 0,
                height: widget.height,
                child: Container(
                  alignment: Alignment.center,
                  padding: widget.padding,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(widget.radius),
                    border: Border.all(color: widget.borderColor, width: widget.radius > 0 ? 2 : 3),
                  ),
                  child: widget.child ??
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: widget.fontSize, fontWeight: FontWeight.w700, color: fg),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 금화 아이콘 + 숫자 (상단 바, 목표 보상 등).
class CoinChip extends StatelessWidget {
  const CoinChip({super.key, required this.text, this.big = false, this.onAdd, this.addLabel});
  final String text;
  final bool big;

  /// 있으면 칩 안 오른쪽 끝에 + 버튼이 붙고, 칩 전체를 누를 수 있다 (골드 얻는 법).
  final VoidCallback? onAdd;

  /// + 버튼을 읽어줄 이름.
  final String? addLabel;

  @override
  Widget build(BuildContext context) {
    final size = big ? 18.0 : 12.0;
    final hPad = big ? 10.0 : 6.0;
    final vPad = big ? 4.0 : 2.0;
    final chip = Container(
      padding: EdgeInsets.fromLTRB(hPad, vPad, onAdd == null ? hPad : vPad, vPad),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.ink, width: 3),
        boxShadow: const [BoxShadow(color: Color(0xFFB8AB90), offset: Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(size: Size(size, size), painter: _CoinPainter()),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  fontFamily: AppTheme.pixelFont,
                  fontSize: big ? 14 : 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.goldDeep)),
          if (onAdd != null) ...[
            const SizedBox(width: 7),
            Container(
              width: size + 2,
              height: size + 2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.ink, width: 2),
              ),
              child: PixelIcon(layers: const [PixelLayer(PixelIcons.plus, AppColors.brownText)], size: size - 8),
            ),
          ],
        ],
      ),
    );
    if (onAdd == null) return chip;
    return Semantics(
      button: true,
      label: addLabel,
      excludeSemantics: true,
      onTap: onAdd,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onAdd, child: chip),
    );
  }
}

/// 성실볼 아이콘 + 개수.
class BallChip extends StatelessWidget {
  const BallChip({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 9, 4),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.ink, width: 3),
        boxShadow: const [BoxShadow(color: Color(0xFFB8AB90), offset: Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PixelImage(AppAssets.seongsilBall, width: 16, height: 16),
          const SizedBox(width: 5),
          Text('×$count',
              style: const TextStyle(
                  fontFamily: AppTheme.pixelFont, fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brownText)),
        ],
      ),
    );
  }
}

/// 16×16 격자 금화 (시안의 SVG를 그대로 옮김).
class _CoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 16;
    Rect r(double x, double y, double w, double h) => Rect.fromLTWH(x * u, y * u, w * u, h * u);
    final gold = Paint()..color = AppColors.gold;
    final dark = Paint()..color = const Color(0xFFB27A14);
    final light = Paint()..color = const Color(0xFFFFE7A8);
    for (final rect in [r(5, 1, 6, 1), r(3, 2, 10, 2), r(2, 4, 12, 8), r(3, 12, 10, 2), r(5, 14, 6, 1)]) {
      canvas.drawRect(rect, gold);
    }
    canvas.drawRect(r(7, 4, 2, 8), dark);
    canvas.drawRect(r(5, 3, 2, 1), light);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 화면 위쪽 가운데에 잠깐 뜨는 알림 (시안의 토스트).
class PixelToast extends StatelessWidget {
  const PixelToast({super.key, required this.text, this.coin = false});
  final String text;

  /// 앞에 금화 아이콘 (골드 증감 알림).
  final bool coin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.brownText,
        border: Border.fromBorderSide(BorderSide(color: AppColors.ink, width: 3)),
        boxShadow: [BoxShadow(color: Color(0x880D0B16), offset: Offset(4, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (coin) ...[
            CustomPaint(size: const Size(18, 18), painter: _CoinPainter()),
            const SizedBox(width: 6),
          ],
          Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.butter)),
        ],
      ),
    );
  }
}

/// CSS `text-shadow` 4방향 외곽선.
List<Shadow> outlineShadows(Color color, [double w = 2]) => [
      Shadow(color: color, offset: Offset(w, 0)),
      Shadow(color: color, offset: Offset(-w, 0)),
      Shadow(color: color, offset: Offset(0, w)),
      Shadow(color: color, offset: Offset(0, -w)),
    ];

/// 테두리 3px + 아래 그림자 카드. [sunk]면 그림자 없이 [sinkBy]만큼 내려앉는다 (선택됨).
class PressCard extends StatelessWidget {
  const PressCard({
    super.key,
    required this.child,
    required this.onTap,
    this.color = AppColors.cream,
    this.shadowColor = AppColors.ink,
    this.borderColor = AppColors.ink,
    this.depth = 5,
    this.sunk = false,
    this.sinkBy = 4,
    this.padding = EdgeInsets.zero,
    this.minHeight = 0,
    this.alignment,
    this.semanticLabel,
    this.radius = 10,
  });
  final Widget child;
  final VoidCallback? onTap;

  /// 모서리 둥글기 (기본 10, 0이면 네모 픽셀).
  final double radius;
  final Color color;
  final Color shadowColor;
  final Color borderColor;
  final double depth;
  final bool sunk;
  final double sinkBy;
  final EdgeInsetsGeometry padding;
  final double minHeight;
  final AlignmentGeometry? alignment;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: sunk,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Transform.translate(
          offset: Offset(0, sunk ? sinkBy : 0),
          child: Container(
            constraints: BoxConstraints(minHeight: minHeight),
            alignment: alignment,
            padding: padding,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor, width: radius > 0 ? 2 : 3),
              boxShadow: sunk || depth == 0 ? null : [BoxShadow(color: shadowColor, offset: Offset(0, depth))],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 둥근 모서리 블록 버튼 (2026-10-29 시안 — 모서리 10, 2px 테두리, 아래로 떨어지는 그림자). 누르면 그림자만큼 내려간다.
/// [child]를 주면 글자 대신 그린다 (예: 동전 + 가격).
class RoundBlockButton extends StatefulWidget {
  const RoundBlockButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.color,
    this.shadowColor = AppColors.ink,
    this.textColor = AppColors.brownText,
    this.height = 54,
    this.leading,
    this.borderColor = AppColors.ink,
    this.fontSize = 15,
    this.child,
  });
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color shadowColor;
  final Color textColor;
  final double height;
  final Widget? leading;
  final Color borderColor;
  final double fontSize;
  final Widget? child;

  @override
  State<RoundBlockButton> createState() => _RoundBlockButtonState();
}

class _RoundBlockButtonState extends State<RoundBlockButton> {
  bool _down = false;
  static const double _depth = 4;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: SizedBox(
          height: widget.height + _depth,
          child: Stack(
            children: [
              Positioned.fill(
                top: _depth,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: widget.shadowColor, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 60),
                left: 0,
                right: 0,
                top: _down ? _depth : 0,
                height: widget.height,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: enabled ? widget.color : AppColors.disabled,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: widget.borderColor, width: 2),
                  ),
                  child: widget.child ?? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 8)],
                      Text(widget.label,
                          style: TextStyle(
                              fontSize: widget.fontSize,
                              fontWeight: FontWeight.w700,
                              color: enabled ? widget.textColor : AppColors.disabledText)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
