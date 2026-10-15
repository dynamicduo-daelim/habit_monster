import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/pixel_icons.dart';
import '../shell/main_shell.dart';
import 'home_parts.dart';

/// 몬스터 정보 · 교감 창.
/// 톡 건드리기 · 쓰다듬기(문지르기 게이지, 하루 1회 ♥+2) · 간식 주기 · 놀아주기(하루 1회 ♥+1) · 말 걸기.
class MonsterOverlay extends StatefulWidget {
  const MonsterOverlay({
    super.key,
    required this.monster,
    required this.initialLine,
    required this.initialFeedOpen,
    required this.bobUp,
    required this.onClose,
    required this.onOpenShop,
  });
  final OwnedMonster monster;
  final String initialLine;
  final bool initialFeedOpen;
  final bool bobUp;
  final VoidCallback onClose;
  final VoidCallback onOpenShop;

  @override
  State<MonsterOverlay> createState() => _MonsterOverlayState();
}

class _Pop {
  _Pop(this.x);
  final double x;
  bool up = false;
}

class _Float {
  _Float(this.text, this.color, this.x);
  final String text;
  final Color color;
  final double x; // %
  bool up = false;
}

class _MonsterOverlayState extends State<MonsterOverlay> {
  static const double _stageHeight = 250;

  final _rand = Random();
  final List<Timer> _timers = [];
  Timer? _hopTimer;
  Timer? _emoteTimer;
  Timer? _squishTimer;

  late String _line = widget.initialLine;
  late bool _feedOpen = widget.initialFeedOpen;
  bool _petMode = false;
  String? _emote;
  double _jump = 0;
  bool _squish = false;
  bool _ball = false;
  double _rubProg = 0;
  double _rubAccum = 0;
  Offset? _last;
  Offset _hand = const Offset(205, 120);
  final List<_Pop> _pops = [];
  final List<_Float> _floats = [];

  OwnedMonster get m => widget.monster;
  MonsterSpecies get sp => Catalog.speciesById(m.speciesId);
  GameState get _s => GameScope.read(context);
  MainShellState get _shell => MainShell.of(context);

  void _later(int ms, VoidCallback fn) {
    _timers.add(Timer(Duration(milliseconds: ms), () {
      if (mounted) fn();
    }));
  }

  String _randomLine() {
    final lines = sp.lines[tierOf(m.affection)]!;
    return lines[_rand.nextInt(lines.length)];
  }

  // ---------- 연출 ----------
  void _hop(int n) {
    _hopTimer?.cancel();
    var k = 0;
    void step() {
      if (!mounted) return;
      if (k >= n * 2) {
        setState(() => _jump = 0);
        return;
      }
      setState(() => _jump = k.isEven ? -22 : 0);
      k++;
      _hopTimer = Timer(const Duration(milliseconds: 170), step);
    }

    step();
  }

  void _showEmote(String kind) {
    _emoteTimer?.cancel();
    setState(() => _emote = kind);
    _emoteTimer = Timer(const Duration(milliseconds: 1700), () {
      if (mounted) setState(() => _emote = null);
    });
  }

  String _tierEmote() => const {
        AffectionTier.low: 'sweat',
        AffectionTier.mid: 'note',
        AffectionTier.high: 'heart',
      }[tierOf(m.affection)]!;

  void _floatText(String text, Color color) {
    final f = _Float(text, color, 40.0 + _rand.nextInt(21));
    setState(() => _floats.add(f));
    _later(40, () => setState(() => f.up = true));
    _later(1100, () => setState(() => _floats.remove(f)));
  }

  void _toastTierUp(AffectionTier before) {
    final after = tierOf(m.affection);
    if (after != before) _shell.toast('${withWa(sp.name)} ${tierName(after)} 사이가 됐어요!');
  }

  // ---------- 동작 ----------
  void _tapMon() {
    if (_petMode) return;
    _hop(1);
    _showEmote(_tierEmote());
    setState(() => _line = _randomLine());
  }

