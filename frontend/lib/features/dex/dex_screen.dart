import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/pixel_icons.dart';
import '../home/home_parts.dart' show CheckerPainter;
import '../shell/game_action.dart';
import '../shell/main_shell.dart';

/// 몬스터 도감: 위 상세 카드 + 카테고리 탭 6개 + No.001~036 목록.
/// 배경은 고른 카테고리 색의 파스텔 줄무늬.
class DexScreen extends StatefulWidget {
  const DexScreen({super.key, this.active = true});

  /// 도감 탭이 보이는 중인지 (아니면 통통 튀는 타이머를 멈춘다).
  final bool active;

  @override
  State<DexScreen> createState() => _DexScreenState();
}

/// 도감 한 칸. 종이 없으면 아직 공개 안 된 빈 자리.
class _Slot {
  const _Slot(this.no, this.species, this.owned, this.open, this.unlock);
  final String no;
  final MonsterSpecies? species;
  final OwnedMonster? owned;
  final bool open; // 지금 탐색에서 만날 수 있음
  final int unlock;
}

class _DexScreenState extends State<DexScreen> {
  /// 카테고리마다 6칸. 빈 칸의 출현 레벨 (시안의 FILL_UNLOCK).
  static const _slotsPerCategory = 6;
  static const _fillUnlock = [2, 4, 5, 6, 8, 10];

