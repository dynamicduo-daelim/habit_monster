import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../core/widgets/popup_card.dart';
import '../../data/models.dart';
import '../../data/results.dart';
import '../home/home_parts.dart' show CheckerPainter, CoinIcon;
import 'chat_controller.dart';
import '../../core/theme/app_theme.dart';

enum _Phase { searching, appear, throwing, popup, done }

/// 성실볼 연출 단계: 제자리 · 끄는 중 · 날아감 · 빗나감 · 빨려 들기 · 떨어짐 · 흔들흔들 · 터짐(잡힘 별 / 놓침 깨짐).
enum _Fx { idle, drag, fly, miss, absorb, drop, wobble, burst }

/// 탐색 화면: 먼저 "찾는 중…"(덤불이 흔들림, [searchDuration]) → "새로운 루틴몬이 등장했어요!" / "발견하지 못했어요" 알림 →
/// 몬스터가 나타나면 아래의 성실볼을 **위로 휙 밀어 던진다** (11-02, 기획 `2026-11-02-성실볼-직접-던지기.md`).
/// 민 방향 · 세기대로 날아가 몬스터에 맞으면 빨려 들기 → 흔들흔들 → 별(잡힘) / 깨짐(놓침) → 팝업. 이때 볼 1개를 쓴다.
/// 빗나가면 볼을 쓰지 않고 제자리로 돌아온다. 잡을 확률은 지금처럼 서버(저장소)가 정한다. 아무도 없으면 덤불만 흔들린다.
class ExploreView extends StatefulWidget {
  const ExploreView({super.key, required this.controller, required this.bobUp, required this.onNeedBall});
  final ChatController controller;
  final bool bobUp;

  /// 성실볼이 없을 때 사러 가기.
  final VoidCallback onNeedBall;

  @override
  State<ExploreView> createState() => _ExploreViewState();

  /// 탐색하는 과정의 길이 (사용자 요청 10-29 — "갑자기 팍 나오지 않게").
  static const Duration searchDuration = Duration(milliseconds: 2000);
}

class _ExploreViewState extends State<ExploreView> with SingleTickerProviderStateMixin {
  static const double _ballSize = 44;
  static const double _landSize = 56;
  static const double _monH = 150;

  /// 이보다 느리게 밀면 던지지 않고 볼이 제자리로 (실수로 톡 친 것 거르기, 기획 [가정]).
  static const double _minFling = 300;

  /// 맞음 판정: 몬스터 그림 상자의 이 배수 (기획 [가정] — 너무 어렵지 않게).
  static const double _hitScale = 1.2;

  /// 밀기 빠르기(px/s) × 이 값 = 날아가는 거리.
  static const double _flingReach = 0.18;
  static const _flyTime = Duration(milliseconds: 500);
  static const _missTime = Duration(milliseconds: 600);
  static const _absorbTime = Duration(milliseconds: 450);
  static const _dropTime = Duration(milliseconds: 350);
  static const _swingTime = Duration(milliseconds: 200);
  static const _burstTime = Duration(milliseconds: 600);

  static const _bush = [
    PixelLayer('M1 16V8h2V4h2v4h2V2h2v6h2V3h2v5h2V5h2v5h2v6z', AppColors.bushDark),
    PixelLayer('M3 16v-6h2v6z M9 16V9h2v7z M15 16v-5h2v5z', AppColors.grassLine),
  ];

  _Phase _phase = _Phase.done;
  int _wobble = 0;

  _Fx _fx = _Fx.idle;
  late final AnimationController _anim = AnimationController(vsync: this);

  /// 연출 세대: 새로 탐색하면 올라가서, 하던 연출이 멈춘다.
  int _gen = 0;

  /// 끄는 중인 볼의 중심 (필드 좌표).
  Offset? _ballAt;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;

  /// 방금 빗나갔다 (대사용).
  bool _missed = false;

  /// 마지막으로 그린 필드 크기 — 볼 자리 · 맞음 판정 계산용.
  Size _field = Size.zero;

