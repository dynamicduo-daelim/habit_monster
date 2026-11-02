import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/pixel_icons.dart';
import '../shell/game_action.dart';
import '../shell/main_shell.dart';
import 'home_parts.dart';
import '../../core/theme/app_theme.dart';

/// 교감 창에서 고른 행동. 말 걸기는 칸을 바꾸지 않는 한 번짜리 동작이라 없다.
enum _Tab { pet, feed, play }

/// 몬스터 정보 · 교감 창 (기획 2026-10-29-교감-창-개편 — 밤 보라 · 네모 픽셀).
/// 위에서부터 머리(이름 · Lv · EXP) → 무대(오른쪽 아래에 쓰다듬기 · 말 걸기) → 고른 행동의 칸 → 간식 · 놀아주기 → 가방 · 대화 상대.
/// - 간식: 물약을 무대의 몬스터에게 직접 끌어다 놓는다.
/// - 놀아주기: 무대가 길어지고, 무대를 휙 밀면(스와이프) 그 방향 · 세기대로 공이 날아가 몬스터가 뛰어가 잡는다 (첫 번째만 하루 1회 ♥+1).
/// - 쓰다듬기: 무대의 몬스터를 문지르면 게이지가 차고, 다 차면 하루 1회 ♥+2.
/// - 말 걸기 · 톡 건드리기: 대사.
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

  /// 가방 · 상점에서 "주기"로 열었는지. 지금은 기본 칸이 간식이라 같지만, 부르는 쪽의 뜻을 남겨 둔다.
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
  /// 무대 높이 · 몬스터 크기: 310 · 140 → 360 · 124 (11-02, 사용자 "몬스터 살짝 작게, 맵을 더 많이").
  static const double _stageHeight = 360;

  /// 놀아주기 때 무대 높이 (기획 [가정] 430 — 시안 470은 360폭 화면에서 아래가 잘려서).
  static const double _playStageHeight = 430;
  static const double _monSize = 124;
  static const double _playMonSize = 94;

  /// 무대 위쪽 이만큼(비율)은 하늘 · 나무라 공을 던질 수 없다.
  static const double _groundTop = 0.4;
  static const Duration _ballFlight = Duration(milliseconds: 450);
  static const Duration _monRun = Duration(milliseconds: 700);

  final _rand = Random();
  final List<Timer> _timers = [];
  Timer? _hopTimer;
  Timer? _emoteTimer;
  Timer? _squishTimer;

  late String _line = widget.initialLine;
  _Tab _tab = _Tab.feed;
  String? _emote;
  double _jump = 0;
  bool _squish = false;
  double _rubProg = 0;
  double _rubAccum = 0;
  Offset? _last;
  Offset _hand = const Offset(205, 120);
  final List<_Pop> _pops = [];
  final List<_Float> _floats = [];

  /// 물약을 끄는 중 (무대에 "여기로" 표시).
  bool _dragging = false;

  // ---------- 공놀이 ----------
  /// 놀아주기에서 몬스터 발의 위치 (무대 안 px). null이면 가운데 아래.
  Offset? _monPos;

  /// 공의 위치 (무대 안 px). null이면 몬스터가 들고 있다.
  Offset? _ballPos;
  bool _throwing = false;
  bool _running = false;

  /// 스와이프 중인 손가락 위치 (조준선) · 시작 위치. null이면 조준 중이 아님.
  Offset? _aim;
  Offset? _aimStart;
  bool _faceRight = false;
  int _throws = 0;

  OwnedMonster get m => widget.monster;
  MonsterSpecies get sp => Catalog.speciesById(m.speciesId);
  GameState get _s => GameScope.read(context);
  MainShellState get _shell => MainShell.of(context);
  bool get _petMode => _tab == _Tab.pet && !m.pettedToday;

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
  void _select(_Tab t) {
    if (t == _Tab.pet && m.pettedToday) {
      _shell.toast('오늘은 이미 쓰다듬었어요 · 내일 또!');
      return;
    }
    _last = null;
    _rubAccum = 0;
    setState(() {
      _tab = t;
      // 공놀이를 떠나면 몬스터는 무대 가운데로 돌아온다
      if (t != _Tab.play) {
        _monPos = null;
        _ballPos = null;
        _running = false;
      }
    });
    if (t == _Tab.play) setState(() => _line = '공 던져 줘! 휙 밀어서!');
  }

  void _tapMon() {
    if (_petMode || _throwing) return;
    _hop(1);
    _showEmote(_tierEmote());
    setState(() => _line = _randomLine());
  }

  /// 말 걸기: 서버 모드면 서버 대사(`GET /monsters/{id}/line`), 아니거나 실패하면 앱 대사.
  Future<void> _talk() async {
    var line = await runGameAction(context, (r) => r.talk(m), onError: (_) {});
    if (!mounted) return;
    if (line == null) {
      line = _randomLine();
      if (line == _line) line = _randomLine();
    }
    _showEmote(tierOf(m.affection) == AffectionTier.low ? 'dots' : 'spark');
    setState(() => _line = line!);
  }

  /// 스와이프로 던지기: 손을 뗀 순간의 빠르기(없으면 민 거리)를 방향 · 세기로 써서 떨어질 곳을 정한다.
  /// 위로 밀면 멀리(무대 안쪽), 옆으로 밀면 옆으로. 너무 약하면 던지지 않는다.
  void _swipeThrow(Offset velocity, Offset pushed, Size size) {
    if (_throwing) return;
    final dir = velocity.distance >= 150 ? velocity * 0.35 : pushed * 2.2;
    if (dir.distance < 40) {
      setState(() => _line = '더 세게 휙 던져 줘!');
      return;
    }
    // 아무리 세게 던져도 무대 높이만큼만 날아간다
    final flight = dir.distance > size.height ? dir / dir.distance * size.height : dir;
    _throwTo(_heldBall(size) + flight, size);
  }

  /// 몬스터가 들고 있는 공의 위치 (무대 안 px).
  Offset _heldBall(Size size) {
    final feet = _monPos ?? _homeFeet(size);
    return feet + const Offset(_playMonSize * 0.3, -_playMonSize * 0.35);
  }

  /// 공을 [p] 근처의 땅으로 던진다 → 공이 날아가고 → 몬스터가 뛰어가 잡는다.
  /// 오늘 처음 잡으면 놀아주기 보상(하루 1회 ♥+1)을 받고, 그 뒤로는 서버를 부르지 않고 놀기만 한다.
  void _throwTo(Offset p, Size size) {
    if (_throwing) return;
    final x = p.dx.clamp(_playMonSize / 2, size.width - _playMonSize / 2);
    final y = p.dy.clamp(size.height * _groundTop + _playMonSize * 0.4, size.height - 14);
    final target = Offset(x, y);
    final from = _monPos ?? _homeFeet(size);
    setState(() {
      _throwing = true;
      _ballPos = target;
      _faceRight = x > from.dx;
      _line = '…!';
    });
    _later(_ballFlight.inMilliseconds, () => setState(() {
          _running = true;
          _monPos = target;
        }));
    _later(_ballFlight.inMilliseconds + _monRun.inMilliseconds, _caught);
  }

  Future<void> _caught() async {
    const lines = ['잡았다!', '또 던져 줘!', '헤헤, 내가 빨랐지?'];
    setState(() {
      _running = false;
      _ballPos = null;
      _throws++;
      _line = lines[(_throws - 1) % lines.length];
    });
    _hop(1);
    _showEmote('note');
    if (m.playedToday) {
      _throwing = false;
      return;
    }
    final before = tierOf(m.affection);
    final gain = await runGameAction(context, (r) => r.play(m));
    if (!mounted) return;
    _throwing = false;
    if (gain == null) return;
    if (gain > 0) {
      setState(() {});
      _floatText('호감도 +$gain', AppColors.tierHigh);
      _toastTierUp(before);
    }
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

  Future<void> _finishPet(Size stage) async {
    final before = tierOf(m.affection);
    final gain = await runGameAction(context, (r) => r.pet(m));
    if (gain == null || !mounted) return;
    final pops = [for (var i = 0; i < 3; i++) _Pop(stage.width / 2 - 34 + i * 24)];
    setState(() {
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

  Future<void> _feed(ShopItem item) async {
    final s = _s;
    if ((s.inventory[item.id] ?? 0) <= 0) return;
    if (m.level >= Economy.finalEvolutionLevel) {
      _shell.toast('이미 최종형이에요');
      return;
    }
    final before = m.level;
    final ups = await runGameAction(context, (r) => r.feed(m, item));
    if (ups == null || ups < 0 || !mounted) return;
    setState(() => _line = '냠냠! 맛있다!');
    _hop(1);
    _showEmote('heart');
    _floatText('+${item.exp} EXP', AppColors.expBlue);
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

  Future<void> _toBag() async {
    final s = _s;
    if (s.fieldMonsters.length <= 1) {
      _shell.toast('필드에 1마리는 남겨둬요');
      return;
    }
    final ok = await runGameAction(context, (r) => r.moveMonster(m, toField: false));
    if (ok != true || !mounted) return;
    _shell.toast('가방에 넣었어요');
    widget.onClose();
  }

  Future<void> _makePartner() async {
    final ok = await runGameAction(context, (r) async {
      await r.setPartner(m);
      return true;
    });
    if (ok != true || !mounted) return;
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
          color: AppColors.night,
          border: Border(top: BorderSide(color: AppColors.ink, width: 4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(cat),
            Flexible(
              child: SingleChildScrollView(
                physics: _petMode ? const NeverScrollableScrollPhysics() : null,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _stage(),
                    const SizedBox(height: 12),
                    switch (_tab) {
                      _Tab.feed => _feedPanel(s),
                      _Tab.play => _playPanel(),
                      _Tab.pet => _petPanel(),
                    },
                    const SizedBox(height: 12),
                    _actions(),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: PixelButton(
                            radius: 0,
                            label: '가방에 넣기',
                            onPressed: _toBag,
                            height: 46,
                            depth: 4,
                            fontSize: 13,
                            color: AppColors.nightRaised,
                            shadowColor: AppColors.ink,
                            textColor: AppColors.text,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PixelButton(
                            radius: 0,
                            label: s.chatPartnerUid == m.uid ? '대화 상대 ✓' : '대화 상대로',
                            onPressed: _makePartner,
                            height: 46,
                            depth: 4,
                            color: AppColors.purple,
                            shadowColor: AppColors.purpleDeep,
                            // Galmuri에 ✓ 글자가 없어서 픽셀 아이콘으로 그린다.
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(s.chatPartnerUid == m.uid ? '대화 상대' : '대화 상대로',
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.white)),
                                if (s.chatPartnerUid == m.uid) ...[
                                  const SizedBox(width: 5),
                                  const PixelIcon(
                                    layers: [PixelLayer(PixelIcons.checkStroke, AppColors.white)],
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

  /// 이름 · Lv · 카테고리 · 닫기, 아래 줄에 EXP 막대 (진화까지 남은 레벨은 보여 주지 않는다 — 기획).
  Widget _header(HabitCategory cat) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: const BoxDecoration(
        color: AppColors.nightPanel,
        border: Border(bottom: BorderSide(color: AppColors.ink, width: 3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(sp.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
                    ),
                    const SizedBox(width: 8),
                    _chip('Lv.${m.level}', AppColors.purpleDeep, AppColors.goldLight),
                    const SizedBox(width: 6),
                    _chip(cat.type, cat.color, AppColors.brownText,
                        icon: PixelIcon(layers: PixelIcons.category[cat.id]!, size: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              BrownCloseButton(onTap: widget.onClose, color: AppColors.red),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip('EXP', AppColors.expBlue, AppColors.ink),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.nightDeep,
                    border: Border.all(color: AppColors.ink, width: 2),
                  ),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (m.exp / Economy.expPerLevel).clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: const ColoredBox(color: AppColors.expBlue),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${formatNum(m.exp)}/${Economy.expPerLevel}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg, {Widget? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: bg, border: Border.all(color: AppColors.ink, width: 2)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon, const SizedBox(width: 4)],
          Text(text,
              style: TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }

  /// 공놀이를 안 할 때 몬스터 발의 위치: 무대 가운데 아래.
  /// 몬스터가 서 있는 자리(발 위치): 무대 한가운데 (11-02, 사용자 "중간에 위치하게" — 전엔 바닥에 붙어 있었다).
  Offset _homeFeet(Size size) {
    final mon = _tab == _Tab.play ? _playMonSize : _monSize;
    return Offset(size.width / 2, (size.height + mon) / 2);
  }

  Widget _stage() {
    final play = _tab == _Tab.play;
    final height = play ? _playStageHeight : _stageHeight;
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth - 6, height - 6); // 테두리 안쪽
      final monSize = play ? _playMonSize : _monSize;
      final feet = _monPos ?? _homeFeet(size);
      final monBob = _squish ? 0.0 : (widget.bobUp ? -4.0 : 0.0);
      // 배경은 홈 필드 그림을 무대 너비에 맞추고, 나무 조금 위부터 보이게 (위아래 위치만 계산)
      final imgH = box.maxWidth / AppAssets.homeFieldW * AppAssets.homeFieldH;
      final top = imgH * (AppAssets.homeFieldGrassTop - 0.1);
      final alignY = imgH > size.height ? (2 * top / (imgH - size.height) - 1).clamp(-1.0, 1.0) : 0.0;
      // 그림의 기본 방향과 반대로 뛰어가면 뒤집는다
      final flip = (_monPos != null) && (_faceRight == sp.facesLeft);

      final body = Transform.translate(
        offset: Offset(0, _jump),
        child: Semantics(
          button: true,
          label: '${sp.name} 톡 건드리기',
          child: GestureDetector(
            onTap: _petMode || play ? null : _tapMon,
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
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(flip ? -1 : 1, 1, 1),
                      child: PixelImage(sp.assetAt(m.level),
                          width: monSize, height: monSize, alignment: Alignment.bottomCenter),
                    ),
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
      );
      // 간식: 물약을 몬스터 위로 끌어다 놓으면 먹는다
      final monster = DragTarget<ShopItem>(
        onAcceptWithDetails: (d) => _feed(d.data),
        builder: (context, candidates, _) => AnimatedScale(
          scale: candidates.isNotEmpty ? 1.08 : 1,
          duration: const Duration(milliseconds: 120),
          alignment: Alignment.bottomCenter,
          child: body,
        ),
      );
      final ballSize = play ? 26.0 : 0.0;
      final ball = _ballPos ?? feet + Offset(monSize * 0.3, -monSize * 0.35);

      Widget stage = AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: height,
        decoration: BoxDecoration(
          color: AppColors.sky,
          border: Border.all(color: _petMode ? AppColors.gold : AppColors.ink, width: 3),
        ),
        child: ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: PixelImage(AppAssets.homeField, fit: BoxFit.fitWidth, alignment: Alignment(0, alignY)),
              ),
              // 몬스터 그림자
              AnimatedPositioned(
                duration: _running ? _monRun : Duration.zero,
                curve: Curves.easeOutCubic,
                left: feet.dx - monSize * 0.4,
                top: feet.dy - 7,
                child: Container(
                  width: monSize * 0.8,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.ink.withValues(alpha: _jump != 0 ? 0.12 : 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (_dragging)
                Positioned(
                  left: feet.dx - 70,
                  top: feet.dy - monSize - 26,
                  width: 140,
                  child: IgnorePointer(child: Center(child: _stageTag('여기로 끌어다 놓아요'))),
                ),
              // 몬스터
              AnimatedPositioned(
                duration: _running ? _monRun : Duration.zero,
                curve: Curves.easeOutCubic,
                left: feet.dx - monSize / 2,
                top: feet.dy - monSize,
                child: monster,
              ),
              if (play)
                AnimatedPositioned(
                  duration: _ballPos != null ? _ballFlight : Duration.zero,
                  curve: Curves.easeOut,
                  left: ball.dx - ballSize / 2,
                  top: ball.dy - ballSize,
                  child: IgnorePointer(
                    child: PixelIcon(
                        layers: PixelIcons.toyBall, size: ballSize, outline: 1.5, outlineColor: AppColors.ink),
                  ),
                ),
              if (play && _aim != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _AimPainter(from: _heldBall(size), to: _aim!)),
                  ),
                ),
              // 호감도
              Positioned(left: 8, top: 8, child: IgnorePointer(child: _hearts())),
              // 대사 말풍선
              Positioned(
                left: 10,
                right: 10,
                top: 44,
                child: IgnorePointer(
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.cream,
                          border: Border.all(color: AppColors.ink, width: 3),
                        ),
                        child: Text(_line,
                            style: const TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.brownText)),
                      ),
                      const Positioned(bottom: -6, child: BubbleTail(color: AppColors.cream)),
                    ],
                  ),
                ),
              ),
              for (final p in _pops)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 800),
                  left: p.x,
                  top: p.up ? feet.dy - monSize - 30 : feet.dy - monSize + 30,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 800),
                    opacity: p.up ? 0 : 1,
                    child: const PixelIcon(
                      layers: [PixelLayer(PixelIcons.heart, AppColors.tierHigh)],
                      size: 20,
                      outline: 1.5,
                      outlineColor: AppColors.ink,
                    ),
                  ),
                ),
              for (final f in _floats)
                AnimatedPositioned(
                  duration: const Duration(seconds: 1),
                  left: size.width * f.x / 100,
                  top: f.up ? feet.dy - monSize - 20 : feet.dy - monSize + 30,
                  child: AnimatedOpacity(
                    duration: const Duration(seconds: 1),
                    opacity: f.up ? 0 : 1,
                    child: Text(f.text,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: f.color,
                          shadows: outlineShadows(AppColors.ink),
                        )),
                  ),
                ),
              if (_petMode)
                Positioned(
                  left: _hand.dx - 20,
                  top: _hand.dy - 22,
                  child: IgnorePointer(
                    child: Transform.rotate(
                      angle: (widget.bobUp ? -12 : 8) * pi / 180,
                      child:
                          const PixelIcon(layers: PixelIcons.hand, size: 40, outline: 2, outlineColor: AppColors.ink),
                    ),
                  ),
                ),
              if (!play)
                Positioned(
                  right: 8,
                  bottom: 34,
                  child: Column(
                    children: [
                      _stageButton('쓰다듬기', PixelIcons.actionPet, _tab == _Tab.pet, m.pettedToday,
                          () => _select(_tab == _Tab.pet ? _Tab.feed : _Tab.pet)),
                      const SizedBox(height: 8),
                      _stageButton('말 걸기', PixelIcons.actionTalk, false, false, _talk),
                    ],
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    color: AppColors.ink.withValues(alpha: 0.72),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    alignment: Alignment.center,
                    child: Text(_stageHint(),
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.text)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      Offset inner(Offset local) => local - const Offset(3, 3);
      if (play) {
        // 무대 위에서는 손가락을 대는 즉시 공 던지기가 이긴다 (창 스크롤에 빼앗기지 않게)
        return Semantics(
          label: '무대를 밀어 공 던지기',
          container: true,
          child: RawGestureDetector(
            key: const ValueKey('play_stage'),
            behavior: HitTestBehavior.opaque,
            gestures: {
              _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
                _EagerPan.new,
                (r) {
                  r.onStart = (d) {
                    _aimStart = inner(d.localPosition);
                    setState(() => _aim = _aimStart);
                  };
                  r.onUpdate = (d) {
                    setState(() => _aim = inner(d.localPosition));
                  };
                  r.onEnd = (d) {
                    final pushed = (_aim ?? Offset.zero) - (_aimStart ?? Offset.zero);
                    setState(() => _aim = null);
                    _swipeThrow(d.velocity.pixelsPerSecond, pushed, size);
                  };
                  r.onCancel = () {
                    setState(() => _aim = null);
                  };
                },
              ),
            },
            child: stage,
          ),
        );
      }
      if (!_petMode) return stage;
      // 쓰다듬기 중: 마우스를 올려 움직이거나, 손가락으로 문지른다.
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

  String _stageHint() => switch (_tab) {
        _Tab.feed => _dragging ? '몬스터 위에 놓으면 먹어요' : '아래 물약을 몬스터에게 끌어다 주세요',
        _Tab.play => _throwing ? '공을 쫓아가는 중…' : (_aim != null ? '놓으면 휙!' : '무대를 휙 밀어서 공을 던져요'),
        _Tab.pet => m.pettedToday ? '오늘은 이미 쓰다듬었어요' : '몬스터를 문질러 쓰다듬어 주세요',
      };

  Widget _stageTag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.gold, border: Border.all(color: AppColors.ink, width: 2)),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brownText)),
      );

  /// 호감도 하트 5개(반 칸 단위) + 사이 이름.
  Widget _hearts() {
    final t = tierOf(m.affection);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(color: AppColors.night, border: Border.all(color: AppColors.ink, width: 2)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < Economy.maxAffection ~/ 2; i++) ...[
            if (i > 0) const SizedBox(width: 1),
            PixelIcon(
              layers: [
                PixelLayer(
                  PixelIcons.heart,
                  m.affection >= (i + 1) * 2
                      ? AppColors.tierHigh
                      : (m.affection == i * 2 + 1 ? AppColors.heartHalf : AppColors.nightLine2),
                ),
              ],
              size: 14,
            ),
          ],
          const SizedBox(width: 6),
          Text('${tierName(t)} 사이',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text)),
        ],
      ),
    );
  }

  /// 아래 칸들의 공통 틀 (제목 + 설명 + 내용).
  Widget _panel(String title, String hint, Widget child) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: AppColors.nightRaised,
        border: Border.fromBorderSide(BorderSide(color: AppColors.ink, width: 3)),
        boxShadow: [BoxShadow(color: AppColors.ink, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.goldLight)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(hint,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
            ],
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }

  Widget _feedPanel(GameState s) {
    final short = Catalog.items.any((it) => (s.inventory[it.id] ?? 0) <= 0);
    return _panel(
      '간식 주기',
      '물약을 몬스터에게 끌어다 주세요',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < Catalog.items.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _feedTile(s, Catalog.items[i])),
              ],
            ],
          ),
          if (short)
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpenShop,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 28),
                  alignment: Alignment.centerRight,
                  child: const Text('간식이 부족해요? 상점 가기 ▶',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.gold)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _feedTile(GameState s, ShopItem it) {
    final n = s.inventory[it.id] ?? 0;
    Widget tile({bool lifted = false}) => Container(
          height: 56,
          decoration: BoxDecoration(
            color: n > 0 ? AppColors.introFloor : AppColors.nightPanel,
            border: Border.all(color: lifted ? AppColors.gold : AppColors.ink, width: 3),
          ),
          child: Stack(
            children: [
              // 간식 칸을 낮게 (88 → 56, 11-02 "간식 창이 너무 커서 부담"): 물약 왼쪽, 이름 · EXP 오른쪽
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 4),
                child: Row(
                  children: [
                    Opacity(opacity: n > 0 ? 1 : 0.35, child: PixelImage(it.asset, height: 26)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.short,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: n > 0 ? AppColors.text : AppColors.textMuted)),
                          const SizedBox(height: 1),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('+${it.exp} EXP',
                                style: TextStyle(
                                    fontSize: 10.5, color: n > 0 ? AppColors.expBlue : AppColors.textMuted)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  color: AppColors.ink,
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  child: Text('×$n',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.goldLight)),
                ),
              ),
            ],
          ),
        );
    // 누르기만 하면 끄는 법을 알려 준다. 화면 읽기(접근성)로는 바로 먹일 수 있게 둔다.
    final tile0 = Semantics(
      button: true,
      label: '${it.name} 먹이기',
      excludeSemantics: true,
      onTap: n > 0 ? () => _feed(it) : null,
      child: GestureDetector(
        key: ValueKey('feed_${it.id}'),
        onTap: n > 0 ? () => setState(() => _line = '그거 나 주는 거야? 이쪽으로 끌어 줘!') : null,
        child: tile(),
      ),
    );
    if (n <= 0) return tile0;
    // 바로 끌기 (Draggable은 손가락을 대는 즉시 시작해서 창 스크롤보다 먼저 잡는다)
    return Draggable<ShopItem>(
      data: it,
      onDragStarted: () => setState(() => _dragging = true),
      onDragEnd: (_) => setState(() => _dragging = false),
      feedback: Transform.rotate(angle: -0.2, child: PixelImage(it.asset, height: 48)),
      childWhenDragging: Opacity(opacity: 0.5, child: tile(lifted: true)),
      child: tile0,
    );
  }

  Widget _playPanel() {
    return _panel(
      '놀아주기',
      m.playedToday ? '오늘 보상은 받았어요 · 계속 놀 수 있어요' : '처음 잡으면 호감도 +${Economy.playAffectionGain}',
      Row(
        children: [
          const PixelIcon(layers: PixelIcons.toyBall, size: 30, outline: 1.5, outlineColor: AppColors.ink),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: m.playedToday ? AppColors.green : AppColors.goldLight,
              border: Border.all(color: AppColors.ink, width: 2),
            ),
            child: Text(m.playedToday ? '오늘 ♥+${Economy.playAffectionGain} 받음' : '하루 1번 ♥+${Economy.playAffectionGain}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ),
          const Spacer(),
          Text('던진 횟수 $_throws', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _petPanel() {
    return _panel(
      '쓰다듬기',
      m.pettedToday ? '오늘 완료 · 내일 또!' : '하루 1번 · 호감도 +${Economy.petAffectionGain}',
      Row(
        children: [
          Text(m.pettedToday ? '100%' : '${_rubProg.round()}%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(color: AppColors.nightDeep, border: Border.all(color: AppColors.ink, width: 2)),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: m.pettedToday ? 1 : _rubProg / 100,
                heightFactor: 1,
                child: const ColoredBox(color: AppColors.tierHigh),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 무대 오른쪽 아래의 작은 버튼 (쓰다듬기 · 말 걸기).
  Widget _stageButton(String label, List<PixelLayer> icon, bool on, bool done, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 58,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: on ? AppColors.gold : AppColors.night.withValues(alpha: 0.85),
                border: Border.all(color: AppColors.ink, width: 2),
              ),
              child: Column(
                children: [
                  PixelIcon(layers: icon, size: 24, outline: 1.5, outlineColor: AppColors.ink),
                  const SizedBox(height: 2),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: on ? AppColors.brownText : AppColors.text)),
                ],
              ),
            ),
            if (done) Positioned(right: -6, top: -6, child: _doneMark()),
          ],
        ),
      ),
    );
  }

  Widget _doneMark() => IgnorePointer(
        child: Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.green, border: Border.all(color: AppColors.ink, width: 2)),
          child: const PixelIcon(layers: [PixelLayer(PixelIcons.checkStroke, AppColors.ink)], size: 9, strokeWidth: 3.5),
        ),
      );

  /// 아래 행동 줄: 간식 · 놀아주기 (작은 버튼 두 개).
  Widget _actions() {
    final items = [
      ('간식', PixelImage(Catalog.items.first.asset, height: 20) as Widget, false, _Tab.feed),
      (
        '놀아주기',
        const PixelIcon(layers: PixelIcons.toyBall, size: 20, outline: 1.5, outlineColor: AppColors.ink),
        m.playedToday,
        _Tab.play,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Builder(builder: (_) {
              final (label, icon, done, tab) = items[i];
              final on = _tab == tab;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  PressCard(
                    radius: 0,
                    onTap: () => _select(tab),
                    sunk: on,
                    sinkBy: 3,
                    depth: 3,
                    color: on ? AppColors.gold : AppColors.introFloor,
                    shadowColor: AppColors.ink,
                    borderColor: AppColors.ink,
                    minHeight: 44,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 22, height: 22, child: Center(child: icon)),
                        const SizedBox(width: 6),
                        Text(label,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: on ? AppColors.brownText : AppColors.text)),
                      ],
                    ),
                  ),
                  if (done) Positioned(right: -6, top: -6, child: _doneMark()),
                ],
              );
            }),
          ),
        ],
      ],
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
            border: Border.all(color: AppColors.ink, width: 3),
          ),
          child: PixelIcon(layers: [PixelIcons.emotes[kind]!], size: 18),
        ),
        const Positioned(left: 10, bottom: -5, child: BubbleTail(color: AppColors.cream, width: 8)),
      ],
    );
  }
}

/// 손가락을 대자마자 이기는 끌기 인식기 — 놀아주기 무대에서 창 스크롤보다 먼저 공 던지기를 잡는다.
class _EagerPan extends PanGestureRecognizer {
  _EagerPan() : super(supportedDevices: null);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// 스와이프 중 공에서 손가락까지 점선 조준선.
class _AimPainter extends CustomPainter {
  _AimPainter({required this.from, required this.to});
  final Offset from;
  final Offset to;

  @override
  void paint(Canvas canvas, Size size) {
    final d = to - from;
    final len = d.distance;
    if (len < 4) return;
    final unit = d / len;
    final paint = Paint()
      ..color = AppColors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square;
    for (double t = 0; t < len; t += 14) {
      canvas.drawLine(from + unit * t, from + unit * min(t + 7, len), paint);
    }
    canvas.drawCircle(to, 7, Paint()..color = AppColors.gold);
  }

  @override
  bool shouldRepaint(_AimPainter old) => old.from != from || old.to != to;
}
