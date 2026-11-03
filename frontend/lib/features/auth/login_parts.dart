import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../data/pixel_icons.dart';

/// 로그인 수단의 화면 이름.
String providerLabel(AuthProvider p) => switch (p) {
      AuthProvider.kakao => '카카오',
      AuthProvider.google => 'Google',
      AuthProvider.email => '이메일',
    };

/// 픽셀 체크 상자 + 글자 (자동 로그인 · 아이디 저장). 글자까지 눌러도 바뀐다.
class PixelCheckbox extends StatelessWidget {
  const PixelCheckbox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.onLight = false,
  });
  final String label;

  /// 크림 카드 위에 놓을 때 (글자를 어둡게).
  final bool onLight;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// 글자 옆 작은 설명 (없으면 생략).
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      label: label,
      excludeSemantics: true,
      onTap: () => onChanged(!value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: value ? AppColors.purple : (onLight ? AppColors.white : AppColors.nightDeep),
                  border: Border.all(color: onLight ? AppColors.ink : (value ? AppColors.purpleSoft : AppColors.nightLine2), width: 3),
                ),
                child: value
                    ? const PixelIcon(
                        layers: [PixelLayer(PixelIcons.checkStroke, AppColors.white)], size: 10, strokeWidth: 3.5)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: onLight ? AppColors.brownText : AppColors.text)),
              if (hint != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(hint!,
                      overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: onLight ? AppColors.brownMuted : AppColors.textMuted)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 마지막으로 쓴 로그인 버튼 위 말풍선 + 버튼 금색 테두리.
class RecentLoginMark extends StatelessWidget {
  const RecentLoginMark({super.key, required this.provider, required this.child});
  final AuthProvider provider;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.yellowButton,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.ink, width: 2),
            ),
            child: Text('최근에 ${providerLabel(provider)}로 로그인했어요',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brownText)),
          ),
        ),
        Center(child: CustomPaint(size: const Size(14, 7), painter: _TailPainter())),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.yellowButton, width: 3),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    final inner = Path()
      ..moveTo(3, 0)
      ..lineTo(size.width - 3, 0)
      ..lineTo(size.width / 2, size.height - 3.5)
      ..close();
    canvas.drawPath(outer, Paint()..color = AppColors.ink);
    canvas.drawPath(inner, Paint()..color = AppColors.yellowButton);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