  /// 찾는 중 덤불 흔들기 · 점(…) 세기.
  Timer? _searchTimer;
  int _searchTick = 0;

  /// 결과 알림 ("새로운 루틴몬이 등장했어요!" 등). 잠깐 보였다 사라진다.
  String? _banner;
  Timer? _bannerTimer;
  EncounterResult? _shownFor;

  ChatController get _c => widget.controller;
  EncounterResult get _e => _c.encounter ?? const EncounterResult();

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant ExploreView old) {
    super.didUpdateWidget(old);
    if (!identical(_c.encounter, _shownFor)) _reset();
  }

  /// 새로 탐색하면: 먼저 찾는 중 → 몬스터가 있으면 등장, 없으면 끝. 되살린 등장은 바로 보여 준다.
  void _reset() {
    _gen++;
    _anim.stop();
    _fx = _Fx.idle;
    _ballAt = null;
    _missed = false;
    _searchTimer?.cancel();
    _shownFor = _c.encounter;
    if (_c.justExplored && _c.encounter != null) {
      _c.justExplored = false;
      _phase = _Phase.searching;
      _searchTick = 0;
      _searchTimer = Timer.periodic(const Duration(milliseconds: 250), (t) {
        if (!mounted) return;
        setState(() => _searchTick++);
        if (_searchTick * 250 >= ExploreView.searchDuration.inMilliseconds) {
          t.cancel();
          setState(_reveal);
        }
      });
      return;
    }
    _phase = _e.catchable ? _Phase.appear : _Phase.done; // 가진 종은 볼 없이 골드만 받고 끝
  }

  /// 찾기가 끝났다: 결과에 맞는 알림을 잠깐 띄운다.
  void _reveal() {
    _phase = _e.catchable ? _Phase.appear : _Phase.done;
    final sp = _e.species;
    _banner = sp == null
        ? '발견하지 못했어요…'
        : _e.alreadyOwned
            ? '친구 ${sp.name}${josaIGa(sp.name)} 놀러 왔어요!'
            : (_e.newlySeen ? '새로운 루틴몬이 등장했어요!' : '야생의 루틴몬이 등장했어요!');
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  // ---------- 성실볼 던지기 ----------
  double get _ground => _field.height * 0.16;

  /// 던지기 전 볼이 놓인 자리 (발판 아래 가운데).
  Offset get _ballRest => Offset(_field.width / 2, _field.height - _ground * 0.5);

  /// 맞은 볼이 떨어져 흔들리는 자리 (발판 위).
  Offset get _ballLand => Offset(_field.width / 2, _field.height - _ground - 14 - _landSize / 2);

  /// 몬스터 그림 상자 (그림 높이 [_monH], 발판 위 18).
  Rect get _monRect => Rect.fromLTWH(_field.width / 2 - _monH / 2, _field.height - _ground - 18 - _monH, _monH, _monH);
  Rect get _hitRect => Rect.fromCenter(center: _monRect.center, width: _monH * _hitScale, height: _monH * _hitScale);

  bool _canThrowNow(GameState s) => _phase == _Phase.appear && _c.canThrow && s.balls > 0 && _fx == _Fx.idle;

  /// 연출 한 단계를 [d] 동안 재생. 중간에 멈췄거나(새 탐색) 화면이 사라졌으면 false.
  Future<bool> _run(Duration d) async {
    final g = _gen;
    _anim.duration = d;
    try {
      await _anim.forward(from: 0).orCancel;
    } on TickerCanceled {
      return false;
    }
    return mounted && g == _gen;
  }

  void _dragStart(DragStartDetails d) {
    if (!_canThrowNow(GameScope.read(context))) return;
    setState(() {
      _fx = _Fx.drag;
      _ballAt = _ballRest;
    });
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_fx != _Fx.drag) return;
    setState(() => _ballAt = _ballAt! + d.delta);
  }

  /// 손을 뗐다: 위로 충분히 빠르게 밀었으면 그 방향 · 세기대로 날아간다. 아니면 제자리.
  void _dragEnd(DragEndDetails d) {
    if (_fx != _Fx.drag) return;
    final v = d.velocity.pixelsPerSecond;
    final from = _ballAt ?? _ballRest;
    if (v.distance < _minFling || v.dy > -_minFling / 2) {
      setState(() {
        _fx = _Fx.idle;
        _ballAt = null;
      });
      return;
    }
    final reach = (v.distance * _flingReach).clamp(120.0, _field.height * 1.1);
    _fly(from, from + v / v.distance * reach);
  }

  /// 화면 읽기(접근성)로 "던지기": 몬스터에게 곧장 던진다.
  void _quickThrow() {
    if (_canThrowNow(GameScope.read(context))) _fly(_ballRest, _monRect.center);
  }

  Future<void> _fly(Offset from, Offset to) async {
    setState(() {
      _fx = _Fx.fly;
      _from = from;
      _to = to;
      _ballAt = null;
      _missed = false;
    });
    if (!await _run(_flyTime)) return;
    if (_hitRect.contains(to)) return _hit();
    // 빗나감: 볼은 쓰지 않고 떨어졌다가 제자리로
    setState(() {
      _fx = _Fx.miss;
      _missed = true;
    });
    if (!await _run(_missTime)) return;
    setState(() => _fx = _Fx.idle);
  }

  /// 맞았다: 빨려 들기와 함께 저장소(서버)에 던지기를 보내고(볼 1개 소모, 결과는 저장소가 정함) → 떨어짐 → 흔들흔들 → 터짐 → 팝업.
  Future<void> _hit() async {
    final g = _gen;
    setState(() {
      _fx = _Fx.absorb;
      _phase = _Phase.throwing;
    });
    final done = await Future.wait<Object?>([_c.throwBall(), _run(_absorbTime)]);
    if (!mounted || g != _gen) return;
    final r = done[0] as CatchResult?;
    if (r == null) {
      // 오류(볼이 없거나 서버 문제): 몬스터는 그대로, 다시 던질 수 있게
      setState(() {
        _fx = _Fx.idle;
        _phase = _Phase.appear;
      });
      return;
    }
    setState(() => _fx = _Fx.drop);
    if (!await _run(_dropTime)) return;
    setState(() {
      _fx = _Fx.wobble;
      _wobble = 0;
    });
    // 잡히면 세 번(좌우 6번) 흔들리고, 놓치면 한 번 반 만에 튀어나온다 (연출만)
    for (var k = 0; k < (r.caught ? 6 : 3); k++) {
      if (!await _run(_swingTime)) return;
      setState(() => _wobble++);
    }
    setState(() => _fx = _Fx.burst);
    if (!await _run(_burstTime)) return;
    setState(() {
      _fx = _Fx.idle;
      _phase = _Phase.popup;
    });
  }

  void _closePopup() {
    setState(() => _phase = _Phase.done);
    _c.confirmCatch();
  }

  @override
  void dispose() {
    _anim.dispose();
    _searchTimer?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  String _line(GameState s) {
    final sp = _e.species;
    final r = _c.lastCatch;
    switch (_phase) {
      case _Phase.searching:
        return '풀숲을 살펴보는 중${'.' * (_searchTick % 3 + 1)}\n어떤 루틴몬이 숨어 있을까?';
      case _Phase.appear:
        final rate = ((_e.captureRate ?? s.captureRateOf(sp!)) * 100).round();
        if (_fx == _Fx.fly) return '성실볼을 던졌다! 과연…';
        if (_missed) return '앗, 빗나갔다! 볼은 그대로야. 몬스터를 향해 다시 휙!\n잡힐 확률 $rate%';
        if (s.balls <= 0) return '야생의 ${sp!.name}${josaIGa(sp.name)} 나타났다! 성실볼이 없네…\n잡힐 확률 $rate%';
        return '야생의 ${sp!.name}${josaIGa(sp.name)} 나타났다! 아래 성실볼을 위로 휙 밀어 던져 봐!\n잡힐 확률 $rate%';
      case _Phase.throwing:
        return '성실볼을 던졌다! 과연…';
      case _Phase.popup:
      case _Phase.done:
        if (r == null) {
          if (sp != null && _e.alreadyOwned) {
            return '이미 친구인 ${sp.name}${josaIGa(sp.name)} 놀러 왔어요! 볼 없이 ${_e.gold}G를 받았어요.';
          }
          return _e.emptyPool
              ? '이번엔 아무도 없었어요… 오늘 체크인한 길에서 만날 수 있는 몬스터가 없나 봐요.'
              : '이번엔 아무도 없었어요… 덤불만 흔들렸네요. 다시 탐색해 볼까요?';
        }
        final n = r.species.name;
        switch (r.kind) {
          case CatchKind.escaped:
            return '$n${josaIGa(n)} 도망갔어요… 다시 탐색해 볼까요?';
          case CatchKind.newMonster:
            return '새로운 몬스터 $n(${r.species.rarity})${josaEulReul(n)} 잡았어요! '
                '${r.toField ? '필드에 나왔어요.' : '필드가 꽉 차서 가방에 넣었어요.'}';
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final r = _c.lastCatch;
    final sp = _e.species;
    final noEnc = s.encountersLeft <= 0;
    final bob = widget.bobUp ? -4.0 : 0.0;
    final caught = r?.caught ?? false;
    // 등장 · 팝업 중엔 몬스터가 보이고, 던지는 중엔 볼 안에 있다. 끝나면 잡은 몬스터만 남는다.
    final escaped = r != null && !r.caught;
    final showMonster = sp != null &&
        (_phase == _Phase.appear ||
            _phase == _Phase.popup ||
            (_phase == _Phase.done && (caught || _e.alreadyOwned)) ||
            // 던지는 중: 빨려 들어가는 동안, 놓쳤으면 튀어나올 때
            (_phase == _Phase.throwing && (_fx == _Fx.absorb || (_fx == _Fx.burst && escaped))));

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                _field = Size(box.maxWidth, box.maxHeight);
                final ground = _ground;
                return ClipRect(
                  child: Stack(
                    children: [
                      const Positioned.fill(child: ColoredBox(color: AppColors.grass)),
                      const Positioned.fill(
                        child: PixelImage(AppAssets.homeField, fit: BoxFit.cover, alignment: Alignment(0, 0.2)),
                      ),
                      Positioned(left: 10, top: 10, child: _pips(s)),
                      if (_phase == _Phase.done && r?.kind == CatchKind.newMonster)
                        Positioned(right: 10, top: 10, child: _newBadge('NEW!')),
                      // 처음 만난 종: 잡기 전이어도 도감에 올라간다 (API 명세 v5 newlySeen)
                      if (_phase == _Phase.appear && _e.newlySeen)
                        Positioned(right: 10, top: 10, child: _newBadge('도감 등록!')),
                      if (_phase == _Phase.done && _e.alreadyOwned)
                        Positioned(right: 10, top: 10, child: _goldBadge(_e.gold)),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: ground,
                        child: const Center(child: CustomPaint(size: Size(180, 40), painter: _PlatformPainter())),
                      ),
                      if (showMonster)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: ground + 18,
                          child: Transform.translate(
                            offset: Offset(0, bob),
                            child: _monsterFx(escaped, Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_phase != _Phase.throwing)
                                  Container(
                                    width: 28,
                                    height: 34,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.cream,
                                      border: Border.all(color: AppColors.ink, width: 3),
                                    ),
                                    child: const Text('!',
                                        style:
                                            TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.red)),
                                  ),
                                const SizedBox(height: 6),
                                Semantics(
                                  key: const ValueKey('explore_monster'),
                                  label: sp.name,
                                  image: true,
                                  child: PixelImage(sp.asset, height: _monH),
                                ),
                              ],
                            )),
                          ),
                        )
                      else if (_phase != _Phase.throwing)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: ground + 14,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Transform.translate(
                                offset: Offset(_shake(-1), 0),
                                child: const PixelIcon(layers: _bush, size: 70, height: 56, viewBox: 20),
                              ),
                              const SizedBox(width: 4),
                              Transform.translate(
                                offset: Offset(_shake(1), 0),
                                child: const PixelIcon(layers: _bush, size: 70, height: 56, viewBox: 20),
                              ),
                            ],
                          ),
                        ),
                      if (_phase == _Phase.searching)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 52,
                          child: Center(child: _searchBadge()),
                        ),
                      if (_banner != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 52,
                          child: Center(child: _resultBanner(_banner!)),
                        ),
                      // 번쩍 · 빛 조각 · 별
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _FxPainter(
                              anim: _anim,
                              fx: _fx,
                              mon: _monRect,
                              to: _to,
                              land: _ballLand,
                              caught: caught,
                            ),
                          ),
                        ),
                      ),
                      ..._ballLayer(s, escaped),
                    ],
                  ),
                );
              }),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppColors.nightDeep,
                border: Border(top: BorderSide(color: AppColors.nightLine, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 64),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.cream,
                          border: Border.all(color: AppColors.ink, width: 4),
                          boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(4, 4))],
                        ),
                        child: Text(_line(s),
                            style: const TextStyle(fontSize: 12.5, height: 1.8, color: AppColors.brownText)),
                      ),
                      Positioned(
                        right: 14,
                        bottom: 8,
                        child: Opacity(
                          opacity: widget.bobUp ? 0 : 1,
                          child: const Text('▼', style: TextStyle(fontSize: 11, color: AppColors.red)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AbsorbPointer(
                    absorbing: _phase == _Phase.searching ||
                        _phase == _Phase.throwing ||
                        _phase == _Phase.popup ||
                        _fx != _Fx.idle,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: PixelButton(
                            label: '그만',
                            onPressed: _c.leaveExplore,
                            color: AppColors.parchment,
                            shadowColor: AppColors.parchmentShadow,
                            textColor: AppColors.brownText,
                            fontSize: 12,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                        if (_phase == _Phase.appear) ...[
                          const SizedBox(width: 8),
                          Expanded(child: _throwHint(s)),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          child: PixelButton(
                            label: noEnc ? '오늘 탐색 끝!' : '다시 탐색 (${s.encountersLeft}회)',
                            onPressed: noEnc ? null : _c.explore,
                            textColor: AppColors.brownText,
                            fontSize: 12.5,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_phase == _Phase.popup && r != null)
          Positioned.fill(child: _CatchPopup(result: r, bobUp: widget.bobUp, onClose: _closePopup)),
      ],
    );
  }

  /// 덤불 흔들림: 찾는 중엔 빠르고 크게, 평소엔 천천히.
  double _shake(int dir) =>
      _phase == _Phase.searching ? dir * (_searchTick.isEven ? 6.0 : -6.0) : dir * (widget.bobUp ? -3.0 : 3.0);

  Widget _searchBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.nightDeep.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.nightLine2, width: 2),
        ),
        child: Text('탐색 중${'.' * (_searchTick % 3 + 1)}',
            style: const TextStyle(
                fontFamily: AppTheme.pixelFont, fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
      );

  Widget _resultBanner(String text) {
    final found = !text.startsWith('발견');
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, k, child) => Transform.scale(scale: k, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: found ? AppColors.yellowButton : AppColors.nightDeep,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.ink, width: 2),
          boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(0, 3))],
        ),
        child: Text(text,
            style: TextStyle(
                fontFamily: AppTheme.pixelFont,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: found ? AppColors.brownText : AppColors.text)),
      ),
    );
  }

  /// 아래 줄 가운데: 볼이 있으면 던지는 법 안내(누르는 버튼 아님), 없으면 "볼 사기".
  Widget _throwHint(GameState s) {
    if (s.balls <= 0) {
      return PixelButton(
        label: '볼 사기',
        onPressed: widget.onNeedBall,
        color: AppColors.ballOfferBg,
        shadowColor: AppColors.purple,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        textColor: AppColors.brownText,
        fontSize: 12.5,
      );
    }
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.nightPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.nightLine2, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('▲', style: TextStyle(fontSize: 11, color: AppColors.goldLight)),
          const SizedBox(width: 5),
          Flexible(
            child: Text('위로 휙! ×${s.balls}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.goldLight)),
          ),
        ],
      ),
    );
  }

  /// 몬스터 연출: 빨려 들 때 하얗게 작아지며 볼로, 놓쳤을 때 볼에서 튀어나온다.
  Widget _monsterFx(bool escaped, Widget child) {
    if (_phase != _Phase.throwing) return child;
    return AnimatedBuilder(
      animation: _anim,
      child: child,
      builder: (context, child) {
        final t = _anim.value;
        if (_fx == _Fx.absorb) {
          final k = Curves.easeIn.transform(t);
          return Transform.translate(
            offset: (_to - _monRect.center) * k,
            child: Transform.scale(
              scale: 1 - k,
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(AppColors.white.withValues(alpha: math.min(1, t * 2)), BlendMode.srcATop),
                child: child,
              ),
            ),
          );
        }
        // 튀어나오기: 볼 자리에서 커지며 제자리로
        final k = Curves.easeOutBack.transform(t);
        return Transform.translate(
          offset: (_ballLand - _monRect.center) * (1 - k),
          child: Transform.scale(scale: k.clamp(0.0, 1.2), child: child),
        );
      },
    );
  }

  /// 성실볼 (제자리 · 끄는 중 · 날아감 · 빗나감 · 떨어짐 · 흔들림 · 터짐).
  List<Widget> _ballLayer(GameState s, bool escaped) {
    final idle = _fx == _Fx.idle || _fx == _Fx.drag;
    if (idle) {
      if (!_canThrowNow(s) && _fx != _Fx.drag) return const [];
      final c = _ballAt ?? _ballRest + Offset(0, widget.bobUp ? -3 : 0);
      const hit = 76.0; // 손가락이 닿는 칸 (볼보다 넓게)
      return [
        Positioned(
          key: const ValueKey('throw_ball'),
          left: c.dx - hit / 2,
          top: c.dy - hit / 2,
          width: hit,
          height: hit,
          child: Semantics(
            button: true,
            label: '성실볼 던지기',
            excludeSemantics: true,
            onTap: _quickThrow,
            // 손가락을 대는 즉시 볼을 잡는다 (보통 끌기는 36px 움직여야 시작돼서 짧게 휙 밀면 놓친다 — 교감 창 공과 같은 방식)
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
                  _EagerPan.new,
                  (g) => g
                    ..onStart = _dragStart
                    ..onUpdate = _dragUpdate
                    ..onEnd = _dragEnd,
                ),
              },
              child: Center(
                child: Transform.scale(
                  scale: _fx == _Fx.drag ? 1.12 : 1,
                  child: const PixelImage(AppAssets.seongsilBall, width: _ballSize, height: _ballSize),
                ),
              ),
            ),
          ),
        ),
        if (_fx == _Fx.idle)
          Positioned(
            left: c.dx + 24,
            top: c.dy - 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                color: AppColors.ink,
                child: Text('×${s.balls}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.goldLight)),
              ),
            ),
          ),
      ];
    }
    if (_phase == _Phase.popup || _phase == _Phase.done) return const [];
    return [
      AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final t = _anim.value;
          var c = _to;
          var size = _ballSize;
          var angle = 0.0;
          var opacity = 1.0;
          var align = Alignment.center;
          switch (_fx) {
            case _Fx.fly:
              // 포물선: 직선 위로 솟았다 내려오고, 멀어지며 작아지고, 돈다
              final k = Curves.easeOut.transform(t);
              final arc = math.min(80.0, (_to - _from).distance * 0.3);
              c = Offset.lerp(_from, _to, k)! + Offset(0, -math.sin(math.pi * t) * arc);
              size = _ballSize * (1 - 0.25 * t);
              angle = t * 4 * math.pi;
            case _Fx.miss:
              c = _to + Offset(0, 260 * t * t);
              size = _ballSize * 0.75;
              angle = 4 * math.pi + t * 3 * math.pi;
              opacity = 1 - t;
            case _Fx.absorb:
              size = _ballSize * (0.75 + 0.15 * math.sin(math.pi * t));
            case _Fx.drop:
              c = Offset.lerp(_to, _ballLand, Curves.bounceOut.transform(t))!;
              size = _ballSize * 0.9 + (_landSize - _ballSize * 0.9) * t;
            case _Fx.wobble:
              c = _ballLand;
              size = _landSize;
              align = Alignment.bottomCenter;
              angle = (_wobble.isEven ? -1 : 1) * math.sin(math.pi * t) * 22 * math.pi / 180;
            case _Fx.burst:
              c = _ballLand;
              size = _landSize * (1 + 0.12 * math.sin(math.pi * t));
              if (escaped) return _brokenBall(t);
            case _Fx.idle:
            case _Fx.drag:
              break;
          }
          return Positioned(
            left: c.dx - size / 2,
            top: c.dy - size / 2,
            child: IgnorePointer(
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: angle,
                  alignment: align,
                  child: PixelImage(AppAssets.seongsilBall, width: size, height: size),
                ),
              ),
            ),
          );
        },
      ),
    ];
  }

  /// 놓침: 볼이 위아래 반쪽으로 갈라져 날아간다.
  Widget _brokenBall(double t) {
    Widget half(bool top) {
      final dir = top ? -1.0 : 1.0;
      return Positioned(
        left: _ballLand.dx - _landSize / 2 + dir * 34 * t,
        top: _ballLand.dy - _landSize / 2 + (top ? -30 * t : 10 * t),
        child: Opacity(
          opacity: (1 - t).clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: dir * t * 0.9,
            child: ClipRect(
              child: Align(
                alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
                heightFactor: 0.5,
                child: const PixelImage(AppAssets.seongsilBall, width: _landSize, height: _landSize),
              ),
            ),
          ),
        ),
      );
    }

    return Positioned.fill(
        child: IgnorePointer(child: Stack(clipBehavior: Clip.none, children: [half(true), half(false)])));
  }

  Widget _newBadge(String text) => Transform.rotate(
        angle: -4 * math.pi / 180,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: AppColors.red, border: Border.all(color: AppColors.ink, width: 3)),
          child: Text(text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.white,
                shadows: [Shadow(color: AppColors.redShadow, offset: Offset(1, 1))],
              )),
        ),
      );

  Widget _goldBadge(int gold) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: AppColors.yellowButton, border: Border.all(color: AppColors.ink, width: 3)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CoinIcon(size: 13),
            const SizedBox(width: 4),
            Text('+${gold}G',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brownText)),
          ],
        ),
      );

  Widget _pips(GameState s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cream,
        border: Border.all(color: AppColors.ink, width: 3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('탐색', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brownText)),
          for (var i = 0; i < Economy.encountersPerDay; i++) ...[
            const SizedBox(width: 6),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: i < s.encountersLeft ? AppColors.green : AppColors.goalTagBorder,
                border: Border.all(color: AppColors.ink, width: 2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "잡았다!" / "놓쳤다…" 팝업.
class _CatchPopup extends StatelessWidget {
  const _CatchPopup({required this.result, required this.bobUp, required this.onClose});
  final CatchResult result;
  final bool bobUp;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final MonsterSpecies sp = r.species;
    final caught = r.caught;
    final String message;
    switch (r.kind) {
      case CatchKind.newMonster:
        message = '새 친구가 됐어요! ${r.toField ? '필드에 나왔어요.' : '필드가 꽉 차서 가방에 넣었어요.'}';
      case CatchKind.escaped:
        message = '${sp.name}${josaIGa(sp.name)} 성실볼에서 빠져나와 도망갔어요…\n성실함이 쌓일수록 더 잘 잡혀요.';
    }
    return PopupCard(
      title: caught ? '잡았다!' : '놓쳤다…',
      ribbonColor: caught ? AppColors.green : AppColors.redSoft,
      ribbonText: caught ? AppColors.brownText : AppColors.white,
      maxWidth: 280,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(border: Border.all(color: AppColors.ink, width: 3)),
          child: CustomPaint(
            painter: const CheckerPainter(AppColors.grassCardDark, AppColors.grassCard),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.translate(
                  offset: Offset(0, caught && bobUp ? -4 : 0),
                  child: Opacity(opacity: caught ? 1 : 0.45, child: PixelImage(sp.asset, height: 68)),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Opacity(
                    opacity: caught ? 1 : 0.5,
                    child: const PixelImage(AppAssets.seongsilBall, height: 22),
                  ),
                ),
              ],
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${sp.name} ',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.brownText)),
            Text(sp.rarity, style: const TextStyle(fontSize: 11, color: AppColors.brownMuted)),
            if (r.kind == CatchKind.newMonster) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: AppColors.red, border: Border.all(color: AppColors.ink, width: 2)),
                child: const Text('NEW',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.white)),
              ),
            ],
          ],
        ),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, height: 1.7, color: AppColors.brownMuted)),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: PixelButton(label: '확인', onPressed: onClose, height: 44, depth: 4, fontSize: 12),
        ),
      ],
    );
  }
}

