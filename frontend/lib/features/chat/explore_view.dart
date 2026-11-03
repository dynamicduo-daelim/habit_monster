import 'dart:async';
import 'dart:math' as math;

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

/// 탐색 화면: 먼저 "찾는 중…"(덤불이 흔들림, [searchDuration]) → "새로운 루틴몬이 등장했어요!" / "발견하지 못했어요" 알림 →
/// 몬스터가 나타나면 [볼 던지기 · 다시 탐색 · 그만].
/// 던지면 성실볼 1개를 쓰고(흔들흔들) → 잡았다/놓쳤다 팝업. 아무도 없으면 덤불만 흔들린다.
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

class _ExploreViewState extends State<ExploreView> {
  static const _wobbles = 6;
  static const _wobbleMs = 150;

  static const _bush = [
    PixelLayer('M1 16V8h2V4h2v4h2V2h2v6h2V3h2v5h2V5h2v5h2v6z', AppColors.bushDark),
    PixelLayer('M3 16v-6h2v6z M9 16V9h2v7z M15 16v-5h2v5z', AppColors.grassLine),
  ];

  _Phase _phase = _Phase.done;
  int _wobble = 0;
  Timer? _timer;

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
    _timer?.cancel();
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

  /// 볼 던지기: 볼이 없으면 사러 가고, 있으면 1개 쓰고 흔들흔들 → 결과 팝업.
  Future<void> _throw() async {
    final s = GameScope.read(context);
    if (s.balls <= 0) {
      widget.onNeedBall();
      return;
    }
    final r = await _c.throwBall();
    if (r == null || !mounted) return;
    setState(() {
      _phase = _Phase.throwing;
      _wobble = 0;
    });
    _timer = Timer.periodic(const Duration(milliseconds: _wobbleMs), (t) {
      if (!mounted) return;
      setState(() {
        _wobble++;
        if (_wobble >= _wobbles) {
          t.cancel();
          _phase = _Phase.popup;
        }
      });
    });
  }

  void _closePopup() {
    setState(() => _phase = _Phase.done);
    _c.confirmCatch();
  }

  @override
  void dispose() {
    _timer?.cancel();
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
        return '야생의 ${sp!.name}${josaIGa(sp.name)} 나타났다! 성실볼을 던져볼까?\n잡힐 확률 $rate%';
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
    final showMonster =
        sp != null && (_phase == _Phase.appear || _phase == _Phase.popup || (_phase == _Phase.done && (caught || _e.alreadyOwned)));

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                final ground = box.maxHeight * 0.16;
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
                                  label: sp.name,
                                  image: true,
                                  child: PixelImage(sp.asset, height: 150),
                                ),
                              ],
                            ),
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
                      // 흔들리는 성실볼
                      if (_phase == _Phase.throwing)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: ground + 14,
                          child: Center(
                            child: Transform.rotate(
                              angle: (_wobble.isEven ? -20 : 20) * math.pi / 180,
                              alignment: Alignment.bottomCenter,
                              child: const PixelImage(AppAssets.seongsilBall, height: 56),
                            ),
                          ),
                        ),
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
                    absorbing: _phase == _Phase.searching || _phase == _Phase.throwing || _phase == _Phase.popup,
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
                          Expanded(child: _throwButton(s)),
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

  /// 볼 던지기 (볼이 없으면 "볼 사기").
  Widget _throwButton(GameState s) {
    final empty = s.balls <= 0;
    return PixelButton(
      label: empty ? '볼 사기' : '볼 던지기',
      onPressed: _throw,
      color: AppColors.ballOfferBg,
      shadowColor: AppColors.purple,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const PixelImage(AppAssets.seongsilBall, height: 22),
          const SizedBox(width: 5),
          Flexible(
            child: Text(empty ? '볼 사기' : '던지기 ×${s.balls}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brownText)),
          ),
        ],
      ),
    );
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
