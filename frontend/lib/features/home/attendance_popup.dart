import 'package:flutter/material.dart';

import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../core/widgets/popup_card.dart';
import '../../data/pixel_icons.dart';

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
      return Container(
        height: 34,
        decoration: BoxDecoration(
          color: attended ? AppColors.gold : (d > now.day ? AppColors.cream : AppColors.slotEmpty),
          border: Border.all(
            color: isToday ? AppColors.purple : (attended ? AppColors.goldShadow : AppColors.slotInset),
            width: isToday ? 3 : 2,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 3,
              top: 1,
              child: Text('$d',
                  style: TextStyle(
                      fontSize: 8.5,
                      color: attended ? AppColors.brownText : (d > now.day ? AppColors.slotInset : AppColors.brownMuted))),
            ),
            if (attended)
              const Positioned(
                right: 3,
                bottom: 3,
                child: PixelIcon(
                  layers: [PixelLayer(PixelIcons.checkStroke, AppColors.brownText)],
                  size: 13,
                  strokeWidth: 3.5,
                ),
              ),
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
                          style: const TextStyle(
                              fontSize: 22, height: 1.2, fontWeight: FontWeight.w700, color: AppColors.goldDeep)),
                      const Spacer(),
                      Text('함께한 지 ${s.dayCount}일째',
                          style: const TextStyle(fontSize: 10.5, color: AppColors.brownMuted)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(s.attendedToday ? '오늘 출석 완료! 내일도 만나요.' : '오늘은 아직 출석 전이에요.',
                      style: TextStyle(
                          fontSize: 11, color: s.attendedToday ? AppColors.fieldGreen : AppColors.brownMuted)),
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
