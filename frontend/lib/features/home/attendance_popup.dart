import 'package:flutter/material.dart';

import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../core/widgets/popup_card.dart';
import '../../data/pixel_icons.dart';
import '../../core/theme/app_theme.dart';

/// 홈의 출석 아이콘 → 출석부 창을 띄운다. [onGoChat]은 "습관 체크하러 가기".
Future<void> showAttendancePopup(BuildContext context, {required VoidCallback onGoChat, DateTime? today}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '출석부 닫기',
    barrierColor: AppColors.black.withValues(alpha: 0),
    pageBuilder: (ctx, _, __) => AttendancePopup(onGoChat: onGoChat, today: today),
  );
}

/// 출석부: 연속 출석 일수 + 이번 달 달력. 앱에 들어온 날에 도장이 찍힌다 (습관 체크와는 별개).
class AttendancePopup extends StatelessWidget {
  const AttendancePopup({super.key, required this.onGoChat, this.today});
  final VoidCallback onGoChat;

  /// 오늘 날짜 (테스트에서 고정할 때).
  final DateTime? today;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final now = today ?? DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final lead = DateTime(now.year, now.month, 1).weekday - 1; // 1일 앞의 빈칸 (월요일 시작)
    final weeks = ((lead + daysInMonth) / 7).ceil();

    Widget cell(int index) {
      final d = index - lead + 1;
      if (d < 1 || d > daysInMonth) return const SizedBox(height: 34);
      final day = DateTime(now.year, now.month, d);
      final isToday = d == now.day;
      final attended = s.attendedOn(day, today: now);
      // 오늘 칸만 습관 결과를 안다 (지난 날은 날짜별 기록이 없어 출석 도장만).
      final result = isToday ? s.todayHabitResult : null;
      final future = d > now.day;
      final (Color bg, Color line, Color num) = switch (result) {
        DayHabitResult.all => (AppColors.gold, AppColors.goldShadow, AppColors.brownText),
        DayHabitResult.partial => (AppColors.goldLight, AppColors.brownShadow, AppColors.brownText),
        null when future => (AppColors.cream, AppColors.slotInset, AppColors.slotInset),
        null => (AppColors.slotEmpty, attended ? AppColors.brownShadow : AppColors.slotInset, AppColors.brownMuted),
      };
      return Container(
        height: 34,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: isToday ? AppColors.purple : line, width: isToday ? 3 : 2),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 3,
              top: 1,
              child: Text('$d', style: TextStyle(fontSize: 8.5, color: num)),
            ),
            if (result != null || attended)
              Positioned(right: 3, bottom: 3, child: _Stamp(result: result)),
          ],
        ),
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: PopupCard(
          title: '출석부',
          ribbonColor: AppColors.redSoft,
          ribbonText: AppColors.white,
          maxWidth: 320,
          children: [
            GestureDetector(
              onTap: () {}, // 카드 안을 눌러도 닫히지 않게
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('연속 ${s.currentStreak}일',
                          style: const TextStyle(fontFamily: AppTheme.pixelFont, 
                              fontSize: 22, height: 1.2, fontWeight: FontWeight.w700, color: AppColors.goldDeep)),
                      const Spacer(),
                      Text('함께한 지 ${s.dayCount}일째',
                          style: const TextStyle(fontSize: 10.5, color: AppColors.brownMuted)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_todayLine(s),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: s.todayHabitResult == DayHabitResult.all ? FontWeight.w700 : FontWeight.w400,
                          color: s.todayHabitResult == DayHabitResult.all
                              ? AppColors.goldDeep
                              : (s.attendedToday ? AppColors.fieldGreen : AppColors.brownMuted))),
                  const SizedBox(height: 12),
                  Text('${now.year}년 ${now.month}월',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final w in _weekdays)
                        Expanded(
                          child: Text(w,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 9.5, color: AppColors.brownMuted)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (var w = 0; w < weeks; w++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          for (var i = 0; i < 7; i++) ...[
                            if (i > 0) const SizedBox(width: 3),
                            Expanded(child: cell(w * 7 + i)),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 7),
                  const Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      _Legend(result: DayHabitResult.all, label: '습관 전부 완료'),
                      _Legend(result: DayHabitResult.partial, label: '일부 완료'),
                      _Legend(result: null, label: '출석만'),
                    ],
                  ),
                  const SizedBox(height: 7),
                  const Text('앱에 들어오면 그날 출석 도장이 찍혀요.\n하루도 빠지지 않으면 연속 출석이 이어져요.',
                      style: TextStyle(fontSize: 10, height: 1.7, color: AppColors.brownMuted)),
                  const SizedBox(height: 10),
                  if (s.checkedInToday)
                    PixelButton(
                      label: '확인',
                      onPressed: () => Navigator.of(context).pop(),
                      color: AppColors.green,
                      shadowColor: AppColors.fieldGreen,
                      textColor: AppColors.brownText,
                      height: 42,
                      depth: 4,
                      fontSize: 12,
                    )
                  else
                    PixelButton(
                      label: '오늘 습관 체크하러 가기',
                      onPressed: () {
                        Navigator.of(context).pop();
                        onGoChat();
                      },
                      height: 42,
                      depth: 4,
                      fontSize: 12,
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

/// 출석부 위쪽 한 줄: 오늘 출석 · 습관 결과.
String _todayLine(GameState s) {
  if (!s.attendedToday) return '오늘은 아직 출석 전이에요.';
  return switch (s.todayHabitResult) {
    DayHabitResult.all => '오늘 습관 전부 완료! 최고예요.',
    DayHabitResult.partial => '오늘 출석 완료! 습관 ${s.todayHabitsLeft}개는 목표까지 조금 남았어요.',
    null => '오늘 출석 완료! 습관 체크도 해 볼까요?',
  };
}

/// 달력 칸 오른쪽 아래 도장: 전부 = 별, 일부 = 체크, 출석만 = 작고 연한 체크.
class _Stamp extends StatelessWidget {
  const _Stamp({required this.result});
  final DayHabitResult? result;

  @override
  Widget build(BuildContext context) {
    return switch (result) {
      DayHabitResult.all => const PixelIcon(layers: [PixelLayer(PixelIcons.star, AppColors.brownText)], size: 13),
      DayHabitResult.partial => const PixelIcon(
          layers: [PixelLayer(PixelIcons.checkStroke, AppColors.brownText)], size: 13, strokeWidth: 3.5),
      null => const PixelIcon(
          layers: [PixelLayer(PixelIcons.checkStroke, AppColors.brownShadow)], size: 10, strokeWidth: 3),
    };
  }
}

/// 달력 아래 범례 한 칸.
class _Legend extends StatelessWidget {
  const _Legend({required this.result, required this.label});
  final DayHabitResult? result;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color line) = switch (result) {
      DayHabitResult.all => (AppColors.gold, AppColors.goldShadow),
      DayHabitResult.partial => (AppColors.goldLight, AppColors.brownShadow),
      null => (AppColors.slotEmpty, AppColors.brownShadow),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, border: Border.all(color: line, width: 2)),
          child: _Stamp(result: result),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 9.5, color: AppColors.brownMuted)),
      ],
    );
  }
}