  void _talk() {
    var line = _randomLine();
    if (line == _line) line = _randomLine();
    _showEmote(tierOf(m.affection) == AffectionTier.low ? 'dots' : 'spark');
    setState(() {
      _line = line;
      _petMode = false;
      _feedOpen = false;
    });
  }

  void _play() {
    setState(() {
      _petMode = false;
      _feedOpen = false;
      _ball = true;
    });
    _later(900, () => setState(() => _ball = false));
    _later(350, () {
      _hop(3);
      _showEmote('note');
    });
    final before = tierOf(m.affection);
    final gain = _s.play(m);
    if (gain > 0) {
      setState(() => _line = '공이다! 신난다~ ${_randomLine()}');
      _later(500, () => _floatText('호감도 +$gain', AppColors.tierHigh));
      _toastTierUp(before);
    } else {
      setState(() => _line = '또 놀자! 공 던져줘!');
    }
  }

  void _togglePet() {
    if (m.pettedToday) {
      _shell.toast('오늘은 이미 쓰다듬었어요 · 내일 또!');
      return;
    }
    _last = null;
    _rubAccum = 0;
    setState(() {
      _petMode = !_petMode;
      _feedOpen = false;
    });
  }

  /// 손으로 문지르기: 몬스터 위를 문지른 거리만큼 게이지가 차고, 다 차면 오늘의 쓰다듬기 완료.
  void _rubAt(Offset p, Size stage) {
    if (!_petMode) return;
    final last = _last;
    _last = p;
    final onMon = p.dx > stage.width * 0.25 && p.dx < stage.width * 0.75 && p.dy > stage.height * 0.3;
    var prog = _rubProg;
    var squish = _squish;
    if (last != null && onMon) {
      final d = (p - last).distance;
      prog = min(100, _rubProg + d / 6);
      _rubAccum += d;
      if (_rubAccum >= 90) {
        _rubAccum = 0;
        squish = true;
        _squishTimer?.cancel();
        _squishTimer = Timer(const Duration(milliseconds: 180), () {
          if (mounted) setState(() => _squish = false);
        });
      }
    }
    setState(() {
      _hand = p;
      _rubProg = prog;
      _squish = squish;
    });
    if (prog >= 100) _finishPet(stage);
  }

  void _finishPet(Size stage) {
    final before = tierOf(m.affection);
    final gain = _s.pet(m);
    final pops = [for (var i = 0; i < 3; i++) _Pop(stage.width / 2 - 34 + i * 24)];
    setState(() {
      _petMode = false;
      _rubProg = 0;
      _squish = true;
      _pops
        ..clear()
        ..addAll(pops);
      _line = _randomLine();
    });
    _showEmote('heart');
    _hop(2);
    _later(40, () => setState(() {
          for (final p in _pops) {
            p.up = true;
          }
        }));
    _later(900, () => setState(() {
          _pops.clear();
          _squish = false;
        }));
    if (tierOf(m.affection) != before) {
      _toastTierUp(before);
    } else if (gain > 0) {
      _shell.toast('호감도 +$gain · 내일 또 쓰다듬어 주세요');
    } else {
      _shell.toast('호감도 최대! 기분 좋아 보여요');
    }
  }

  void _feed(ShopItem item) {
    final s = _s;
    if ((s.inventory[item.id] ?? 0) <= 0) return;
    if (m.level >= Economy.finalEvolutionLevel) {
      _shell.toast('이미 최종형이에요');
      return;
    }
    final before = m.level;
    s.feed(m, item);
    setState(() => _line = '냠냠! 맛있다!');
    _hop(1);
    _showEmote('heart');
    _floatText('+${item.exp} EXP', AppColors.tierMidText);
    final evolved = (before < Economy.firstEvolutionLevel && m.level >= Economy.firstEvolutionLevel) ||
        (before < Economy.finalEvolutionLevel && m.level >= Economy.finalEvolutionLevel);
    if (evolved) {
      _shell.toast('진화! ${m.stage}이 되었어요');
    } else if (m.level > before) {
      _shell.toast('레벨 업! Lv.${m.level}');
    } else {
      _shell.toast('+${item.exp} EXP');
    }
  }

