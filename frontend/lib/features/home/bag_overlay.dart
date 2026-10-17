import 'package:flutter/material.dart';

import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/pixel_icons.dart';
import '../shell/game_action.dart';
import '../shell/main_shell.dart';
import 'home_parts.dart';

/// 내 가방: [아이템] 칸 + 선택한 아이템 정보, [몬스터] 필드 ↔ 가방 옮기기.
class BagOverlay extends StatefulWidget {
  const BagOverlay({super.key, required this.onClose, required this.onUse, required this.onMonstersChanged});
  final VoidCallback onClose;

  /// "사용하러 가기" (아이템 id: 's' · 'm' · 'l' · 'ball').
  final ValueChanged<String> onUse;
  final VoidCallback onMonstersChanged;

  @override
  State<BagOverlay> createState() => _BagOverlayState();
}

class _BagOverlayState extends State<BagOverlay> {
  int _tab = 0; // 0 아이템, 1 몬스터
  String? _sel;

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    return HomeOverlay(
      onClose: widget.onClose,
      heightFactor: 0.9,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: AppColors.leather,
          border: Border(top: BorderSide(color: AppColors.inkBrown, width: 4)),
        ),
        child: CustomPaint(
          foregroundPainter: const DashedBorderPainter(color: AppColors.stitch),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const PixelIcon(layers: PixelIcons.bagHeader, size: 34, outline: 2, outlineColor: AppColors.inkBrown),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('내 가방',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.paper,
                            shadows: [Shadow(color: AppColors.woodDeep, offset: Offset(2, 2))],
                          )),
                    ),
                    BrownCloseButton(onTap: widget.onClose),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: _tabHeight - 3,
                        bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.paper,
                            border: Border.all(color: AppColors.inkBrown, width: 3),
                          ),
                          child: ListView(
                            padding: const EdgeInsets.all(12),
                            children: _tab == 0 ? _items(s) : _monsters(s),
                          ),
                        ),
                      ),
                      // 탭은 패널 위 테두리를 덮도록 나중에 그린다.
                      Positioned(
                        left: 6,
                        top: 0,
                        child: Row(
                          children: [
                            _tabButton(0, '아이템'),
                            const SizedBox(width: 4),
                            _tabButton(1, '몬스터 ${s.monsters.length}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const double _tabHeight = 40;

  Widget _tabButton(int i, String label) {
    final on = _tab == i;
    return GestureDetector(
      onTap: () => setState(() => _tab = i),
      child: Container(
        height: _tabHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        // 선택된 탭은 아래 테두리를 패널 색으로 덮어 이어 보이게 한다.
        foregroundDecoration: on
            ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.paper, width: 3)))
            : null,
        decoration: BoxDecoration(
          color: on ? AppColors.paper : AppColors.tabOff,
          border: Border.all(color: AppColors.inkBrown, width: 3),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brownText)),
      ),
    );
  }

  // ---------- 아이템 ----------
  List<Widget> _items(GameState s) {
    final slots = [
      for (final it in Catalog.items) (it, '${it.short} 물약', s.inventory[it.id] ?? 0),
      (Catalog.seongsilBall, Catalog.seongsilBall.short, s.balls),
    ];
    final sel = slots.where((x) => x.$1.id == _sel).firstOrNull;
    final cells = <Widget>[
      for (final (it, short, count) in slots)
        _ItemSlot(
          item: it,
          short: short,
          count: count,
          selected: _sel == it.id,
          onTap: () => setState(() => _sel = it.id),
        ),
      for (var i = 0; i < 4; i++)
        const CustomPaint(
          foregroundPainter: DashedBorderPainter(color: AppColors.brownShadow, width: 3),
          child: ColoredBox(color: AppColors.slotEmpty),
        ),
    ];
    return [
      for (var r = 0; r < cells.length; r += 4) ...[
        if (r > 0) const SizedBox(height: 8),
        Row(
          children: [
            for (var c = 0; c < 4; c++) ...[
              if (c > 0) const SizedBox(width: 8),
              Expanded(child: AspectRatio(aspectRatio: 1, child: cells[r + c])),
            ],
          ],
        ),
      ],
      const SizedBox(height: 12),
      if (sel == null)
        const Padding(
          padding: EdgeInsets.all(6),
          child: Text('아이템을 눌러 정보를 확인하세요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, height: 1.8, color: AppColors.footnoteBrown)),
        )
      else
        _SelectedItem(item: sel.$1, count: sel.$3, onUse: () => widget.onUse(sel.$1.id)),
    ];
  }

  // ---------- 몬스터 ----------
  List<Widget> _monsters(GameState s) {
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('함께하는 몬스터', style: _headStyle),
          Text('필드 ${s.fieldMonsters.length}/${Economy.fieldCapacity}', style: _headStyle),
        ],
      ),
      for (final m in s.monsters) ...[
        const SizedBox(height: 12),
        _MonsterCard(monster: m, onMove: () => _move(s, m)),
      ],
    ];
  }

  static const _headStyle = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.woodDeep);

  Future<void> _move(GameState s, OwnedMonster m) async {
    final shell = MainShell.of(context);
    final toField = !m.inField;
    if (toField && s.fieldMonsters.length >= Economy.fieldCapacity) {
      shell.toast('필드는 최대 ${Economy.fieldCapacity}마리');
      return;
    }
    if (!toField && s.fieldMonsters.length <= 1) {
      shell.toast('필드에 1마리는 남겨둬요');
      return;
    }
    final ok = await runGameAction(context, (r) => r.moveMonster(m, toField: toField));
    if (ok != true || !mounted) return;
    widget.onMonstersChanged();
    shell.toast(toField ? '필드로 꺼냈어요' : '가방에 넣었어요');
  }
}