/// 타원 풀숲 발판 (아래쪽 안쪽 그늘 + 테두리).
class _PlatformPainter extends CustomPainter {
  const _PlatformPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Offset.zero & size;
    canvas.save();
    canvas.clipPath(Path()..addOval(oval));
    canvas.drawRect(oval, Paint()..color = AppColors.platformInset);
    canvas.drawOval(oval.shift(const Offset(0, -6)), Paint()..color = AppColors.grassLine);
    canvas.restore();
    canvas.drawOval(
      oval.deflate(1.5),
      Paint()
        ..color = AppColors.bushDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 던지기 이펙트: 맞는 순간 번쩍 + 빛 조각이 볼로 빨려 들기, 잡히면 별이 터지고, 놓치면 하얀 번쩍.
class _FxPainter extends CustomPainter {
  _FxPainter({
    required this.anim,
    required this.fx,
    required this.mon,
    required this.to,
    required this.land,
    required this.caught,
  }) : super(repaint: anim);
  final Animation<double> anim;
  final _Fx fx;
  final Rect mon;
  final Offset to;
  final Offset land;
  final bool caught;

  static const _sparks = 10;

  void _square(Canvas canvas, Offset c, double size, Color color) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(math.pi / 4);
    canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: size, height: size), Paint()..color = color);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    switch (fx) {
      case _Fx.absorb:
        canvas.drawCircle(mon.center, 30 + 110 * t, Paint()..color = AppColors.white.withValues(alpha: (1 - t) * 0.7));
        final k = Curves.easeIn.transform(t);
        for (var i = 0; i < _sparks; i++) {
          final a = i * 2 * math.pi / _sparks;
          final start = mon.center + Offset(math.cos(a), math.sin(a)) * 70;
          _square(canvas, Offset.lerp(start, to, k)!, 7 * (1 - k) + 2, i.isEven ? AppColors.white : AppColors.goldLight);
        }
      case _Fx.burst:
        canvas.drawCircle(land, 20 + 80 * t, Paint()..color = AppColors.white.withValues(alpha: (1 - t) * 0.6));
        if (caught) {
          for (var i = 0; i < _sparks; i++) {
            final a = i * 2 * math.pi / _sparks - math.pi / 2;
            final p = land + Offset(math.cos(a), math.sin(a)) * (24 + 70 * Curves.easeOut.transform(t));
            _square(canvas, p, 10 * (1 - t) + 3, i.isEven ? AppColors.gold : AppColors.white);
          }
        }
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _FxPainter old) =>
      old.fx != fx || old.mon != mon || old.to != to || old.land != land || old.caught != caught;
}

/// 손가락을 대자마자 이기는 끌기 (성실볼).
class _EagerPan extends PanGestureRecognizer {
  _EagerPan() : super(supportedDevices: null);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}