  String _cat = 'ex';
  int _sel = 0;
  bool _picking = false; // 새 카테고리 고르는 창
  bool _bobUp = false;
  Timer? _bob;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant DexScreen old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _syncTimer();
  }

  void _syncTimer() {
    _bob?.cancel();
    if (!widget.active) return;
    _bob = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _bobUp = !_bobUp);
    });
  }

  @override
  void dispose() {
    _bob?.cancel();
    super.dispose();
  }

  Map<String, OwnedMonster> _ownedBySpecies(GameState s) => {for (final m in s.monsters) m.speciesId: m};

  List<_Slot> _slots(GameState s, String catId, Map<String, OwnedMonster> owned) {
    final catIdx = Catalog.categories.indexWhere((c) => c.id == catId);
    final list = Catalog.species.where((x) => x.categoryId == catId).toList();
    final active = s.pickedCategories.contains(catId);
    final lv = s.categoryLevel(catId).level;
    return [
      for (var i = 0; i < _slotsPerCategory; i++)
        if (i < list.length)
          _Slot(_no(catIdx, i), list[i], owned[list[i].id], active && list[i].unlockLevel <= lv, list[i].unlockLevel)
        else
          _Slot(_no(catIdx, i), null, null, false, _fillUnlock[i]),
    ];
  }

  static String _no(int catIdx, int i) => (catIdx * _slotsPerCategory + i + 1).toString().padLeft(3, '0');

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final cat = Catalog.category(_cat);
    final owned = _ownedBySpecies(s);
    final slots = _slots(s, _cat, owned);
    final found = slots.where((x) => x.owned != null).length;
    final totalFound = Catalog.species.where((x) => owned.containsKey(x.id)).length;
    final total = Catalog.categories.length * _slotsPerCategory;
    final active = s.pickedCategories.contains(_cat);

    // 카테고리 색으로 만든 파스텔 배경 · 줄무늬 · 그림자 (시안의 mixHex)
    final bg = Color.lerp(cat.color, AppColors.white, 0.62)!;
    final stripe = Color.lerp(cat.color, AppColors.white, 0.52)!;
    final shade = Color.lerp(cat.color, AppColors.brownText, 0.45)!;

    return Stack(
      children: [
        Positioned.fill(child: _page(s, cat, slots, owned, found, totalFound, total, active, bg, stripe, shade)),
        if (_picking)
          Positioned.fill(
            child: _CategoryPicker(
              onPick: (c) async {
                final ok = await runGameAction(context, (r) => r.openCategory(c.id));
                if (ok != true || !context.mounted) return;
                setState(() {
                  _picking = false;
                  _cat = c.id;
                  _sel = 0;
                });
                MainShell.of(context).toast('${c.name} 길이 열렸어요!');
              },
              onClose: () => setState(() => _picking = false),
            ),
          ),
      ],
    );
  }

  Widget _page(GameState s, HabitCategory cat, List<_Slot> slots, Map<String, OwnedMonster> owned, int found,
      int totalFound, int total, bool active, Color bg, Color stripe, Color shade) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: bg,
      child: CustomPaint(
        painter: _StripePainter(stripe),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
          children: [
            _header(totalFound, total),
            const SizedBox(height: 9),
            _slotCard(s, shade),
            const SizedBox(height: 9),
            _DetailCard(slot: slots[_sel.clamp(0, _slotsPerCategory - 1)], cat: cat, shade: shade, bobUp: _bobUp),
            const SizedBox(height: 9),
            Row(
              children: [
                for (var i = 0; i < Catalog.categories.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(child: _tab(s, Catalog.categories[i], owned, shade)),
                ],
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Text(cat.name,
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                const SizedBox(width: 8),
                Text('${active ? 'Lv.${s.categoryLevel(_cat).level}' : '미등록'} · $found/$_slotsPerCategory',
                    style: const TextStyle(fontSize: 10.5, color: AppColors.brownText)),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 8,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: AppColors.cream,
                      border: Border.all(color: AppColors.inkBrown, width: 2),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: found / _slotsPerCategory,
                      heightFactor: 1,
                      child: const ColoredBox(color: AppColors.gold),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Container(
              decoration: BoxDecoration(
                color: AppColors.cream,
                border: Border.all(color: AppColors.inkBrown, width: 4),
                boxShadow: [BoxShadow(color: shade, offset: const Offset(4, 4))],
              ),
              child: Column(
                children: [
                  for (var i = 0; i < slots.length; i++)
                    _SlotRow(slot: slots[i], index: i, selected: i == _sel, onTap: () => setState(() => _sel = i)),
                ],
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              '카테고리 레벨이 오르면 새로운 몬스터가 탐색에 나타나요 · 이미 가진 몬스터를 또 만나면 골드로 바뀌어요',
              style: TextStyle(fontSize: 9.5, height: 1.8, color: AppColors.dexFootnote),
            ),
          ],
        ),
      ),
    );
  }

  /// 카테고리 슬롯: 도감 5 · 10 · 15마리마다 +1칸.
  Widget _slotCard(GameState s, Color shade) {
    final found = s.discoveredCount;
    const steps = Economy.categorySlotSteps;
    final next = steps.where((n) => found < n).firstOrNull;
    final prev = [0, ...steps].where((n) => n <= found).last;
    final pct = next == null ? 1.0 : (found - prev) / (next - prev);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cream,
        border: Border.all(color: AppColors.inkBrown, width: 3),
        boxShadow: [BoxShadow(color: shade, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('카테고리 슬롯 ${s.pickedCategories.length}/${s.categorySlotCount}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brownText)),
              ),
              Text(next != null ? '도감 $found/$next 발견하면 +1' : '모든 슬롯 해금!',
                  style: const TextStyle(fontSize: 10, color: AppColors.brownMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 12,
                  color: AppColors.inkBrown,
                  padding: const EdgeInsets.all(2),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: pct.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: const ColoredBox(color: AppColors.gold),
                  ),
                ),
              ),
              for (final n in steps) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 30),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: found >= n ? AppColors.yellowButton : AppColors.parchment,
                    border: Border.all(color: AppColors.inkBrown, width: 2),
                  ),
                  child: Text('$n',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: found >= n ? AppColors.brownText : AppColors.slotStepOff,
                      )),
                ),
              ],
            ],
          ),
          if (s.canOpenCategory) ...[
            const SizedBox(height: 8),
            PixelButton(
              label: '새 카테고리 열기! ▶',
              onPressed: () => setState(() => _picking = true),
              color: AppColors.yellowButton,
              shadowColor: AppColors.yellowShadow,
              textColor: AppColors.brownText,
              height: 44,
              depth: 4,
              fontSize: 13,
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(int found, int total) {
    Widget light(Color c) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, border: Border.all(color: AppColors.inkBrown, width: 2)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
      child: Row(
        children: [
          // 도감 렌즈 (inset 그림자 → 오른쪽·아래 어둡게, 왼쪽·위 밝게)
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.dexLens,
              border: Border.all(color: AppColors.inkBrown, width: 3),
            ),
            child: const Stack(
              children: [
                Positioned(right: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: AppColors.dexLensDark)),
                Positioned(left: 0, right: 0, bottom: 0, height: 4, child: ColoredBox(color: AppColors.dexLensDark)),
                Positioned(left: 0, top: 0, width: 3, bottom: 4, child: ColoredBox(color: AppColors.dexLensLight)),
                Positioned(left: 0, top: 0, right: 4, height: 3, child: ColoredBox(color: AppColors.dexLensLight)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          light(AppColors.dexLightRed),
          const SizedBox(width: 8),
          light(AppColors.yellowButton),
          const SizedBox(width: 8),
          light(AppColors.green),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('몬스터 도감',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.brownText,
                  shadows: [Shadow(color: AppColors.cream, offset: Offset(2, 2))],
                )),
          ),
          Container(
            color: AppColors.inkBrown,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('발견 $found/$total', style: const TextStyle(fontSize: 10.5, color: AppColors.butter)),
          ),
        ],
      ),
    );
  }

  Widget _tab(GameState s, HabitCategory c, Map<String, OwnedMonster> owned, Color shade) {
    final cur = c.id == _cat;
    final found = Catalog.species.where((x) => x.categoryId == c.id && owned.containsKey(x.id)).length;
    return PressCard(
      onTap: () => setState(() {
        _cat = c.id;
        _sel = 0;
      }),
      sunk: cur,
      sinkBy: 2,
      depth: 4,
      color: cur ? AppColors.butter : AppColors.offWhite,
      shadowColor: shade,
      borderColor: AppColors.inkBrown,
      minHeight: 52,
      alignment: Alignment.center,
      padding: const EdgeInsets.fromLTRB(0, 5, 0, 4),
      semanticLabel: '${c.name} 도감',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CategoryIcon(c.id, size: 22, outline: 1),
          const SizedBox(height: 3),
          Text('$found/$_slotsPerCategory',
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.brownText)),
        ],
      ),
    );
  }
}

