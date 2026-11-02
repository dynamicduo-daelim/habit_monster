import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  /// 제목 · 숫자 (게임 느낌). 본문은 [bodyFont] (2026-10-29 사용자 결정, D-55).
  static const String pixelFont = 'Galmuri11';

  /// 본문 글꼴 — 매끈한 한글 고딕 (OFL, `assets/fonts/Pretendard-*.otf`).
  static const String bodyFont = 'Pretendard';

  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: bodyFont,
      scaffoldBackgroundColor: AppColors.night,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        secondary: AppColors.purple,
        surface: AppColors.nightPanel,
        onPrimary: AppColors.night,
        onSurface: AppColors.text,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: bodyFont,
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
    );
  }
}
