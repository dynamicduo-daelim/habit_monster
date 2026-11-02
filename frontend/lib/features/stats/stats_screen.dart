import 'package:flutter/material.dart';

import '../../core/constants/economy.dart';
import '../../core/state/game_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/results.dart';
import '../shell/game_action.dart';

/// 통계 (시안 "통계", 4-4): 연속 출석 + 최근 14일 · 최근 7일 성실도 막대 · 카테고리별 레벨.
/// 탭을 열 때마다 [GameRepository.loadStats]로 새로 불러온다 (체크인 뒤 바로 반영되게). 막대 값은 달성률 %.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.active = true});

  /// 지금 보이는 탭인지. 꺼져 있다가 켜지면 다시 불러온다.
  final bool active;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  StatsData? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant StatsScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _failed = false);
    final data = await runGameAction(context, (r) => r.loadStats());
    if (!mounted) return;
    setState(() {
      if (data != null) _data = data;
      _failed = data == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      // 안 보이는 탭(IndexedStack 뒤)에서 로딩 원이 계속 돌지 않게 — 탭을 열 때 불러온다
      if (!widget.active) return const SizedBox.shrink();
      return Center(
        child: _failed
            ? SizedBox(width: 180, child: PixelButton(label: '다시 시도', onPressed: _load))
            : const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.gold)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _AttendanceCard(d),
        const SizedBox(height: 12),
        _SincerityCard(d),
        const SizedBox(height: 12),
        const Text('카테고리별 레벨', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        for (final c in Catalog.categories) ...[
          const SizedBox(height: 8),
          _CategoryRow(category: c, level: d.categories[c.id]),
        ],
      ],
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard(this.d);
  final StatsData d;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.nightPanel, border: Border.all(color: AppColors.nightLine, width: 3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('연속 출석', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                    const SizedBox(height: 4),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${d.currentStreak}', style: const TextStyle(fontSize: 30)),
                      const TextSpan(text: '일', style: TextStyle(fontSize: 13)),
                    ]), style: const TextStyle(color: AppColors.rateHigh, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Text('최장 기록 ${d.longestStreak}일\n최근 14일',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 10, height: 1.8, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < d.last14Days.length; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(child: _DayCell(attended: d.last14Days[i], today: i == d.last14Days.length - 1)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.attended, required this.today});
  final bool attended;
  final bool today;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          // 출석한 날 민트 · 오늘 노랑 (11-02, 통계 그래프 80% 이상 색과 맞춤 — D-60)
          color: attended ? (today ? AppColors.goldLight : AppColors.rateHigh) : AppColors.nightDeep,
          border: Border.all(color: attended ? AppColors.ink : (today ? AppColors.goldLight : AppColors.nightLine2), width: 2),
        ),
      ),
    );
  }
}

class _SincerityCard extends StatelessWidget {
  const _SincerityCard(this.d);
  final StatsData d;

  static const double _chartHeight = 150;

  @override
  Widget build(BuildContext context) {
    final last = d.last7Days.length - 1;
    Color tone(int i) => i == last ? AppColors.goldLight : AppColors.textMuted;
    final avg = d.averageRate;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.nightPanel, border: Border.all(color: AppColors.nightLine, width: 3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('성실도 그래프 · 최근 7일', style: TextStyle(fontSize: 11, color: AppColors.text))),
              Text.rich(
                TextSpan(text: '평균 ', children: [
                  TextSpan(
                      text: avg == null ? '-' : '$avg%',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: avg == null ? AppColors.textMuted : rateColor(avg))),
                ]),
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: _chartHeight,
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.nightLine2, width: 3))),
            child: Stack(
              children: [
                // 목표 80% 점선
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: _Bar.maxBar * goalRate / 100,
                  child: CustomPaint(size: Size(double.infinity, 2), painter: _DashPainter()),
                ),
                const Positioned(
                  right: 0,
                  bottom: _Bar.maxBar * goalRate / 100 + 3,
                  child: Text('목표 $goalRate%', style: TextStyle(fontSize: 9, color: AppColors.goldLight)),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i <= last; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: _Bar(rate: d.last7Days[i].$2)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i <= last; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Text(i == last ? '오늘' : d.last7Days[i].$1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10, color: tone(i), fontWeight: i == last ? FontWeight.w700 : FontWeight.w400)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // 색 뜻 (성취도별 색, 2026-11-02)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (c, label) in const [
                (AppColors.rateLow, '50% 미만'),
                (AppColors.rateMid, '50 ~ 79%'),
                (AppColors.rateHigh, '80% 이상'),
              ]) ...[
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 10, color: AppColors.purpleSoft)),
                const SizedBox(width: 10),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 목표선 (달성률 %).
const int goalRate = 80;

/// 달성률에 따른 막대 색: 50% 미만 코랄 · 50~79% 노랑 · 80% 이상 민트 (2026-11-02, 칙칙하다는 의견으로 보라 → 성취도별 색).
Color rateColor(int rate) => rate >= goalRate ? AppColors.rateHigh : (rate >= 50 ? AppColors.rateMid : AppColors.rateLow);

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.goldLight.withValues(alpha: 0.45)
      ..strokeWidth = 2;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 1), Offset((x + 4).clamp(0, size.width), 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 막대 하나: 위에 값, 높이 = 달성률 % (최소 4). 색 = [rateColor]. 체크인 안 한 날은 "-"만.
class _Bar extends StatelessWidget {
  const _Bar({required this.rate});
  final int? rate;

  static const double maxBar = 120;

  @override
  Widget build(BuildContext context) {
    final r = rate;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(r == null ? '-' : '$r',
            style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: r == null ? AppColors.lockedMuted : rateColor(r))),
        if (r != null) ...[
          const SizedBox(height: 5),
          Container(
            height: (r.clamp(0, 100) / 100 * maxBar).clamp(4, maxBar).toDouble(),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.topCenter,
            decoration: BoxDecoration(
              color: rateColor(r),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(2)),
            ),
            child: Container(height: 3, color: AppColors.barShine),
          ),
        ],
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.level});
  final HabitCategory category;
  final CategoryLevel? level;

  @override
  Widget build(BuildContext context) {
    final lv = level;
    final color = lv != null ? category.color : AppColors.lockedMuted;
    final pct = lv == null ? 0.0 : (lv.isMax ? 1.0 : lv.current / lv.needed);
    final sub = lv == null
        ? '도감을 채우면 열려요'
        : lv.isMax
            ? '최고 레벨 달성!'
            : '다음 레벨까지 ${lv.needed - lv.current} 성실도 · 레벨업마다 +${Economy.categoryLevelUpGold}G';
    return Opacity(
      opacity: lv != null ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.nightDeep, border: Border.all(color: AppColors.nightLine, width: 3)),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.nightRaised, border: Border.all(color: color, width: 3)),
              child: CategoryIcon(category.id, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text(category.name, style: const TextStyle(fontSize: 12, color: AppColors.text))),
                      Text(lv != null ? 'Lv.${lv.level}' : '미등록', style: TextStyle(fontSize: 12, color: color)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 9,
                    decoration: BoxDecoration(
                        color: AppColors.nightRaised, border: Border.all(color: AppColors.nightLine2, width: 2)),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: pct.clamp(0, 1).toDouble(),
                      child: ColoredBox(color: color),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(sub, style: const TextStyle(fontSize: 9.5, color: AppColors.lavender)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
