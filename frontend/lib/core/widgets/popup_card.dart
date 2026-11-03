import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// 화면 가운데 뜨는 팝업 카드 (어두운 배경 + 위에 걸린 리본).
class PopupCard extends StatelessWidget {
  const PopupCard({
    super.key,
    required this.title,
    required this.ribbonColor,
    required this.ribbonText,
    required this.maxWidth,
    required this.children,
  });
  final String title;
  final Color ribbonColor;
  final Color ribbonText;
  final double maxWidth;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.scrimLight,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    border: Border.all(color: AppColors.ink, width: 4),
                    boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(6, 6))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        children[i],
                      ],
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: -16,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                      decoration: BoxDecoration(
                        color: ribbonColor,
                        border: Border.all(color: AppColors.ink, width: 3),
                      ),
                      child:
                          Text(title,
                              style: TextStyle(
                                  fontFamily: AppTheme.pixelFont,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: ribbonText)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
