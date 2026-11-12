import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/audio/bgm.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/economy.dart';
import '../../core/state/game_repository.dart';
import '../../core/state/game_state.dart';
import '../../core/state/study_timer.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../home/home_parts.dart' show DashedBorderPainter;
import '../home/purchase_popups.dart' show QuantityPopup;
import '../shell/game_action.dart';
import '../shell/main_shell.dart';
import 'chat_controller.dart';
import 'explore_view.dart';
import 'study_timer_view.dart';

/// 챗봇 탭: [챗봇 | 공부 타이머] 칸 전환. 챗봇 = 대화 상대 고르기 + 습관 체크 대화(버튼 또는 말 — AI 해석, D-57) + 탐색.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.active = true, this.keyboardOpen, this.controllerBuilder});

  /// 챗봇 탭이 보이는 중인지 (탐색 화면 애니메이션 타이머용).
  final bool active;

  /// 자판이 올라와 있는지 (셸이 알려 준다. 없으면 이 화면의 MediaQuery로 본다).
  /// 올라와 있으면 [챗봇 | 공부 타이머] 줄을 숨기고 대화 상대 줄을 얇게 해 대화가 보이게 한다 (11-12).
  final bool? keyboardOpen;

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

  /// 말로 답하기 입력칸 (AI 해석).
  final _text = TextEditingController();

  /// 0 = 챗봇, 1 = 공부 타이머.
  int _pane = 0;

  /// 앱 전체 타이머 (없으면 이 화면만의 타이머 — 위젯 테스트).
  late StudyTimer _timer;
  StudyTimer? _ownTimer;
  int _lastCount = 0;
  ChatStep? _lastStep;

  /// 셸에 부탁해 둔 이 탭의 곡 (탐색 곡 · 공부 소리 · null = 기본 챗봇 곡).
  BgmTrack? _music;

  /// 타이머 설정에서 소리를 고르면 2.5초 들려준다.
  BgmTrack? _preview;
  Timer? _previewTimer;
  bool _bobUp = false;
  Timer? _ticker;

  /// 성실볼 사기 팝업 (탐색을 다 썼는데 볼이 없을 때).
  bool _buyingBall = false;

  /// 대화 상대 고르기 창 (채팅방 위 프로필을 누르면, 11-12).
  bool _picking = false;

  /// 메시지마다 처음 화면에 나온 시각 (메신저처럼 말풍선 옆에 시간을 붙인다). 모델은 건드리지 않는다.
  final _times = Expando<DateTime>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final s = GameScope.read(context);
    final repo = GameRepositoryScope.of(context);
    _timer = StudyTimerScope.maybeOf(context) ?? (_ownTimer ??= StudyTimer());
    _c = (widget.controllerBuilder ??
        (st) => ChatController(state: st, repository: repo, timerMinutes: (id) => _timer.todayMinutes(id)))(s)
      ..addListener(_onChange);
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
    _previewTimer?.cancel();
    _c?.removeListener(_onChange);
    _c?.dispose();
    _scroll.dispose();
    _text.dispose();
    _ownTimer?.dispose();
    super.dispose();
  }

  void _pickPartner(GameState s, String uid) {
    if (uid == s.chatPartnerUid) return;
    s.chatPartnerUid = uid;
    s.touch(); // 아래 build에서 대화 상대 변경을 보고 대화를 다시 시작한다.
  }

  /// "얼마나 했어?" 칸: 숫자만이면(`30`, `1.5`) 바로 기록, 글이 섞이면(`30분 뛰었어`) 말로 답하기(AI 해석)로.
  Future<void> _sendText() async {
    final t = _text.text;
    if (t.trim().isEmpty) return;
    _text.clear();
    await _c!.sendText(t);
  }

  /// 위쪽 [챗봇 | 공부 타이머] 전환.
  Widget _paneTabs() {
    Widget tab(int i, String label) => Expanded(
          child: Semantics(
            button: true,
            selected: _pane == i,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _pane = i),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _pane == i ? AppColors.purpleDeep : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: _pane == i ? FontWeight.w700 : FontWeight.w400,
                        color: _pane == i ? AppColors.goldLight : AppColors.textMuted)),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      color: AppColors.nightPanel,
      child: Row(children: [tab(0, '챗봇'), const SizedBox(width: 6), tab(1, '공부 타이머')]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final c = _c!;
    // 탐색 중엔 탐색 곡, 공부 타이머로 집중하는 동안엔 공부 소리, 아니면 챗봇 곡 (그리기가 끝난 뒤 셸에 알린다).
    // 집중 → 쉬는 시간은 시간만 흘러 바뀌므로 0.5초마다 다시 그릴 때([_ticker]) 같이 본다.
    final exploring = c.step == ChatStep.explore;
    final focusing = _timer.running && _timer.phase == StudyPhase.focus;
    final music = _preview ?? (exploring ? BgmTrack.explore : (focusing ? _timer.sound.track : null));
    if (music != _music) {
      _music = music;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) MainShell.maybeOf(context)?.setMusicOverride(MainShell.chatTab, music);
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
    final keyboard = widget.keyboardOpen ?? MediaQuery.viewInsetsOf(context).bottom > 0;
    return Stack(
      children: [
        Column(
          children: [
            if (c.step != ChatStep.explore && !(keyboard && _pane == 0)) _paneTabs(),
            if (_pane == 1 && c.step != ChatStep.explore)
              Expanded(
                child: StudyTimerView(
                  timer: _timer,
                  onSaved: (m) {
                    if (m > 0) MainShell.maybeOf(context)?.toast('공부 $m분을 기록했어요');
                  },
                  onGoChat: () => setState(() => _pane = 0),
                  onPreview: (track) {
                    _previewTimer?.cancel();
                    setState(() => _preview = track);
                    _previewTimer = Timer(const Duration(milliseconds: 2500), () {
                      if (mounted) setState(() => _preview = null);
                    });
                  },
                ),
              )
            else ...[
            _roomHeader(s, c, compact: keyboard),
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
          ],
        ),
        if (_picking)
          Positioned.fill(
            child: _PartnerPicker(
              monsters: [for (final m in s.monsters.where((m) => m.uid != c.hiddenMonsterUid)) m],
              currentUid: s.chatPartnerUid,
              onPick: (uid) {
                setState(() => _picking = false);
                _pickPartner(s, uid);
              },
              onClose: () => setState(() => _picking = false),
            ),
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
  Future<void> _buyBalls(GameState s, int n) async {
    final ok = await runGameAction(context, (r) => r.buy(Catalog.seongsilBall, count: n));
    if (ok != true || !mounted) return;
    setState(() => _buyingBall = false);
    MainShell.of(context).toast('성실볼 $n개를 샀어요 · 던질 수 있어요!');
  }

  /// 채팅방 머리글: 대화 상대 프로필 · 이름. 누르면 옆으로 밀어 고르는 창이 열린다 (메신저형, 11-12).
  /// [compact]: 자판이 올라온 동안 얇게.
  Widget _roomHeader(GameState s, ChatController c, {bool compact = false}) {
    final p = c.partner;
    final sp = p == null ? null : Catalog.speciesById(p.speciesId);
    final box = compact ? 30.0 : 40.0;
    return Semantics(
      button: true,
      label: '대화 상대 바꾸기',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: s.monsters.isEmpty ? null : () => setState(() => _picking = true),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 5 : 8),
          decoration: const BoxDecoration(
            color: AppColors.nightPanel,
            border: Border(bottom: BorderSide(color: AppColors.nightLine, width: 3)),
          ),
          child: Row(
            children: [
              _Avatar(asset: sp == null ? AppAssets.seongsilBall : sp.assetAt(p!.level), size: box),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(sp?.name ?? '대화 상대 없음',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textMuted),
                      ],
                    ),
                    if (!compact && p != null)
                      Text('Lv.${p.level} · 호감도 ${p.affection}/${Economy.maxAffection}',
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                  ],
                ),
              ),
              if (!compact && s.monsters.length > 1)
                const Text('눌러서 바꾸기', style: TextStyle(fontSize: 10, color: AppColors.lavender)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messages(ChatController c) {
    final p = c.partner;
    final sp = p == null ? null : Catalog.speciesById(p.speciesId);
    final avatar = sp == null ? AppAssets.seongsilBall : sp.assetAt(p!.level);
    final name = sp?.name ?? '';
    final msgs = c.messages;
    final now = DateTime.now();
    for (final m in msgs) {
      _times[m] ??= now;
    }
    // 메신저처럼: 같은 쪽이 이어서 말하면 프로필 · 이름은 첫 말풍선에만, 시간은 마지막 말풍선에만.
    final items = <Widget>[
      _DayDivider(date: msgs.isEmpty ? now : _times[msgs.first]!),
      for (var i = 0; i < msgs.length; i++)
        Padding(
          padding: EdgeInsets.only(top: i > 0 && msgs[i - 1].fromBot == msgs[i].fromBot ? 4 : 12),
          child: _Bubble(
            message: msgs[i],
            avatar: avatar,
            name: name,
            showProfile: msgs[i].fromBot && (i == 0 || !msgs[i - 1].fromBot),
            time: i == msgs.length - 1 || msgs[i + 1].fromBot != msgs[i].fromBot ? _times[msgs[i]] : null,
          ),
        ),
      if (c.busy)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _Bubble(
            message: const ChatMessage.bot('…'),
            avatar: avatar,
            name: name,
            showProfile: msgs.isEmpty || !msgs.last.fromBot,
          ),
        ),
    ];
    // reverse: 최신 메시지가 항상 아래에 붙어 있다 (메시지 높이가 달라도 스크롤 위치를 계산할 필요 없음).
    return ListView(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
      children: items.reversed.toList(),
    );
  }

  Widget _dock(GameState s, ChatController c) {
    final Widget content;
    switch (c.step) {
      case ChatStep.idle:
        content = _GoldButton(label: '오늘 습관 체크 시작', onTap: c.start);
      case ChatStep.yesNo:
      case ChatStep.amount:
        // 채팅방처럼 말로만 답한다 (빠른 답장 버튼 없앰, 11-12). 확인 카드는 사이에 끼므로 따로.
        content = _textRow(c);
      case ChatStep.confirm:
        content = _confirmCard(c);
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
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: const BoxDecoration(
        color: AppColors.nightDeep,
        border: Border(top: BorderSide(color: AppColors.nightLine, width: 3)),
      ),
      child: AbsorbPointer(absorbing: c.busy, child: content),
    );
  }

  /// 말로 답하기: "아침에 30분 뛰었어"처럼 쓰면 AI가 알아듣는다 (서버 모드). 시연 모드는 숫자만 읽는다.
  Widget _textRow(ChatController c) {
    final unit = c.step == ChatStep.amount ? c.currentMeasure?.unit ?? '' : '';
    return Row(
      children: [
        Expanded(
          child: _PillField(
            child: Semantics(
              label: '말로 답하기',
              child: TextField(
                controller: _text,
                maxLength: 300,
                cursorColor: AppColors.gold,
                textInputAction: TextInputAction.send,
                style: const TextStyle(fontSize: 14, color: AppColors.text),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  hintText: unit.isEmpty ? '메시지 보내기 (예: 했어 / 못 했어)' : '메시지 보내기 (예: 30$unit 했어)',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
                onSubmitted: (_) => _sendText(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _SendButton(label: '보내기', onTap: _sendText),
      ],
    );
  }

  /// 확인 카드: 말로 답한 기록을 제출 전에 보여 준다 (AI가 잘못 알아들었으면 [고칠래]).
  Widget _confirmCard(ChatController c) {
    final s = GameScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.ink, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('이대로 기록할까?',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.brownText)),
              const SizedBox(height: 8),
              for (final (h, v) in c.draft)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(h.name, style: const TextStyle(fontSize: 13, color: AppColors.brownText)),
                      ),
                      Text(
                          v <= 0
                              ? '못 했어'
                              : (s.measureOf(h).isOX ? '했어' : '${formatNum(v)}${s.measureOf(h).unit}'),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: v <= 0 ? AppColors.brownMuted : AppColors.tierMidText)),
                      if (c.timedMinutes(h) > 0 && v > 0) ...[
                        const SizedBox(width: 6),
                        const Text('타이머', style: TextStyle(fontSize: 11, color: AppColors.purple)),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(child: _DarkButton(label: '고칠래', onTap: c.editDraft)),
            const SizedBox(width: 9),
            Expanded(flex: 2, child: _GoldButton(label: '맞아!', onTap: c.confirmDraft)),
          ],
        ),
      ],
    );
  }
}

/// 메신저형 말풍선. 상대(몬스터)는 왼쪽 — 이어지는 말의 첫 줄에만 프로필 · 이름, 나는 오른쪽.
/// [time]은 이어지는 말의 마지막 말풍선 옆에만 붙는다.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.avatar, required this.name, this.showProfile = true, this.time});
  final ChatMessage message;
  final String avatar;
  final String name;
  final bool showProfile;
  final DateTime? time;

  static const double _avatarSize = 36;

  @override
  Widget build(BuildContext context) {
    final bot = message.fromBot;
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: bot ? AppColors.nightRaised : AppColors.chatMeBubble,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(bot && showProfile ? 4 : 14),
          topRight: Radius.circular(bot ? 14 : 4),
          bottomLeft: const Radius.circular(14),
          bottomRight: const Radius.circular(14),
        ),
        border: Border.all(color: bot ? AppColors.purple : AppColors.gold, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message.text, style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.text)),
          if (message.reward != null) ...[
            const SizedBox(height: 7),
            Container(
              decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(6)),
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
    final timeText =
        time == null ? null : Text(_clock(time!), style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted));
    return LayoutBuilder(builder: (context, box) {
      final maxW = box.maxWidth * 0.68;
      final line = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!bot && timeText != null) ...[timeText, const SizedBox(width: 5)],
          Flexible(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: bubble)),
          if (bot && timeText != null) ...[const SizedBox(width: 5), timeText],
        ],
      );
      if (!bot) return Align(alignment: Alignment.centerRight, child: line);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showProfile) _Avatar(asset: avatar, size: _avatarSize) else const SizedBox(width: _avatarSize),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showProfile && name.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 4),
                    child: Text(name, style: const TextStyle(fontSize: 11, color: AppColors.chatSoftText)),
                  ),
                line,
              ],
            ),
          ),
        ],
      );
    });
  }

  /// 메신저식 시각: 오전 9:05 / 오후 2:13.
  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${t.hour < 12 ? '오전' : '오후'} $h:${t.minute.toString().padLeft(2, '0')}';
  }
}