class _ItemSlot extends StatelessWidget {
  const _ItemSlot({
    required this.item,
    required this.short,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final ShopItem item;
  final String short;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${item.name} $count개',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                color: selected ? AppColors.butter : AppColors.shopCloth,
                border: Border.all(color: selected ? AppColors.red : AppColors.inkBrown, width: 3),
              ),
              child: Stack(
                children: [
                  // inset 3px 3px 0 그림자
                  const Positioned(left: 0, top: 0, right: 0, child: SizedBox(height: 3, child: ColoredBox(color: AppColors.slotInset))),
                  const Positioned(left: 0, top: 0, bottom: 0, child: SizedBox(width: 3, child: ColoredBox(color: AppColors.slotInset))),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PixelImage(item.asset, height: 30),
                        const SizedBox(height: 2),
                        Text(short,
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.woodDeep)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                color: AppColors.inkBrown,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text('×$count', style: const TextStyle(fontSize: 10, color: AppColors.butter)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedItem extends StatelessWidget {
  const _SelectedItem({required this.item, required this.count, required this.onUse});
  final ShopItem item;
  final int count;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final isBall = item.id == Catalog.seongsilBall.id;
    final desc = isBall
        ? '챗봇 탐색에서 만난 몬스터에게 던져서 잡아요 · 1번에 1개'
        : '몬스터에게 먹이면 +${item.exp} EXP';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cream,
        border: Border.all(color: AppColors.inkBrown, width: 3),
        boxShadow: const [BoxShadow(color: AppColors.brownShadow, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.shopCloth,
              border: Border.all(color: AppColors.inkBrown, width: 3),
            ),
            child: PixelImage(item.asset, height: 34),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${item.name} '),
                    TextSpan(
                      text: '×$count',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w400, color: AppColors.brownMuted),
                    ),
                  ]),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brownText),
                ),
                const SizedBox(height: 3),
                Text(desc, style: const TextStyle(fontSize: 10, height: 1.6, color: AppColors.brownMuted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 112,
            child: PixelButton(
              label: '사용하러 가기 ▶',
              onPressed: count > 0 ? onUse : null,
              height: 44,
              depth: 4,
              fontSize: 11.5,
              color: AppColors.yellowButton,
              shadowColor: AppColors.yellowShadow,
              textColor: AppColors.brownText,
              disabledTextColor: AppColors.brownText,
              borderColor: AppColors.inkBrown,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonsterCard extends StatelessWidget {
  const _MonsterCard({required this.monster, required this.onMove});
  final OwnedMonster monster;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final m = monster;
    final sp = Catalog.speciesById(m.speciesId);
    final inField = m.inField;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: inField ? AppColors.cream : AppColors.bagCard,
        border: Border.all(color: AppColors.inkBrown, width: 3),
        boxShadow: const [BoxShadow(color: AppColors.brownShadow, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(border: Border.all(color: AppColors.inkBrown, width: 3)),
            child: CustomPaint(
              painter: const CheckerPainter(AppColors.grassCardDark, AppColors.grassCard),
              child: Padding(padding: const EdgeInsets.all(3), child: PixelImage(sp.assetAt(m.level))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${sp.name} '),
                    TextSpan(text: 'Lv.${m.level}', style: const TextStyle(fontSize: 10, color: AppColors.brownMuted)),
                  ]),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brownText),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      color: AppColors.inkBrown,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      child: const Text('EXP', style: TextStyle(fontSize: 8.5, color: AppColors.butter)),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Container(
                        height: 7,
                        color: AppColors.inkBrown,
                        padding: const EdgeInsets.all(1),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (m.exp / Economy.expPerLevel).clamp(0.0, 1.0),
                          heightFactor: 1,
                          child: const ColoredBox(color: AppColors.expBlue),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: inField ? AppColors.fieldGreen : AppColors.woodDark,
                    border: Border.all(color: AppColors.inkBrown, width: 2),
                  ),
                  child: Text('${inField ? '필드에 있음' : '가방에 있음'} · ${m.stage}',
                      style: const TextStyle(fontSize: 9.5, color: AppColors.white)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: PixelButton(
              label: inField ? '넣기' : '꺼내기',
              onPressed: onMove,
              height: 44,
              depth: 4,
              fontSize: 11.5,
              color: inField ? AppColors.shopCloth : AppColors.green,
              shadowColor: inField ? AppColors.brownShadow : AppColors.fieldGreen,
              textColor: AppColors.brownText,
              borderColor: AppColors.inkBrown,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
