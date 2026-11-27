import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/pixel_icons.dart';
import '../home/habit_manage_screen.dart';
import '../home/habit_sheet.dart' show SincerityHelp;
import '../shell/main_shell.dart';

/// 첫 화면 "오늘" 탭 (11-26 개편, D-99): 위에 필드 장면 + 랜덤 루틴몬 1마리의 말풍선 → 체크 수 · 성실도 → 습관 리스트 → 체크받기.
/// 루틴몬은 이 탭에 들어올 때마다 가진 아이 중 하나를 랜덤으로 고른다. 필드(여러 마리 · 상점 아이콘)는 가운데 "필드" 탭.
class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key, this.active = true, this.random});

  /// 이 탭이 보이는 중인지 — 다시 보일 때마다 루틴몬을 새로 고른다.
  final bool active;

  /// 테스트용 난수 (없으면 `Random()`).
  final math.Random? random;

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  late final math.Random _rng = widget.random ?? math.Random();
  String? _uid; // 오늘 탭에 나온 루틴몬

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _uid ??= _pick(GameScope.read(context));
  }

  @override
  void didUpdateWidget(HabitsScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _uid = _pick(GameScope.read(context));
  }

  String? _pick(GameState s) => s.monsters.isEmpty ? null : s.monsters[_rng.nextInt(s.monsters.length)].uid;

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final shell = MainShell.maybeOf(context);
    Future<void> add() async {
      final msg = await HabitManageScreen.open(context);
      if (msg != null) shell?.toast(msg);
    }

    final mon = s.monsterByUid(_uid) ?? s.monsters.firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      children: [
        if (mon != null) ...[
          _MonsterScene(s: s, monster: mon),
          const SizedBox(height: 12),
        ],
        _TodayCard(s: s),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(
              child: Text('오늘의 습관',
                  style: TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
            ),
            _NewHabitButton(onTap: add),
          ],
        ),
        const SizedBox(height: 10),
        if (s.habits.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('아직 습관이 없어요', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          )
        else
          for (final h in s.habits) ...[
            HabitRow(s: s, habit: h, counted: !s.checkedInToday || s.isCounted(h)),
            const SizedBox(height: 8),
          ],
        // 맨 아래: 챗봇 체크받기 (11-26 사용자 — 목록을 다 본 뒤에). 체크를 마치면 버튼을 없앤다 (10-29)
        if (!s.checkedInToday && s.habits.isNotEmpty && shell != null) ...[
          const SizedBox(height: 6),
          _ChatCheckButton(s: s, onTap: () => shell.goTab(MainShell.chatTab)),
        ],
      ],
    );
  }
}

/// 오늘 탭 위 장면: 필드 배경 위에 루틴몬 1마리 + 말풍선 (오늘 상황에 맞는 한마디).
class _MonsterScene extends StatelessWidget {
  const _MonsterScene({required this.s, required this.monster});
  final GameState s;
  final OwnedMonster monster;

  /// 말풍선: 체크 전이면 첫 습관을 묻고, 하는 중이면 다음 습관, 다 했으면 칭찬.
  String _line() {
    if (s.habits.isEmpty) return '같이 할 습관을 하나 만들어 볼까?';
    if (s.todayRecords.isEmpty) return '오늘 ${s.activeHabits.first.name} 했어? 나한테 알려 줘!';
    // 실제로 해낸 습관만 센다 (기록만 있고 0이면 못 한 것)
    final missed = [for (final h in s.activeHabits) if ((s.todayRecords[h.id] ?? 0) <= 0) h];
    if (missed.isEmpty) return '오늘 다 했어! 정말 최고야';
    if (s.checkedInToday) return '수고했어! ${missed.first.name}은 내일 같이 해 보자';
    return '잘하고 있어! 다음은 ${missed.first.name} 어때?';
  }