  void _toBag() {
    final s = _s;
    if (s.fieldMonsters.length <= 1) {
      _shell.toast('필드에 1마리는 남겨둬요');
      return;
    }
    s.moveMonster(m, toField: false);
    _shell.toast('가방에 넣었어요');
    widget.onClose();
  }

  void _makePartner() {
    final s = _s;
    s.chatPartnerUid = m.uid;
    s.touch();
    _shell.toast('${withWa(sp.name)} 대화해요');
  }

  @override
  void dispose() {
    for (final t in [..._timers, _hopTimer, _emoteTimer, _squishTimer]) {
      t?.cancel();
    }
    super.dispose();
  }

  // ---------- 화면 ----------
  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final cat = Catalog.category(sp.categoryId);
    return HomeOverlay(
      onClose: widget.onClose,
      maxHeightFactor: 0.98,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cream,
          border: Border(top: BorderSide(color: AppColors.inkBrown, width: 4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(cat),
            Flexible(
              child: SingleChildScrollView(
                physics: _petMode ? const NeverScrollableScrollPhysics() : null,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _stage(),
                    const SizedBox(height: 10),
                    _moodRow(),
                    const SizedBox(height: 4),
                    _affText(),
                    const SizedBox(height: 10),
                    _actions(),
                    if (_feedOpen) ...[const SizedBox(height: 10), _feedPanel(s)],
                    const SizedBox(height: 10),
                    _status(cat),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: PixelButton(
                            label: '가방에 넣기',
                            onPressed: _toBag,
                            height: 42,
                            depth: 4,
                            fontSize: 11,
                            color: AppColors.shopCloth,
                            shadowColor: AppColors.brownShadow,
                            textColor: AppColors.brownText,
                            borderColor: AppColors.inkBrown,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PixelButton(
                            label: s.chatPartnerUid == m.uid ? '대화 상대 ✓' : '대화 상대로',
                            onPressed: _makePartner,
                            height: 42,
                            depth: 4,
                            color: AppColors.skyCard,
                            shadowColor: AppColors.skyCardShadow,
                            borderColor: AppColors.inkBrown,
                            // Galmuri에 ✓ 글자가 없어서 픽셀 아이콘으로 그린다.
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(s.chatPartnerUid == m.uid ? '대화 상대' : '대화 상대로',
                                    style: const TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                                if (s.chatPartnerUid == m.uid) ...[
                                  const SizedBox(width: 5),
                                  const PixelIcon(
                                    layers: [PixelLayer(PixelIcons.checkStroke, AppColors.brownText)],
                                    size: 10,
                                    strokeWidth: 3.5,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(HabitCategory cat) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        color: cat.color,
        border: const Border(bottom: BorderSide(color: AppColors.inkBrown, width: 4)),
      ),
      child: Row(
        children: [
          PixelIcon(
            layers: [for (final l in PixelIcons.category[cat.id]!) PixelLayer(l.path, AppColors.cream)],
            size: 22,
            outline: 1.5,
            outlineColor: AppColors.inkBrown,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(sp.name,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.brownText)),
          ),
          Container(
            color: AppColors.inkBrown,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('Lv.${m.level}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.butter)),
          ),
          const SizedBox(width: 8),
          BrownCloseButton(
            onTap: widget.onClose,
            color: AppColors.cream,
            iconColor: AppColors.inkBrown,
            shadow: false,
          ),
        ],
      ),
    );
  }

  Widget _stage() {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth - 6, _stageHeight - 6); // 테두리 안쪽
      final monBob = _squish ? 0.0 : (widget.bobUp ? -4.0 : 0.0);
      Widget stage = Container(
        height: _stageHeight,
        decoration: BoxDecoration(
          color: AppColors.sky,
          border: Border.all(color: _petMode ? AppColors.gold : AppColors.nightLine, width: 3),
        ),
        child: ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: size.height * 0.46,
                height: size.height * 0.1,
                child: const ColoredBox(color: AppColors.horizon),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: size.height * 0.3,
                child: Container(
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.grassLine, width: 3))),
                  child: const CustomPaint(painter: CheckerPainter(AppColors.grassDark, AppColors.grass, cell: 10)),
                ),
              ),
              Positioned(
                bottom: 14,
                child: Container(
                  width: 100,
                  height: 12,
                  color: AppColors.inkBrown.withValues(alpha: _jump != 0 ? 0.1 : 0.18),
                ),
              ),
              // 몬스터
              Positioned(
                bottom: 18,
                child: Transform.translate(
                  offset: Offset(0, _jump),
                  child: Semantics(
                    button: true,
                    label: '${sp.name} 톡 건드리기',
                    child: GestureDetector(
                      onTap: _petMode ? null : _tapMon,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.topCenter,
                        children: [
                          Transform.translate(
                            offset: Offset(0, monBob),
                            child: Transform.scale(
                              scaleX: _squish ? 1.08 : 1,
                              scaleY: _squish ? 0.9 : 1,
                              alignment: Alignment.bottomCenter,
                              child: PixelImage(sp.assetAt(m.level), height: 124),
                            ),
                          ),
                          if (_emote != null)
                            Positioned(
                              top: -2,
                              child: FractionalTranslation(
                                translation: const Offset(0, -1),
                                child: _EmoteBubble(kind: _emote!),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 대사 말풍선
              Positioned(
                left: 10,
                right: 10,
                top: 10,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.cream,
                        border: Border.all(color: AppColors.inkBrown, width: 3),
                      ),
                      child: Text(_line,
                          style: const TextStyle(fontSize: 11.5, height: 1.7, color: AppColors.brownText)),
                    ),
                    const Positioned(bottom: -6, child: BubbleTail(color: AppColors.cream)),
                  ],
                ),
              ),
              if (_ball)
                Positioned(
                  left: size.width * 0.6,
                  top: size.height * 0.42,
                  child: const PixelIcon(
                      layers: PixelIcons.actionPlay, size: 26, outline: 1.5, outlineColor: AppColors.inkBrown),
                ),
              for (final p in _pops)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 800),
                  left: p.x,
                  top: p.up ? 40 : 110,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 800),
                    opacity: p.up ? 0 : 1,
                    child: const PixelIcon(
                      layers: [PixelLayer(PixelIcons.heart, AppColors.tierHigh)],
                      size: 20,
                      outline: 1.5,
                      outlineColor: AppColors.inkBrown,
                    ),
                  ),
                ),
              for (final f in _floats)
                AnimatedPositioned(
                  duration: const Duration(seconds: 1),
                  left: size.width * f.x / 100,
                  top: f.up ? 30 : 90,
                  child: AnimatedOpacity(
                    duration: const Duration(seconds: 1),
                    opacity: f.up ? 0 : 1,
                    child: Text(f.text,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: f.color,
                          shadows: outlineShadows(AppColors.cream),
                        )),
                  ),
                ),
              if (_petMode) ...[
                Positioned(
                  left: 10,
                  bottom: 8,
                  width: 150,
                  child: IgnorePointer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('문질러서 쓰다듬기 · ${_rubProg.round()}%',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.white,
                              shadows: outlineShadows(AppColors.inkBrown, 1),
                            )),
                        const SizedBox(height: 4),
                        Container(
                          height: 10,
                          color: AppColors.inkBrown,
                          padding: const EdgeInsets.all(1),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: _rubProg / 100,
                            heightFactor: 1,
                            child: const ColoredBox(color: AppColors.tierHigh),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: _hand.dx - 20,
                  top: _hand.dy - 22,
                  child: IgnorePointer(
                    child: Transform.rotate(
                      angle: (widget.bobUp ? -12 : 8) * pi / 180,
                      child: const PixelIcon(
                          layers: PixelIcons.hand, size: 40, outline: 2, outlineColor: AppColors.inkBrown),
                    ),
                  ),
                ),
              ],
              if (!_petMode && _emote == null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: IgnorePointer(
                    child: Text('톡 눌러보세요!',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.white,
                          shadows: outlineShadows(AppColors.inkBrown, 1),
                        )),
                  ),
                ),
            ],
          ),
        ),
      );
      if (!_petMode) return stage;
      // 쓰다듬기 중: 마우스를 올려 움직이거나, 손가락으로 문지른다.
      Offset inner(Offset local) => local - const Offset(3, 3);
      return MouseRegion(
        cursor: SystemMouseCursors.none,
        onHover: (e) => _rubAt(inner(e.localPosition), size),
        onExit: (_) => _last = null,
        child: GestureDetector(
          onPanStart: (d) {
            _last = null;
            _rubAt(inner(d.localPosition), size);
          },
          onPanUpdate: (d) => _rubAt(inner(d.localPosition), size),
          onPanEnd: (_) => _last = null,
          child: stage,
        ),
      );
    });
  }

  Widget _moodRow() {
    final String key;
    final String text;
    if (m.pettedToday && m.playedToday) {
      key = 'heart';
      text = '오늘 최고로 신났어요!';
    } else if (m.pettedToday || m.playedToday) {
      key = 'note';
      text = '기분이 좋아 보여요';
    } else {
      key = tierOf(m.affection) == AffectionTier.low ? 'dots' : 'sweat';
      text = '심심해 보여요… 놀아줄까?';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        border: Border.all(color: AppColors.inkBrown, width: 3),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.cream,
              border: Border.all(color: AppColors.inkBrown, width: 2),
            ),
            child: PixelIcon(layers: [PixelIcons.emotes[key]!], size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brownText)),
          ),
          for (var i = 0; i < Economy.maxAffection ~/ 2; i++) ...[
            if (i > 0) const SizedBox(width: 1),
            PixelIcon(
              layers: [
                PixelLayer(
                  PixelIcons.heart,
                  m.affection >= (i + 1) * 2
                      ? AppColors.tierHigh
                      : (m.affection == i * 2 + 1 ? AppColors.heartHalf : AppColors.disabled),
                ),
              ],
              size: 15,
              outline: 1,
              outlineColor: AppColors.inkBrown,
            ),
          ],
        ],
      ),
    );
  }

  Widget _affText() {
    final t = tierOf(m.affection);
    final color = const {
      AffectionTier.low: AppColors.brownMuted,
      AffectionTier.mid: AppColors.tierMidText,
      AffectionTier.high: AppColors.tierHighText,
    }[t]!;
    return Text('${m.affection}/${Economy.maxAffection} · ${tierName(t)} 사이',
        textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color));
  }

  Widget _actions() {
    final items = [
      (
        '쓰다듬기',
        m.pettedToday ? '오늘 완료' : '하루 1번 · ♥+${Economy.petAffectionGain}',
        PixelIcons.actionPet,
        m.pettedToday,
        _petMode,
        _togglePet
      ),
      (
        '간식 주기',
        'EXP 업',
        PixelIcons.actionSnack,
        false,
        _feedOpen,
        () => setState(() {
              _feedOpen = !_feedOpen;
              _petMode = false;
            })
      ),
      (
        '놀아주기',
        m.playedToday ? '오늘 완료' : '하루 1번 · ♥+${Economy.playAffectionGain}',
        PixelIcons.actionPlay,
        m.playedToday,
        false,
        _play
      ),
      ('말 걸기', '대사 듣기', PixelIcons.actionTalk, false, false, _talk),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PressCard(
                  onTap: items[i].$6,
                  sunk: items[i].$5,
                  sinkBy: 3,
                  depth: 4,
                  color: items[i].$5 ? AppColors.butter : AppColors.cream,
                  shadowColor: AppColors.brownShadow,
                  borderColor: AppColors.inkBrown,
                  minHeight: 74,
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                  child: Column(
                    children: [
                      PixelIcon(layers: items[i].$3, size: 30, outline: 1.5, outlineColor: AppColors.inkBrown),
                      const SizedBox(height: 3),
                      Text(items[i].$1,
                          style:
                              const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                      const SizedBox(height: 3),
                      Text(items[i].$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 8.5, color: AppColors.brownMuted)),
                    ],
                  ),
                ),
                if (items[i].$4)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: IgnorePointer(
                      child: Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.green,
                          border: Border.all(color: AppColors.inkBrown, width: 3),
                        ),
                        child: const PixelIcon(
                          layers: [PixelLayer(PixelIcons.checkStroke, AppColors.brownText)],
                          size: 10,
                          strokeWidth: 3.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _feedPanel(GameState s) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.shopCloth,
        border: Border.all(color: AppColors.inkBrown, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('어떤 간식을 줄까? (경험치 물약)',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.woodDeep)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < Catalog.items.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _feedButton(s, Catalog.items[i])),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpenShop,
              child: Container(
                constraints: const BoxConstraints(minHeight: 28),
                alignment: Alignment.center,
                child: const Text('간식이 부족해요? 상점 가기',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.red,
                    )),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feedButton(GameState s, ShopItem it) {
    final n = s.inventory[it.id] ?? 0;
    return Opacity(
      opacity: n > 0 ? 1 : 0.55,
      child: PressCard(
        onTap: n > 0 ? () => _feed(it) : null,
        color: n > 0 ? AppColors.cream : AppColors.feedEmpty,
        shadowColor: AppColors.brownShadow,
        borderColor: AppColors.inkBrown,
        depth: 3,
        minHeight: 66,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        semanticLabel: '${it.name} 먹이기',
        child: Column(
          children: [
            PixelImage(it.asset, height: 22),
            const SizedBox(height: 2),
            Text('${it.short} ×$n',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.brownText)),
            const SizedBox(height: 2),
            Text('+${it.exp} EXP', style: const TextStyle(fontSize: 9, color: AppColors.tierMidText)),
          ],
        ),
      ),
    );
  }

  Widget _status(HabitCategory cat) {
    final String next;
    if (m.level < Economy.firstEvolutionLevel) {
      next = '1차 진화까지 Lv.${Economy.firstEvolutionLevel - m.level}';
    } else if (m.level < Economy.finalEvolutionLevel) {
      next = '최종 진화까지 Lv.${Economy.finalEvolutionLevel - m.level}';
    } else {
      next = '최종형 도달';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        border: Border.all(color: AppColors.inkBrown, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(4, 2, 7, 2),
                decoration: BoxDecoration(color: cat.color, border: Border.all(color: AppColors.inkBrown, width: 2)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PixelIcon(layers: PixelIcons.category[cat.id]!, size: 12),
                    const SizedBox(width: 4),
                    Text(cat.type,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.cream, border: Border.all(color: AppColors.inkBrown, width: 2)),
                child: Text(m.stage,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.brownText)),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 1),
                      child: PixelIcon(
                        layers: [PixelLayer(PixelIcons.star, i < sp.stars ? AppColors.gold : AppColors.disabled)],
                        size: 12,
                      ),
                    ),
                ],
              ),
              Text(sp.rarity, style: const TextStyle(fontSize: 9.5, color: AppColors.brownMuted)),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Container(
                color: AppColors.inkBrown,
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: const Text('EXP',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.butter)),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Container(
                  height: 11,
                  color: AppColors.inkBrown,
                  padding: const EdgeInsets.all(2),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (m.exp / Economy.expPerLevel).clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: const ColoredBox(color: AppColors.expBlue),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text('${formatNum(m.exp)}/${Economy.expPerLevel}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.brownText)),
            ],
          ),
          const SizedBox(height: 7),
          Text(next, textAlign: TextAlign.right, style: const TextStyle(fontSize: 9.5, color: AppColors.brownMuted)),
        ],
      ),
    );
  }
}

/// 몬스터 머리 위 감정 말풍선 (34×30).
class _EmoteBubble extends StatelessWidget {
  const _EmoteBubble({required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 34,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.cream,
            border: Border.all(color: AppColors.inkBrown, width: 3),
          ),
          child: PixelIcon(layers: [PixelIcons.emotes[kind]!], size: 18),
        ),
        const Positioned(left: 10, bottom: -5, child: BubbleTail(color: AppColors.cream, width: 8)),
      ],
    );
  }
}