/// 3px 가로줄을 12px마다 (repeating-linear-gradient).
class _StripePainter extends CustomPainter {
  const _StripePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (double y = size.height - 3; y > -3; y -= 12) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 3), p);
    }
  }

  @override
  bool shouldRepaint(covariant _StripePainter old) => old.color != color;
}

/// 몬스터 그림. 가진 몬스터는 그대로, 못 만난 몬스터는 검은 실루엣.
class _MonsterArt extends StatelessWidget {
  const _MonsterArt({required this.species, required this.owned, required this.maxSize, required this.dimOpacity});
  final MonsterSpecies species;
  final bool owned;
  final double maxSize;
  final double dimOpacity;

  @override
  Widget build(BuildContext context) {
    final img = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxSize, maxHeight: maxSize),
      child: PixelImage(species.asset),
    );
    if (owned) return img;
    return Opacity(
      opacity: dimOpacity,
      child: ColorFiltered(colorFilter: const ColorFilter.mode(AppColors.black, BlendMode.srcIn), child: img),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.slot, required this.cat, required this.shade, required this.bobUp});
  final _Slot slot;
  final HabitCategory cat;
  final Color shade;
  final bool bobUp;

  @override
  Widget build(BuildContext context) {
    final sp = slot.species;
    final own = slot.owned;
    final String state;
    final Color stateColor;
    if (own != null) {
      state = '보유 중 · Lv.${own.level} · ${own.stage}';
      stateColor = AppColors.fieldGreen;
    } else if (slot.open) {
      state = '지금 탐색하면 만날 수 있어요!';
      stateColor = AppColors.red;
    } else {
      state = '카테고리 Lv.${slot.unlock}에서 출현';
      stateColor = AppColors.brownMuted;
    }
    final String desc;
    if (own != null) {
      desc = sp!.description;
    } else if (sp != null) {
      desc = '그림자만 어렴풋이 보인다. ${cat.name} 습관을 꾸준히 하면 모습을 드러낼 것 같다.';
    } else {
      desc = '아직 아무것도 알려지지 않은 몬스터. 카테고리 레벨을 올려보자.';
    }
    final stars = own != null ? sp!.stars : 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        border: Border.all(color: AppColors.inkBrown, width: 4),
        boxShadow: [BoxShadow(color: shade, offset: const Offset(4, 4))],
      ),
      // inset 0 0 0 3px 크림색 안쪽 테두리
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: AppColors.cream, width: 3)),
        padding: const EdgeInsets.all(7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(border: Border.all(color: AppColors.inkBrown, width: 3)),
                  child: CustomPaint(
                    painter: const CheckerPainter(AppColors.grassCardDark, AppColors.grassCard, cell: 8),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (sp != null)
                          Transform.translate(
                            offset: Offset(0, bobUp ? -4 : 0),
                            child: _MonsterArt(species: sp, owned: own != null, maxSize: 104, dimOpacity: 0.35),
                          )
                        else
                          const Text('?',
                              style:
                                  TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: AppColors.dexPortraitQ)),
                        if (own != null)
                          const Positioned(right: 4, top: 4, child: PixelImage(AppAssets.seongsilBall, height: 20)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No.${slot.no}', style: const TextStyle(fontSize: 11, color: AppColors.brownMuted)),
                      const SizedBox(height: 6),
                      Text(own != null ? sp!.name : '??????',
                          style:
                              const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.fromLTRB(5, 3, 8, 3),
                        decoration: BoxDecoration(
                          color: cat.color,
                          border: Border.all(color: AppColors.inkBrown, width: 2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CategoryIcon(cat.id, size: 14, outline: 0),
                            const SizedBox(width: 5),
                            Text('${cat.type} 타입',
                                style: const TextStyle(
                                    fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          for (var i = 0; i < 3; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: PixelIcon(
                                layers: [
                                  PixelLayer(PixelIcons.star, i < stars ? AppColors.gold : AppColors.mutedOnBrown),
                                ],
                                size: 13,
                              ),
                            ),
                          const SizedBox(width: 2),
                          Text(own != null ? sp!.rarity : '???',
                              style: const TextStyle(fontSize: 10, color: AppColors.brownMuted)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(state, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: stateColor)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            CustomPaint(
              painter: const _TopDashPainter(),
              child: Padding(
                padding: const EdgeInsets.only(top: 11),
                child: Text(desc, style: const TextStyle(fontSize: 11, height: 1.85, color: AppColors.brownText)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 위쪽 3px 점선 (border-top: dashed).
class _TopDashPainter extends CustomPainter {
  const _TopDashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.mutedOnBrown;
    for (double x = 0; x < size.width; x += 9) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 6, 3), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot, required this.index, required this.selected, required this.onTap});
  final _Slot slot;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  /// 시안의 빨간 ▶ (4×4 격자를 16칸으로 4배).
  static const _arrow = 'M0 0h4v4h4v4h4v4H8v4H4v4H0z';

  @override
  Widget build(BuildContext context) {
    final sp = slot.species;
    final own = slot.owned;
    final sub = own != null ? 'Lv.${own.level}' : (slot.open ? '출현 중' : 'Lv.${slot.unlock} 출현');
    return Semantics(
      button: true,
      selected: selected,
      label: 'No.${slot.no} ${own != null ? sp!.name : '미발견'}',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.butter : (index.isOdd ? AppColors.dexRowAlt : AppColors.cream),
            border: const Border(bottom: BorderSide(color: AppColors.divider, width: 2)),
          ),
          child: Row(
            children: [
              Opacity(
                opacity: selected ? 1 : 0,
                child: const ClipRect(
                  child: PixelIcon(layers: [PixelLayer(_arrow, AppColors.red)], size: 10),
                ),
              ),
              const SizedBox(width: 9),
              SizedBox(
                width: 48,
                child: Text('No.${slot.no}', style: const TextStyle(fontSize: 10.5, color: AppColors.brownMuted)),
              ),
              const SizedBox(width: 9),
              SizedBox(
                width: 34,
                height: 34,
                child: Center(
                  child: sp != null
                      ? _MonsterArt(species: sp, owned: own != null, maxSize: 34, dimOpacity: 0.3)
                      : const Text('?',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.dexSlotQ)),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(own != null ? sp!.name : '??????',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: own != null ? AppColors.brownText : AppColors.dexUnknown,
                    )),
              ),
              const SizedBox(width: 9),
              Text(sub, style: const TextStyle(fontSize: 9.5, color: AppColors.brownMuted)),
              if (own != null) ...[
                const SizedBox(width: 9),
                const PixelImage(AppAssets.seongsilBall, height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 빈 슬롯에 새 길(카테고리)을 고르는 창.
class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.onPick, required this.onClose});
  final ValueChanged<HabitCategory> onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final found = s.discoveredCount;
    final grown = s.categorySlotCount > Economy.baseCategorySlots;
    final rest = Catalog.categories.where((c) => !s.pickedCategories.contains(c.id)).toList();
    return Stack(
      children: [
        Positioned.fill(child: GestureDetector(onTap: onClose, child: const ColoredBox(color: AppColors.scrim))),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
                decoration: const BoxDecoration(
                  color: AppColors.cream,
                  border: Border(top: BorderSide(color: AppColors.ink, width: 4)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      grown
                          ? '도감을 $found마리 채워서 슬롯이 ${s.categorySlotCount}칸이 됐어요. 새로 걸을 길을 골라주세요.'
                          : '아직 비어 있는 카테고리 슬롯이 있어요. 걸을 길을 골라주세요.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11.5, height: 1.8, color: AppColors.brownText),
                    ),
                    const SizedBox(height: 12),
                    for (var r = 0; r < rest.length; r += 3) ...[
                      if (r > 0) const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = r; i < r + 3; i++) ...[
                            if (i > r) const SizedBox(width: 8),
                            Expanded(child: i < rest.length ? _choice(rest[i]) : const SizedBox()),
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onClose,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 40),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: const Text('나중에 고를게요',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.brownMuted,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.brownMuted,
                              )),
                        ),
                      ),
                    ),
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
                    decoration: BoxDecoration(color: AppColors.red, border: Border.all(color: AppColors.ink, width: 3)),
                    child: Text(grown ? '새로운 길이 열렸다!' : '빈 슬롯이 있어요',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _choice(HabitCategory c) {
    return PressCard(
      onTap: () => onPick(c),
      color: AppColors.parchment,
      depth: 4,
      minHeight: 90,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      semanticLabel: '${c.name} 길 열기',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.color, border: Border.all(color: AppColors.ink, width: 3)),
            child: CategoryIcon(c.id, size: 24),
          ),
          const SizedBox(height: 6),
          Text(c.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brownText)),
          const SizedBox(height: 6),
          Text('${c.type} 타입', style: const TextStyle(fontSize: 9, color: AppColors.brownMuted)),
        ],
      ),
    );
  }
}