  @override
  Widget build(BuildContext context) {
    final sp = Catalog.speciesById(monster.speciesId);
    return Semantics(
      label: '${sp.name}: ${_line()}',
      excludeSemantics: true,
      child: Container(
        height: 210,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.ink, width: 3),
          boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(0, 4))],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Image(
              image: AssetImage(AppAssets.homeField),
              fit: BoxFit.cover,
              alignment: Alignment(0, -0.2), // 나무 · 풀밭이 같이 보이게
              filterQuality: FilterQuality.none,
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.ink, width: 3),
                ),
                child: Column(
                  children: [
                    Text(_line(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                    const SizedBox(height: 1),
                    Text('— ${sp.name}', style: const TextStyle(fontSize: 10.5, color: AppColors.brownMuted)),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Center(child: PixelImage(sp.assetAt(monster.level), height: 104)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 오른쪽 위 "+ 새 습관" (금색 작은 버튼).
class _NewHabitButton extends StatelessWidget {
  const _NewHabitButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '새 습관',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.goldLight, width: 2),
            boxShadow: const [BoxShadow(color: AppColors.goldShadow, offset: Offset(0, 3))],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PixelIcon(layers: [PixelLayer(PixelIcons.plus, AppColors.night)], size: 14),
              SizedBox(width: 6),
              Text('새 습관', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.night)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 체크 수 · 오늘의 성실도.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.s});
  final GameState s;

  @override
  Widget build(BuildContext context) {
    final score = s.todayScore;
    final pct = (score / GameState.maxDailyScore).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.nightPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.nightLine, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('오늘의 성실도', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              const SizedBox(width: 2),
              const SincerityHelp(),
              const Spacer(),
              Text('${s.checkedCount} / ${s.activeHabits.length} 체크',
                  style: const TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 13, color: AppColors.gold)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(color: AppColors.nightDeep, border: Border.all(color: AppColors.nightLine2, width: 3)),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(widthFactor: pct, heightFactor: 1, child: const ColoredBox(color: AppColors.gold)),
                ),
              ),
              const SizedBox(width: 10),
              Text('$score / ${GameState.maxDailyScore} · ${score * Economy.goldPerSincerity}G',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// "챗봇에게 오늘 습관 체크받기": 대화 상대 몬스터 그림 + 말풍선 아이콘.
class _ChatCheckButton extends StatelessWidget {
  const _ChatCheckButton({required this.s, required this.onTap});
  final GameState s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = s.monsterByUid(s.chatPartnerUid) ?? s.monsters.firstOrNull;
    final sp = p == null ? null : Catalog.speciesById(p.speciesId);
    return Semantics(
      button: true,
      label: '챗봇에게 오늘 습관 체크받기',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.goldLight, width: 3),
            boxShadow: const [BoxShadow(color: AppColors.goldShadow, offset: Offset(0, 4))],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.butter,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.ink, width: 2),
                ),
                child: sp == null
                    ? const PixelIcon(layers: [PixelLayer(PixelIcons.checkStroke, AppColors.ink)], size: 22, strokeWidth: 3)
                    : PixelImage(sp.assetAt(p!.level), height: 40),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('오늘 습관 체크받기',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.night)),
                    const SizedBox(height: 2),
                    Text('${sp?.name ?? '루틴몬'}에게 오늘 한 걸 알려 줘요',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.brownText)),
                  ],
                ),
              ),
              PixelIcon(layers: [PixelLayer(PixelIcons.nav[1], AppColors.night)], size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// 습관 한 줄: 아이콘 · 이름 · 하루 목표, 오른쪽에 오늘 상태 아이콘(빈 칸 = 미체크, 초록 체크 = 했음, 회색 체크 = 반영 안 됨).
class HabitRow extends StatelessWidget {
  const HabitRow({super.key, required this.s, required this.habit, required this.counted});
  final GameState s;
  final Habit habit;

  /// 오늘 성실도에 반영되는지 (상위 [Economy.dailyHabitCap]개 안).
  final bool counted;

  @override
  Widget build(BuildContext context) {
    final m = s.measureOf(habit);
    final v = s.todayRecords[habit.id];
    // 값은 최신 기록, +점수는 보상에 쓰인 첫 확정 점수 (다시 체크해도 보상은 그대로)
    final score = s.rewardedScoreOf(habit) ?? 0;
    final goal = m.isOX ? '매일 했다 / 못 했다' : '하루 ${formatNum(habit.target)}${m.unit}';
    // 방금 등록한 습관: 금색 테두리 + NEW (기획 2026-11-26)
    final isNew = s.lastAddedHabitId == habit.id;

    final _CheckState st;
    final String? note; // 아이콘 옆 작은 글자 (값 · 점수)
    if (v == null) {
      st = _CheckState.todo;
      note = isNew ? (s.checkedInToday ? '내일부터' : '오늘부터') : null;
    } else if (!counted) {
      st = _CheckState.notCounted;
      note = '반영 안 됨';
    } else if (m.isOX ? v <= 0 : score <= 0) {
      st = _CheckState.missed;
      note = m.isOX ? null : '${formatNum(v)}${m.unit}';
    } else {
      st = _CheckState.done;
      note = m.isOX ? '+$score' : '${formatNum(v)}${m.unit} · +$score';
    }
    final label = switch (st) {
      _CheckState.todo => '미체크',
      _CheckState.done => '체크 완료',
      _CheckState.missed => '못 함',
      _CheckState.notCounted => '반영 안 됨',
    };
    return Semantics(
      label: '${habit.name}, $goal, $label${note != null && st == _CheckState.done ? ' $note' : ''}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: isNew ? AppColors.nightRaised : AppColors.nightPanel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isNew ? AppColors.gold : AppColors.nightLine, width: 3),
        ),
        child: Row(
          children: [
            CategoryIcon(habit.categoryId, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(habit.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                      ),
                      if (isNew) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          color: AppColors.gold,
                          child: const Text('NEW',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(goal, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
            if (note != null) ...[
              Text(note,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: st == _CheckState.done ? AppColors.gold : AppColors.purpleSoft)),
              const SizedBox(width: 8),
            ],
            _CheckBox(state: st),
          ],
        ),
      ),
    );
  }
}

enum _CheckState { todo, done, missed, notCounted }

/// 오늘 상태 아이콘 (32px): 빈 칸 · 초록 체크 · 주황 X · 회색 체크.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.state});
  final _CheckState state;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color line, String? path, Color ink) = switch (state) {
      _CheckState.todo => (AppColors.nightDeep, AppColors.nightLine2, null, AppColors.ink),
      _CheckState.done => (AppColors.green, AppColors.ink, PixelIcons.checkStroke, AppColors.ink),
      _CheckState.missed => (AppColors.orange, AppColors.ink, 'M4 4l8 8 M12 4l-8 8', AppColors.ink),
      _CheckState.notCounted => (AppColors.nightLine2, AppColors.ink, PixelIcons.checkStroke, AppColors.textMuted),
    };
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: line, width: 3),
      ),
      child: path == null ? null : PixelIcon(layers: [PixelLayer(path, ink)], size: 16, strokeWidth: 3.5),
    );
  }
}
