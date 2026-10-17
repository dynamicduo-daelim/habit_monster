import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/audio/bgm.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/help_button.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/pixel_icons.dart';
import '../shell/game_action.dart';
import '../shell/main_shell.dart';
import 'attendance_popup.dart';
import 'bag_overlay.dart';
import 'habit_manage_screen.dart';
import 'habit_sheet.dart';
import 'home_parts.dart';
import 'monster_overlay.dart';
import 'purchase_popups.dart';
import 'shop_overlay.dart';

enum HomeOverlayKind { none, shop, bag, monster }

/// 필드 위 몬스터 한 마리의 위치 (본문 크기 대비 %).
class _FieldPos {
  const _FieldPos(this.x, this.y, this.flip);
  final double x;
  final double y;
  final bool flip;
}

/// 홈: 초원 위를 몬스터들이 돌아다니고, 가끔 호감도에 맞는 말을 한다.
/// 오른쪽 위 상점·가방, 아래 슬라이드 시트, 몬스터를 누르면 교감 창.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.active = true,
    this.tutorial = false,
    this.monsterKeys,
    this.iconsKey,
    this.sheetKey,
  });

  /// 홈 탭이 보이는 중인지 (아니면 돌아다니기/말풍선을 멈춘다).
  final bool active;

  /// 튜토리얼이 떠 있는지 (몬스터를 멈추고 열려 있던 창을 닫는다).
  final bool tutorial;

  /// 튜토리얼이 가리킬 곳: 필드 몬스터들(필드 순서대로) · 오른쪽 위 아이콘들 · 아래 시트.
  final List<GlobalKey>? monsterKeys;
  final GlobalKey? iconsKey;
  final GlobalKey? sheetKey;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _rand = Random();
  final Map<String, _FieldPos> _pos = {};
  Map<String, String> _talk = {};
  Timer? _wander;
  Timer? _firstWander;
  Timer? _bob;
  Timer? _chatter;
  Timer? _talkClear;
  int _tick = 0;

  /// 끌고 있는 몬스터 (한 번에 한 마리).
  String? _dragUid;

  /// 옮긴 자리에서 쉬는 중인 몬스터 → 다시 돌아다니게 할 타이머.
  final Map<String, Timer> _rest = {};

  HomeOverlayKind _overlay = HomeOverlayKind.none;
  String? _selUid;
  bool _monFeedOpen = false;
  String? _monFirstLine;
  String? _shopLine;

  /// 상점(구매 팝업 포함)이 열려 있어 상점 곡을 틀었는지.
  bool _shopMusic = false;

  /// 상점 수량 팝업에 띄운 물건 / 방금 산 것 (구매 완료 팝업).
  ShopItem? _qtyItem;
  Purchase? _purchase;

  @override
  void initState() {
    super.initState();
    _firstWander = Timer(const Duration(milliseconds: 400), _step);
    _wander = Timer.periodic(const Duration(milliseconds: 2600), (_) => _step());
    _bob = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _tick++);
    });
    _chatter = Timer.periodic(const Duration(milliseconds: 5200), (_) => _chatterStep());
    WidgetsBinding.instance.addPostFrameCallback((_) => _openingChatter());
  }

  bool get _idle => widget.active && !widget.tutorial && _overlay == HomeOverlayKind.none;

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (widget.tutorial && !old.tutorial) {
      _iconsHidden = false; // 튜토리얼이 아이콘을 가리킨다
      _overlay = HomeOverlayKind.none;
      _qtyItem = null;
      _purchase = null;
      _talk = {};
    }
  }

  String _randomLine(OwnedMonster m) {
    final lines = Catalog.speciesById(m.speciesId).lines[tierOf(m.affection)]!;
    return lines[_rand.nextInt(lines.length)];
  }

  // ---------- 필드 ----------
  /// 마지막으로 그린 필드 크기 (걷기 타이머가 영역을 계산할 때 쓴다).
  BoxConstraints? _fieldBox;

  // ---------- 오른쪽 아이콘 줄 (숨기기) ----------
  static const _iconRight = 8.0, _iconTop = 8.0, _iconColumnW = 64.0;
  static const _handleW = 22.0, _handleH = 56.0;

  /// 아이콘 줄을 오른쪽으로 밀어 숨겼는지.
  bool _iconsHidden = false;
  double _iconSwipe = 0;

  /// 아이콘 줄의 높이를 재는 키 (튜토리얼이 키를 주면 그것을 쓴다).
  final _ownIconsKey = GlobalKey();
  GlobalKey get _iconsKey => widget.iconsKey ?? _ownIconsKey;

  void _setIconsHidden(bool hidden) {
    if (_iconsHidden != hidden) setState(() => _iconsHidden = hidden);
  }

  /// 몬스터가 가리면 안 되는 오른쪽 위 버튼 영역 (필드 안 px). 숨겼으면 손잡이만.
  Rect _buttonsRect(double w) {
    if (_iconsHidden) return Rect.fromLTWH(w - _handleW - 6, _iconTop + 40 - 6, _handleW + 6, _handleH + 12);
    final colH = _iconsKey.currentContext?.size?.height ?? 300;
    const gap = 6.0;
    return Rect.fromLTWH(w - _iconRight - _iconColumnW - gap, 0, _iconColumnW + _iconRight + gap, _iconTop + colH + gap);
  }

  _FieldPos _initialPos(int i) => _FieldPos(4.0 + i * 16, 52.0 + (i % 2) * 10, false);

  /// 몬스터가 다닐 수 있는 영역 = 잔디 전체 (본문 크기 대비 %, 몬스터 왼쪽 위 기준). 걷기와 끌기가 같은 규칙을 쓴다.
  /// 위: 발(그림 아래 끝)이 숲 바로 아래 잔디에 닿는 곳, 그리고 "나의 필드" 바 아래. 아래: 이름표가 접힌 시트 위에 보이는 곳.
  /// 오른쪽 위 아이콘 줄([_buttonsRect])은 가리지 않는다 — 그 아래쪽 잔디는 다닐 수 있다.
  /// 화면 크기마다 배경이 다르게 잘려서 px로 계산한다. [x] · [y]를 이 영역 안의 가장 가까운 곳으로 옮겨 돌려준다.
  (double, double) _place(BoxConstraints box, MonsterSpecies sp, double x, double y) {
    final w = box.maxWidth, h = box.maxHeight;
    final scale = max(w / AppAssets.homeFieldW, h / AppAssets.homeFieldH); // BoxFit.cover
    final imgH = AppAssets.homeFieldH * scale;
    final grassPx = h - imgH + imgH * AppAssets.homeFieldGrassTop; // 아래 맞춤 (bottomCenter)
    const labelH = 24.0; // 그림자 + 이름표
    const columnW = 100.0; // 그림 · 이름표가 차지하는 폭 (대략)
    const leftGap = 20.0, rightGap = 6.0; // 왼쪽은 말풍선이 덜 잘리게 조금 더
    const fieldBarBottom = 12.0 + 28 + 6; // "나의 필드" 바 위치(top 12) + 높이 + 틈
    final monH = sp.fieldHeight + labelH;
    final minX = leftGap, maxX = max(minX, w - columnW - rightGap);
    final minY = max(fieldBarBottom, grassPx - sp.fieldHeight + 6);
    final maxY = max(minY, h - HabitSheet.closedHeight - monH);
    var px = (x / 100 * w).clamp(minX, maxX), py = (y / 100 * h).clamp(minY, maxY);

    // 버튼 영역과 겹치면 왼쪽으로 비키거나 아래로 내려가기 중 덜 움직이는 쪽
    final b = _buttonsRect(w);
    if (Rect.fromLTWH(px, py, columnW, monH).overlaps(b)) {
      final toLeft = b.left - columnW; // 오른쪽 끝이 버튼 왼쪽에 닿게
      final toDown = b.bottom; // 위 끝이 버튼 아래에 닿게
      final canLeft = toLeft >= minX, canDown = toDown <= maxY;
      if (canLeft && (!canDown || px - toLeft <= toDown - py)) {
        px = toLeft;
      } else if (canDown) {
        py = toDown;
      }
    }
    return (px / w * 100, py / h * 100);
  }

  void _step() {
    final box = _fieldBox;
    if (!mounted || !_idle || box == null) return;
    final mons = GameScope.read(context).fieldMonsters;
    setState(() {
      for (var i = 0; i < mons.length; i++) {
        final m = mons[i];
        if (m.uid == _dragUid || _rest.containsKey(m.uid)) continue; // 끄는 중 · 옮긴 자리에서 쉬는 중
        final c = _pos[m.uid] ?? _initialPos(i);
        final sp = Catalog.speciesById(m.speciesId);
        final (nx, ny) = _place(box, sp, c.x + (_rand.nextDouble() * 34 - 17), c.y + (_rand.nextDouble() * 14 - 7));
        _pos[m.uid] = _FieldPos(nx, ny, sp.facesLeft && nx > c.x);
      }
    });
  }

  // ---------- 끌어 옮기기 ----------
  void _dragStart(OwnedMonster m, int i) {
    if (!_idle || _dragUid != null) return;
    _rest.remove(m.uid)?.cancel();
    setState(() {
      _dragUid = m.uid;
      _pos[m.uid] ??= _initialPos(i);
      _talk = Map.of(_talk)..remove(m.uid);
    });
  }

  void _dragMove(OwnedMonster m, DragUpdateDetails d, BoxConstraints box) {
    if (_dragUid != m.uid) return;
    final c = _pos[m.uid]!;
    final sp = Catalog.speciesById(m.speciesId);
    final (nx, ny) = _place(box, sp, c.x + d.delta.dx / box.maxWidth * 100, c.y + d.delta.dy / box.maxHeight * 100);
    final flip = d.delta.dx == 0 ? c.flip : sp.facesLeft && d.delta.dx > 0;
    setState(() => _pos[m.uid] = _FieldPos(nx, ny, flip));
  }

  /// 내려놓은 몬스터의 한마디 (호감도 단계별).
  static const _dropLines = {
    AffectionTier.low: ['…내려 줘.', '어디로 데려가는 거야?', '(두리번두리번)'],
    AffectionTier.mid: ['여기도 괜찮네!', '우와, 높다!', '새 자리 좋아!'],
    AffectionTier.high: ['한 번 더! 한 번 더!', '네가 옮겨 주니까 좋아!', '여기서 기다릴게!'],
  };

  /// 하트가 뿅뿅 튀어나오는 몬스터 → 몇 번째 하트인지 (애니메이션을 새로 시작하는 키).
  final Map<String, int> _hearts = {};
  final Map<String, Timer> _heartClear = {};

  /// 내려놓기: 한마디 하고, 그 자리에서 잠깐 쉬다가 다시 돌아다닌다.
  /// 오늘 처음이면 호감도 +1과 함께 하트가 뿅뿅 (단계가 오르면 토스트도).
  Future<void> _dragEnd(OwnedMonster m) async {
    if (_dragUid != m.uid) return;
    setState(() => _dragUid = null);
    _rest[m.uid] = Timer(Economy.dragRest, () => _rest.remove(m.uid));
    final before = tierOf(m.affection);
    final gain = await runGameAction(context, (r) => r.dragMonster(m)) ?? 0;
    if (!mounted) return;
    final after = tierOf(m.affection);
    final lines = _dropLines[after]!;
    _showTalk({m.uid: lines[_rand.nextInt(lines.length)]}, const Duration(milliseconds: 2400));
    if (gain == 0) return;
    _heartClear.remove(m.uid)?.cancel();
    setState(() => _hearts[m.uid] = (_hearts[m.uid] ?? 0) + 1);
    _heartClear[m.uid] = Timer(const Duration(milliseconds: 1200), () {
      _heartClear.remove(m.uid);
      if (mounted) setState(() => _hearts.remove(m.uid));
    });
    if (after != before) {
      MainShell.of(context).toast('${withWa(Catalog.speciesById(m.speciesId).name)} ${tierName(after)} 사이가 됐어요!');
    }
  }

  // ---------- 말풍선 ----------
  void _showTalk(Map<String, String> talk, Duration hold) {
    _talkClear?.cancel();
    setState(() => _talk = talk);
    _talkClear = Timer(hold, () {
      if (mounted) setState(() => _talk = {});
    });
  }

  /// 처음 들어왔을 때 두 마리가 인사한다.
  void _openingChatter() {
    if (!mounted || widget.tutorial) return;
    final f = GameScope.read(context).fieldMonsters;
    if (f.length < 2) return;
    _showTalk({f[1].uid: _randomLine(f[1]), f.last.uid: _randomLine(f.last)}, const Duration(milliseconds: 3600));
  }

  void _chatterStep() {
    if (!mounted || !_idle) return;
    final f = GameScope.read(context).fieldMonsters;
    if (f.isEmpty || _rand.nextDouble() < 0.25) {
      setState(() => _talk = {});
      return;
    }
    final n = f.length > 2 && _rand.nextDouble() < 0.3 ? 2 : 1;
    final picks = f.where((m) => m.uid != _dragUid).toList()..shuffle(_rand); // 끄는 중엔 말하지 않는다
    _showTalk({for (final m in picks.take(n)) m.uid: _randomLine(m)}, const Duration(milliseconds: 3400));
  }

  // ---------- 창 열기 ----------
  void _openMonster(OwnedMonster m, {bool feed = false, String? line}) {
    setState(() {
      _overlay = HomeOverlayKind.monster;
      _selUid = m.uid;
      _monFeedOpen = feed;
      _monFirstLine = line ?? _randomLine(m);
      _talk = {};
    });
  }

  void _openShop() => setState(() {
        _overlay = HomeOverlayKind.shop;
        _shopLine = null;
      });

  void _close() => setState(() => _overlay = HomeOverlayKind.none);

  /// 간식을 줄 몬스터: 필드의 대화 상대 → 필드 첫 몬스터 → 아무나 (없으면 null).
  OwnedMonster? _feedTarget(GameState s) {
    final field = s.fieldMonsters;
    return field.where((m) => m.uid == s.chatPartnerUid).firstOrNull ??
        field.firstOrNull ??
        s.monsters.firstOrNull;
  }

  /// [_feedTarget]에게 간식 창을 열어준다.
  void _openFeed(String line) {
    final target = _feedTarget(GameScope.read(context));
    if (target == null) {
      _close();
      MainShell.of(context).toast('아직 함께하는 몬스터가 없어요');
      return;
    }
    _openMonster(target, feed: true, line: line);
  }

  /// 가방에서 "사용하러 가기".
  void _useFromBag(String key) {
    final shell = MainShell.of(context);
    if (key == Catalog.seongsilBall.id) {
      _close();
      shell.goTab(MainShell.chatTab);
      shell.toast('탐색할 때 성실볼을 쓸 수 있어요');
      return;
    }
    _openFeed('그거 나 주는 거야?');
  }

  // ---------- 상점 구매 ----------
  Future<void> _buy(ShopItem item, int count) async {
    final s = GameScope.read(context);
    final ok = await runGameAction(context, (r) => r.buy(item, count: count));
    if (ok != true || !mounted) return;
    setState(() {
      _qtyItem = null;
      _shopLine = ShopOverlay.reactionFor(item.id);
      _purchase = Purchase(item, count, s.ownedCount(item));
    });
  }

  /// 구매 완료 팝업의 "몬스터에게 주기" / "탐색하러 가기".
  void _usePurchase() {
    final p = _purchase!;
    setState(() => _purchase = null);
    if (p.isBall) {
      _close();
      MainShell.of(context).goTab(MainShell.chatTab);
      return;
    }
    _openFeed('방금 산 거 나 주는 거야?');
  }

  @override
  void dispose() {
    for (final t in [_wander, _firstWander, _bob, _chatter, _talkClear, ..._heartClear.values, ..._rest.values]) {
      t?.cancel();
    }
    super.dispose();
  }

  /// 상점이 열리면 상점 곡, 닫히면 홈 곡으로 (그리기가 끝난 뒤 셸에 알린다).
  void _syncShopMusic() {
    final open = _overlay == HomeOverlayKind.shop || _qtyItem != null || _purchase != null;
    if (open == _shopMusic) return;
    _shopMusic = open;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MainShell.maybeOf(context)?.setMusicOverride(MainShell.homeTab, open ? BgmTrack.shop : null);
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncShopMusic();
    final s = GameScope.of(context);
    final mons = s.fieldMonsters;
    final sel = s.monsterByUid(_selUid);
    final bobUp = _tick.isOdd;

    // 아래쪽(앞)에 있는 몬스터를 나중에 그린다. 끌고 있는 몬스터는 맨 위.
    int depth(int i) => mons[i].uid == _dragUid ? 1000 : 0;
    final order = [for (var i = 0; i < mons.length; i++) i]
      ..sort((a, b) {
        final d = depth(a).compareTo(depth(b));
        if (d != 0) return d;
        return (_pos[mons[a].uid] ?? _initialPos(a)).y.compareTo((_pos[mons[b].uid] ?? _initialPos(b)).y);
      });

    return LayoutBuilder(builder: (context, box) {
      _fieldBox = box;
      return ClipRect(
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: AppColors.fieldSky)),
            const Positioned.fill(
              child: PixelImage(AppAssets.homeField, fit: BoxFit.cover, alignment: Alignment.bottomCenter),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.fromLTRB(7, 0, 3, 0),
                decoration: BoxDecoration(
                  color: AppColors.nightDeep.withValues(alpha: 0.8),
                  border: Border.all(color: AppColors.nightLine2, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('나의 필드 ${mons.length}/${Economy.fieldCapacity}',
                        style: const TextStyle(fontSize: 10, color: AppColors.purpleSoft)),
                    const SizedBox(width: 2),
                    const HelpButton(title: '나의 필드', items: [
                      ('필드가 뭐예요?', '함께 지내는 몬스터가 돌아다니는 곳이에요. 최대 ${Economy.fieldCapacity}마리까지 꺼내 둘 수 있어요.'),
                      ('몬스터와 놀기', '몬스터를 누르면 쓰다듬기 · 간식 주기 · 놀아주기 · 말 걸기를 할 수 있어요. 친해질수록 호감도(♥)가 올라요.'),
                      ('옮기기', '몬스터를 누른 채 끌면 원하는 자리로 옮길 수 있어요. 몬스터마다 하루 1번 호감도 ♥+${Economy.dragAffectionGain}.'),
                      ('넣고 꺼내기', '가방을 열면 몬스터를 필드로 꺼내거나 가방에 넣을 수 있어요.'),
                    ]),
                  ],
                ),
              ),
            ),
            for (final i in order) _monster(mons[i], i, box, bobUp),
            // 오른쪽 아이콘 줄: 오른쪽으로 밀면 화면 밖으로 숨고, 손잡이(◀)를 누르거나 왼쪽으로 밀면 다시 나온다.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              right: _iconsHidden ? -_iconColumnW : _iconRight,
              top: _iconTop,
              child: GestureDetector(
                onHorizontalDragStart: (_) => _iconSwipe = 0,
                onHorizontalDragUpdate: (d) => _iconSwipe += d.delta.dx,
                onHorizontalDragEnd: (d) {
                  if (_iconSwipe > 24 || d.primaryVelocity! > 300) _setIconsHidden(true);
                },
                child: Column(
                key: _iconsKey,
                children: [
                  _IconSpot(
                    label: '상점',
                    semantic: '상점',
                    icon: PixelIcons.shopStall,
                    labelColor: AppColors.goldLight,
                    bob: bobUp ? -4 : 0,
                    badge: true,
                    onTap: _openShop,
                  ),
                  const SizedBox(height: 6),
                  _IconSpot(
                    label: '가방',
                    semantic: '내 가방',
                    icon: PixelIcons.fieldBag,
                    labelColor: AppColors.text,
                    bob: bobUp ? 0 : -4,
                    onTap: () => setState(() => _overlay = HomeOverlayKind.bag),
                  ),
                  const SizedBox(height: 6),
                  _IconSpot(
                    label: '출석',
                    semantic: '출석부',
                    icon: PixelIcons.fieldCalendar,
                    labelColor: AppColors.text,
                    bob: bobUp ? -4 : 0,
                    onTap: () => showAttendancePopup(
                      context,
                      onGoChat: () => MainShell.of(context).goTab(MainShell.chatTab),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _IconSpot(
                    label: '습관',
                    semantic: '습관 관리',
                    icon: PixelIcons.fieldQuest,
                    labelColor: AppColors.text,
                    bob: bobUp ? 0 : -4,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const HabitManageScreen()),
                    ),
                  ),
                ],
              ),
              ),
            ),
            // 숨겼을 때 오른쪽 끝에 남는 손잡이
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              right: _iconsHidden ? 0 : -_handleW,
              top: _iconTop + 40,
              child: Semantics(
                button: true,
                label: '아이콘 보이기',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => _setIconsHidden(false),
                  onHorizontalDragEnd: (d) {
                    if (d.primaryVelocity! < 0) _setIconsHidden(false);
                  },
                  child: Container(
                    width: _handleW,
                    height: _handleH,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.nightDeep.withValues(alpha: 0.85),
                      border: Border.all(color: AppColors.nightLine2, width: 2),
                    ),
                    child: const Text('◀', style: TextStyle(fontSize: 11, color: AppColors.text)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: HabitSheet(
                key: widget.sheetKey,
                maxHeight: box.maxHeight,
                onGoChat: () => MainShell.of(context).goTab(MainShell.chatTab),
              ),
            ),
            if (_overlay == HomeOverlayKind.shop)
              Positioned.fill(
                child: ShopOverlay(
                  line: _shopLine,
                  bobUp: bobUp,
                  onBuyPressed: (it) => setState(() => _qtyItem = it),
                  onClose: _close,
                ),
              ),
            if (_overlay == HomeOverlayKind.bag)
              Positioned.fill(
                child: BagOverlay(
                  onClose: _close,
                  onUse: _useFromBag,
                  onMonstersChanged: () => setState(() {}),
                ),
              ),
            if (_overlay == HomeOverlayKind.monster && sel != null)
              Positioned.fill(
                child: MonsterOverlay(
                  key: ValueKey(sel.uid),
                  monster: sel,
                  initialLine: _monFirstLine ?? '',
                  initialFeedOpen: _monFeedOpen,
                  bobUp: bobUp,
                  onClose: _close,
                  onOpenShop: _openShop,
                ),
              ),
            if (_qtyItem != null)
              Positioned.fill(
                child: QuantityPopup(
                  key: ValueKey(_qtyItem!.id),
                  item: _qtyItem!,
                  onCancel: () => setState(() => _qtyItem = null),
                  onBuy: (n) => _buy(_qtyItem!, n),
                ),
              ),
            if (_purchase != null)
              Positioned.fill(
                child: PurchaseDonePopup(
                  purchase: _purchase!,
                  bobUp: bobUp,
                  onUse: _usePurchase,
                  onClose: () => setState(() => _purchase = null),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _monster(OwnedMonster m, int i, BoxConstraints box, bool bobUp) {
    final sp = Catalog.speciesById(m.speciesId);
    final p = _pos[m.uid] ?? _initialPos(i);
    final dragging = _dragUid == m.uid;
    // 끄는 중엔 통통 대신 살짝 들려 있다 (그림자는 발밑에 남는다).
    final bob = dragging ? -10.0 : (((bobUp ? 1 : 0) + i).isOdd ? -3.0 : 0.0);
    final talk = _talk[m.uid];
    final tier = tierOf(m.affection);
    return AnimatedPositioned(
      key: ValueKey(m.uid),
      // 끄는 중엔 손가락을 바로 따라오고, 걸을 때는 천천히 움직인다.
      duration: dragging ? Duration.zero : const Duration(milliseconds: 2400),
      curve: Curves.linear,
      left: p.x / 100 * box.maxWidth,
      top: p.y / 100 * box.maxHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Column(
            key: widget.monsterKeys?.elementAtOrNull(i),
            children: [
              Semantics(
                button: true,
                label: '${sp.name} 정보 보기',
                child: GestureDetector(
                  onTap: () => _openMonster(m),
                  // 누른 채 움직이면 끌어 옮기기 (짧게 누르면 위의 onTap)
                  onPanStart: (_) => _dragStart(m, i),
                  onPanUpdate: (d) => _dragMove(m, d, box),
                  onPanEnd: (_) => _dragEnd(m),
                  onPanCancel: () => _dragEnd(m),
                  child: Column(
                    children: [
                      Transform.translate(
                        offset: Offset(0, bob),
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.diagonal3Values(p.flip ? -1 : 1, 1, 1),
                          child: PixelImage(sp.assetAt(m.level), height: sp.fieldHeight),
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -3),
                        child: Container(width: 46, height: 6, color: AppColors.ink.withValues(alpha: 0.45)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.nightDeep.withValues(alpha: 0.85),
                  border: Border.all(color: AppColors.nightLine2, width: 2),
                ),
                child: Text('${sp.name} Lv.${m.level}', style: const TextStyle(fontSize: 9, color: AppColors.text)),
              ),
            ],
          ),
          if (talk != null)
            // 몬스터 머리 위 10px
            Positioned(
              top: -10,
              child: IgnorePointer(
                child: FractionalTranslation(
                  translation: const Offset(0, -1),
                  child: _TalkBubble(text: talk, tier: tier),
                ),
              ),
            ),
          if (_hearts[m.uid] case final n?)
            // 머리 근처에서 하트 세 개가 뿅뿅 올라가며 사라진다
            Positioned(
              top: 6,
              child: IgnorePointer(child: _HeartBurst(key: ValueKey('hearts_${m.uid}_$n'))),
            ),
        ],
      ),
    );
  }
}

/// 호감도가 오를 때 하트 세 개가 엇갈려 튀어 오르며 사라진다 (약 1초).
class _HeartBurst extends StatelessWidget {
  const _HeartBurst({super.key});

  static const _spots = [(-22.0, 0.0), (0.0, 0.15), (22.0, 0.3)]; // (가로 위치, 늦게 시작하는 정도)

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1000),
      builder: (context, t, _) => SizedBox(
        width: 70,
        height: 20,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            for (final (dx, delay) in _spots)
              Builder(builder: (_) {
                final k = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
                return Transform.translate(
                  offset: Offset(dx, -34 * Curves.easeOut.transform(k)),
                  child: Opacity(
                    opacity: k == 0 ? 0 : (1 - k * k),
                    child: const PixelIcon(layers: [PixelLayer(PixelIcons.heart, AppColors.tierHigh)], size: 14),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// 필드 몬스터 말풍선: 호감도 단계 + 대사.
class _TalkBubble extends StatelessWidget {
  const _TalkBubble({required this.text, required this.tier});
  final String text;
  final AffectionTier tier;

  static Color tierColor(AffectionTier t) =>
      const {AffectionTier.low: AppColors.tierLow, AffectionTier.mid: AppColors.tierMid, AffectionTier.high: AppColors.tierHigh}[t]!;

  @override
  Widget build(BuildContext context) {
    final c = tierColor(tier);
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.parchment,
            border: Border.all(color: AppColors.ink, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x880D0B16), offset: Offset(3, 3))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PixelIcon(layers: [PixelLayer(PixelIcons.heart, c)], size: 9),
                  const SizedBox(width: 4),
                  Text(tierName(tier),
                      style: TextStyle(fontSize: 8.5, color: c, shadows: outlineShadows(AppColors.ink, 1))),
                ],
              ),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(fontSize: 10.5, height: 1.6, color: AppColors.night)),
            ],
          ),
        ),
        const Positioned(bottom: -6, child: BubbleTail(color: AppColors.parchment, borderColor: AppColors.ink)),
      ],
    );
  }
}

class _IconSpot extends StatelessWidget {
  const _IconSpot({
    required this.label,
    required this.semantic,
    required this.icon,
    required this.labelColor,
    required this.bob,
    required this.onTap,
    this.badge = false,
  });
  final String label;
  final String semantic;
  final List<PixelLayer> icon;
  final Color labelColor;
  final double bob;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(
            children: [
              Transform.translate(
                offset: Offset(0, bob),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PixelIcon(layers: icon, size: 48, outline: 3),
                    if (badge)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.notifyDot,
                            border: Border.all(color: AppColors.ink, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 1),
              Text(label,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                      shadows: outlineShadows(AppColors.ink))),
            ],
          ),
        ),
      ),
    );
  }
}