/// 둥근 네모 프로필 (채팅방 머리글 · 말풍선).
class _Avatar extends StatelessWidget {
  const _Avatar({required this.asset, required this.size});
  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.1),
      decoration: BoxDecoration(
        color: AppColors.purpleDeep,
        borderRadius: BorderRadius.circular(size * 0.34),
        border: Border.all(color: AppColors.purple, width: 2),
      ),
      child: PixelImage(asset),
    );
  }
}

/// 메시지 맨 위 날짜 줄.
class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.date});
  final DateTime date;

  static const _weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.nightRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.nightLine2, width: 1.5),
        ),
        child: Text('${date.year}년 ${date.month}월 ${date.day}일 ${_weekdays[date.weekday - 1]}',
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
      ),
    );
  }
}

/// 알약 모양 입력칸 틀.
class _PillField extends StatelessWidget {
  const _PillField({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.night,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.nightLine2, width: 2),
      ),
      child: child,
    );
  }
}

/// 입력칸 옆 보내기 버튼.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.goldLight, width: 2),
          ),
          child: Text(label,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.night)),
        ),
      ),
    );
  }
}

/// 대화 상대 고르기: 아래에서 올라오는 창. 양옆으로 밀어 고르고 버튼으로 바꾼다 (11-12).
class _PartnerPicker extends StatefulWidget {
  const _PartnerPicker({required this.monsters, required this.currentUid, required this.onPick, required this.onClose});
  final List<OwnedMonster> monsters;
  final String? currentUid;
  final ValueChanged<String> onPick;
  final VoidCallback onClose;

