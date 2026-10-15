import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/audio/bgm.dart';
import '../../core/constants/app_assets.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/catalog.dart';
import '../home/home_parts.dart' show DashedBorderPainter;
import '../home/purchase_popups.dart' show QuantityPopup;
import '../shell/main_shell.dart';
import 'chat_controller.dart';
import 'explore_view.dart';

/// 챗봇 탭: 대화 상대 고르기 + 습관 체크 대화 + 탐색.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.active = true, this.controllerBuilder});

  /// 챗봇 탭이 보이는 중인지 (탐색 화면 애니메이션 타이머용).
  final bool active;

  /// 테스트나 AI 챗봇 연결 때 다른 [ChatController]를 넣을 수 있다.
  final ChatController Function(GameState state)? controllerBuilder;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  ChatController? _c;
  String? _partnerUid;

  /// 습관 목록이 바뀌었는지 보는 표시 (홈에서 습관을 추가 · 그만두면 묻던 질문을 처음부터 다시).
  String? _habitSig;
  static String _sigOf(GameState s) => s.habits.map((h) => h.id).join(',');
  final _scroll = ScrollController();
  final _amount = TextEditingController();
  int _lastCount = 0;
  ChatStep? _lastStep;

  /// 탐색 화면이라 탐색 곡을 틀었는지.
  bool _exploreMusic = false;
  bool _bobUp = false;
  Timer? _ticker;

  /// 성실볼 사기 팝업 (탐색을 다 썼는데 볼이 없을 때).
  bool _buyingBall = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final s = GameScope.read(context);
    _c = (widget.controllerBuilder ?? (st) => ChatController(state: st))(s)..addListener(_onChange);
    _partnerUid = s.chatPartnerUid;
    _habitSig = _sigOf(s);
    _c!.start();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ChatScreen old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _syncTicker();
  }

  void _syncTicker() {
    _ticker?.cancel();
    if (!widget.active) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _bobUp = !_bobUp);
    });
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    final n = _c!.messages.length;
    final step = _c!.step;
    // 새 메시지가 오거나 탐색에서 돌아오면 맨 아래로.
    if (n != _lastCount || step != _lastStep) {
      _lastCount = n;
      _lastStep = step;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 거꾸로 쌓는 목록이라 0이 맨 아래(최신 메시지)
        if (_scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _c?.removeListener(_onChange);
    _c?.dispose();
    _scroll.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _pickPartner(GameState s, String uid) {
    if (uid == s.chatPartnerUid) return;
    s.chatPartnerUid = uid;
    s.touch(); // 아래 build에서 대화 상대 변경을 보고 대화를 다시 시작한다.
  }

  Future<void> _sendAmount() async {
    final ok = await _c!.sendAmount(_amount.text);
    if (!mounted) return;
    if (!ok) {
      MainShell.of(context).toast('숫자를 입력해 주세요');
      return;
    }
    _amount.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final c = _c!;
    // 탐색 중엔 탐색 곡, 돌아오면 챗봇 곡 (그리기가 끝난 뒤 셸에 알린다)
    final exploring = c.step == ChatStep.explore;
    if (exploring != _exploreMusic) {
      _exploreMusic = exploring;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) MainShell.maybeOf(context)?.setMusicOverride(MainShell.chatTab, exploring ? BgmTrack.explore : null);
      });
    }
    // 홈 교감 창에서 "대화 상대로"를 눌렀거나 여기서 바꿨으면 대화를 새로 시작.
    if (s.chatPartnerUid != _partnerUid) {
      _partnerUid = s.chatPartnerUid;
      WidgetsBinding.instance.addPostFrameCallback((_) => c.start());
    }
    // 질문하던 중에 습관 목록이 바뀌면 순서가 어긋나므로 처음부터 다시 묻는다.
    final sig = _sigOf(s);
    if (sig != _habitSig) {
      _habitSig = sig;
      if (c.step == ChatStep.yesNo || c.step == ChatStep.amount) {
        WidgetsBinding.instance.addPostFrameCallback((_) => c.start());
      }
    }
    return Stack(
      children: [
        Column(
          children: [
            _partnerBar(s, c),
            Expanded(
              child: c.step == ChatStep.explore
                  ? ExploreView(controller: c, bobUp: _bobUp, onNeedBall: _openBallShop)
                  : Column(
                      children: [
                        Expanded(child: _messages(c)),
                        _dock(s, c),
                      ],
                    ),
            ),
          ],
        ),
        if (_buyingBall)
          Positioned.fill(
            child: QuantityPopup(
              item: Catalog.seongsilBall,
              onCancel: () => setState(() => _buyingBall = false),
              onBuy: (n) => _buyBalls(s, n),
            ),
          ),
      ],
    );
  }

  void _openBallShop() => setState(() => _buyingBall = true);

  /// 그 자리에서 성실볼을 산다. 산 볼은 바로 성실볼 버튼으로 쓸 수 있다.
  void _buyBalls(GameState s, int n) {
    if (!s.buy(Catalog.seongsilBall, count: n)) return;
    setState(() => _buyingBall = false);
    MainShell.of(context).toast('성실볼 $n개를 샀어요 · 던질 수 있어요!');
  }

  Widget _partnerBar(GameState s, ChatController c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.nightPanel,
        border: Border(bottom: BorderSide(color: AppColors.nightLine, width: 3)),
      ),
      child: Row(
        children: [
          const Text('대화 상대', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // 방금 잡은 몬스터는 결과 팝업을 닫은 뒤에 보인다.
                  for (final m in s.monsters.where((m) => m.uid != c.hiddenMonsterUid)) ...[
                    Semantics(
                      button: true,
                      selected: m.uid == s.chatPartnerUid,
                      label: '${withWa(Catalog.speciesById(m.speciesId).name)} 대화',
                      child: GestureDetector(
                        onTap: () => _pickPartner(s, m.uid),
                        child: Container(
                          width: 46,
                          height: 46,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: m.uid == s.chatPartnerUid ? AppColors.purpleDeep : AppColors.nightDeep,
                            border: Border.all(
                                color: m.uid == s.chatPartnerUid ? AppColors.gold : AppColors.nightLine, width: 3),
                          ),
                          child: PixelImage(Catalog.speciesById(m.speciesId).asset),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messages(ChatController c) {
    final p = c.partner;
    final avatar = p == null ? AppAssets.seongsilBall : Catalog.speciesById(p.speciesId).asset;
    // reverse: 최신 메시지가 항상 아래에 붙어 있다 (메시지 높이가 달라도 스크롤 위치를 계산할 필요 없음).
    return ListView(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      children: [
        if (c.busy) ...[
          _Bubble(message: const ChatMessage.bot('…'), avatar: avatar),
          const SizedBox(height: 10),
        ],
        for (final m in c.messages.reversed) ...[
          const SizedBox(height: 10),
          _Bubble(message: m, avatar: avatar),
        ],
      ],
    );
  }

  Widget _dock(GameState s, ChatController c) {
    final Widget content;
    switch (c.step) {
      case ChatStep.idle:
        content = _GoldButton(label: '오늘 습관 체크 시작', onTap: c.start);
      case ChatStep.yesNo:
        content = Row(
          children: [
            Expanded(child: _DarkButton(label: '못 했어', onTap: () => c.answer(false))),
            const SizedBox(width: 9),
            Expanded(child: _GoldButton(label: '했어!', onTap: () => c.answer(true))),
          ],
        );
      case ChatStep.amount:
        final unit = c.currentMeasure?.unit ?? '';
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.night,
                      border: Border.all(color: AppColors.nightLine2, width: 3),
                    ),
                    padding: const EdgeInsets.all(11),
                    child: Semantics(
                      label: '수행량',
                      child: TextField(
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        cursorColor: AppColors.gold,
                        style: const TextStyle(fontSize: 17, color: AppColors.gold),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: '숫자만',
                          hintStyle: TextStyle(color: AppColors.textMuted),
                        ),
                        onSubmitted: (_) => _sendAmount(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 24),
                  child: Text(unit, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ),
                const SizedBox(width: 8),
                _GoldButton(label: '전송', onTap: _sendAmount, expand: false, shadow: false),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final q in c.quickAmounts)
                  GestureDetector(
                    onTap: () => c.sendValue(q),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.chatChip,
                        border: Border.all(color: AppColors.nightLine, width: 3),
                      ),
                      child: Text('${formatNum(q)}$unit',
                          style: const TextStyle(fontSize: 11, color: AppColors.chatSoftText)),
                    ),
                  ),
              ],
            ),
          ],
        );
      case ChatStep.done:
      case ChatStep.explore:
        final noEnc = s.encountersLeft <= 0;
        content = Row(
          children: [
            // 확정한 기록 고치기 (보상은 첫 확정 그대로)
            if (s.checkedInToday) ...[
              Expanded(flex: 2, child: _DarkButton(label: '다시 체크', onTap: c.recheck)),
              const SizedBox(width: 9),
            ],
            Expanded(
              flex: 3,
              child: Semantics(
                button: true,
                enabled: !noEnc,
                child: GestureDetector(
                  onTap: noEnc ? null : c.explore,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 46),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: noEnc ? AppColors.nightRaised : AppColors.purpleDeep,
                      border: Border.all(color: noEnc ? AppColors.nightLine2 : AppColors.purple, width: 3),
                      boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(4, 4))],
                    ),
                    child: Text('탐색하기 (${s.encountersLeft}회 남음)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: noEnc ? AppColors.lavender : AppColors.text,
                        )),
                  ),
                ),
              ),
            ),
          ],
        );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppColors.nightDeep,
        border: Border(top: BorderSide(color: AppColors.nightLine, width: 3)),
      ),
      child: AbsorbPointer(absorbing: c.busy, child: content),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.avatar});
  final ChatMessage message;
  final String avatar;

  @override
  Widget build(BuildContext context) {
    final bot = message.fromBot;
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bot ? AppColors.nightRaised : AppColors.chatMeBubble,
        border: Border.all(color: bot ? AppColors.purple : AppColors.gold, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message.text, style: const TextStyle(fontSize: 12.5, height: 1.9, color: AppColors.text)),
          if (message.reward != null) ...[
            const SizedBox(height: 7),
            Container(
              color: AppColors.gold,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Text(message.reward!, style: const TextStyle(fontSize: 11, color: AppColors.night)),
            ),
          ],
          if (message.levelUp != null) ...[
            const SizedBox(height: 7),
            CustomPaint(
              foregroundPainter: const DashedBorderPainter(color: AppColors.purple, dash: 5, gap: 3),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Text(message.levelUp!, style: const TextStyle(fontSize: 11, color: AppColors.purpleSoft)),
              ),
            ),
          ],
        ],
      ),
    );
    return LayoutBuilder(builder: (context, box) {
      final maxW = box.maxWidth * 0.76;
      return Row(
        mainAxisAlignment: bot ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bot) ...[
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppColors.purpleDeep,
                border: Border.all(color: AppColors.purple, width: 3),
              ),
              child: PixelImage(avatar),
            ),
            const SizedBox(width: 8),
          ],
          ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: bubble),
        ],
      );
    });
  }
}

/// 금색 버튼 (밝은 테두리 + 오른쪽 아래 그림자).
class _GoldButton extends StatelessWidget {
  const _GoldButton({required this.label, required this.onTap, this.expand = true, this.shadow = true});
  final String label;
  final VoidCallback onTap;
  final bool expand;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: expand ? double.infinity : null,
          constraints: const BoxConstraints(minHeight: 46),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: expand ? 12 : 15, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.gold,
            border: Border.all(color: AppColors.goldLight, width: 3),
            boxShadow: shadow ? const [BoxShadow(color: AppColors.ink, offset: Offset(4, 4))] : null,
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.night)),
        ),
      ),
    );
  }
}

/// 어두운 보조 버튼 ("못 했어").
class _DarkButton extends StatelessWidget {
  const _DarkButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 46),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.nightRaised,
            border: Border.all(color: AppColors.nightLine2, width: 3),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.chatSoftText)),
        ),
      ),
    );
  }
}