  @override
  State<_PartnerPicker> createState() => _PartnerPickerState();
}

class _PartnerPickerState extends State<_PartnerPicker> {
  late int _index = math.max(0, widget.monsters.indexWhere((m) => m.uid == widget.currentUid));
  late final _page = PageController(viewportFraction: 0.44, initialPage: _index);

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ms = widget.monsters;
    final sel = ms[_index.clamp(0, ms.length - 1)];
    final selName = Catalog.speciesById(sel.speciesId).name;
    final isCurrent = sel.uid == widget.currentUid;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(onTap: widget.onClose, child: const ColoredBox(color: AppColors.scrim)),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
            decoration: const BoxDecoration(
              color: AppColors.nightPanel,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(top: BorderSide(color: AppColors.purple, width: 3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, color: AppColors.sheetHandle),
                const SizedBox(height: 10),
                const Text('누구랑 이야기할까?',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                const SizedBox(height: 2),
                const Text('← 옆으로 밀어서 고르기 →', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 190,
                  child: PageView.builder(
                    controller: _page,
                    itemCount: ms.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => AnimatedBuilder(
                      animation: _page,
                      builder: (context, child) {
                        final page =
                            _page.hasClients && _page.position.haveDimensions ? _page.page! : _index.toDouble();
                        final t = (1 - (page - i).abs()).clamp(0.0, 1.0);
                        return Transform.scale(
                            scale: 0.84 + 0.16 * t, child: Opacity(opacity: 0.45 + 0.55 * t, child: child));
                      },
                      child: _card(ms[i], i),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < ms.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        width: i == _index ? 14 : 6,
                        height: 6,
                        color: i == _index ? AppColors.gold : AppColors.nightLine2,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _GoldButton(
                    label: isCurrent ? '지금 ${withWa(selName)} 이야기 중' : '${withWa(selName)} 대화하기',
                    onTap: () => isCurrent ? widget.onClose() : widget.onPick(sel.uid),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(OwnedMonster m, int i) {
    final sp = Catalog.speciesById(m.speciesId);
    final on = m.uid == widget.currentUid;
    return Semantics(
      button: true,
      selected: on,
      label: '${withWa(sp.name)} 대화',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _page.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppColors.nightRaised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? AppColors.gold : AppColors.purple, width: 2),
          ),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.purpleDeep, borderRadius: BorderRadius.circular(10)),
                  child: PixelImage(sp.assetAt(m.level)),
                ),
              ),
              const SizedBox(height: 7),
              Text(sp.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 2),
              Text('Lv.${m.level} · ♥ ${m.affection}', style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 금색 버튼 (밝은 테두리 + 오른쪽 아래 그림자).
class _GoldButton extends StatelessWidget {
  const _GoldButton({required this.label, required this.onTap});
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.gold,
            border: Border.all(color: AppColors.goldLight, width: 3),
            boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(4, 4))],
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
