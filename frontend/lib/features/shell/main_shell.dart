import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/bgm.dart';
import '../../core/auth/auth_service.dart';
import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/help_button.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../core/widgets/popup_card.dart';
import '../../data/catalog.dart';
import '../../data/pixel_icons.dart';
import '../auth/auth_gate.dart';
import '../chat/chat_screen.dart';
import '../dex/dex_screen.dart';
import '../goals/goals_screen.dart';
import '../home/home_screen.dart';
import '../stats/stats_screen.dart';
import '../tutorial/tutorial_overlay.dart';
import 'game_action.dart';

/// 상단 바(날짜 · 탐색 · 골드 · 성실볼) + 본문 + 하단 탭 5개.
///
/// 하위 화면에서 `MainShell.of(context)`로 탭 이동([MainShellState.goTab])과
/// 토스트([MainShellState.toast])를 쓸 수 있다.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.showTutorial = false});

  /// 온보딩을 막 끝내고 처음 들어왔으면 튜토리얼부터 보여준다.
  final bool showTutorial;

  static const int homeTab = 0;
  static const int chatTab = 1;
  static const int goalsTab = 2;
  static const int dexTab = 3;
  static const int statsTab = 4;

  static MainShellState of(BuildContext context) => context.findAncestorStateOfType<MainShellState>()!;

  /// 셸 밖(단독 테스트 등)에서도 안전하게.
  static MainShellState? maybeOf(BuildContext context) => context.findAncestorStateOfType<MainShellState>();

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _tab = 0;
  String? _toastText;
  bool _toastCoin = false;
  Timer? _toastTimer;

  static const _tabs = ['홈', '챗봇', '목표', '도감', '통계'];

  /// 탭 순서 → `PixelIcons.nav`(시안 순서: 홈 · 챗봇 · 통계 · 도감 · 목표)의 아이콘 번호.
  static const _tabIcons = [0, 1, 4, 3, 2];

  /// 탭 안에서 잠깐 바꾸는 곡 (홈의 상점 → 상점 곡, 챗봇의 탐색 → 탐색 곡).
  final Map<int, BgmTrack> _musicOverrides = {};

  void goTab(int i) {
    setState(() => _tab = i);
    _syncMusic();
  }

  /// [tab] 안의 화면이 곡을 바꾸거나(track) 되돌린다(null). 그 탭이 보일 때만 들린다.
  void setMusicOverride(int tab, BgmTrack? track) {
    if (_musicOverrides[tab] == track) return;
    if (track == null) {
      _musicOverrides.remove(tab);
    } else {
      _musicOverrides[tab] = track;
    }
    _syncMusic();
  }

  /// 챗봇 탭은 챗봇 곡, 나머지 탭은 홈 필드 곡.
  void _syncMusic() {
    if (!mounted) return;
    final base = _tab == MainShell.chatTab ? BgmTrack.chat : BgmTrack.home;
    BgmScope.read(context).play(_musicOverrides[_tab] ?? base);
  }

  // ---------- 튜토리얼 ----------
  late bool _tutorial = widget.showTutorial;
  final _walletKey = GlobalKey();
  final _monsterKeys = [for (var i = 0; i < Economy.fieldCapacity; i++) GlobalKey()];
  final _iconsKey = GlobalKey();
  final _sheetKey = GlobalKey();
  final _tabKeys = [for (var i = 0; i < _tabs.length; i++) GlobalKey()];

  /// 홈으로 돌아가 튜토리얼을 처음부터 보여준다 (설정의 "다시 보기").
  void startTutorial() {
    goTab(MainShell.homeTab);
    setState(() => _tutorial = true);
  }

  List<TutorialStep> get _tutorialSteps => [
        const TutorialStep(
          title: '루틴몬에 온 걸 환영해요!',
          body: '습관을 지키면 몬스터와 함께 자라는 곳이에요. 화면을 하나씩 알려 드릴게요.',
        ),
        TutorialStep(
          targets: _monsterKeys,
          title: '나의 필드',
          body: '함께하는 몬스터가 여기서 지내요. 몬스터를 누르면 쓰다듬고, 간식을 주고, 같이 놀 수 있어요.',
        ),
        TutorialStep(
          targets: [_sheetKey],
          title: '오늘의 성실도',
          body: '오늘 습관을 얼마나 지켰는지 보여줘요. 위로 밀면 내 습관 리스트가 나와요.',
        ),
        TutorialStep(
          targets: [_tabKeys[MainShell.chatTab]],
          title: '챗봇에서 습관 체크',
          body: '하루에 한 번, 챗봇에게 오늘 습관을 알려 주세요. 성실도만큼 골드를 받고 '
              '탐색을 ${Economy.encountersPerDay}번 할 수 있어요. 탐색에서 새 몬스터를 만나요.',
        ),
        TutorialStep(
          targets: [_walletKey],
          title: '골드와 성실볼',
          body: '골드로 상점에서 물약과 성실볼을 사요. 성실볼은 탐색에서 만난 몬스터를 잡을 때 써요. '
              '골드 옆 + 를 누르면 골드 얻는 법이 나와요.',
        ),
        TutorialStep(
          targets: [_iconsKey],
          title: '상점 · 가방 · 출석 · 습관',
          body: '상점에서 물건을 사고, 가방에서 꺼내 써요. 출석부에서는 연속 출석을 보고, 습관에서는 새 습관을 추가하거나 그만둘 수 있어요.',
        ),
        TutorialStep(
          targets: [_tabKeys[MainShell.goalsTab], _tabKeys[MainShell.dexTab]],
          title: '목표와 도감',
          body: '목표 탭에서 주간 · 월간 목표를 달성하면 골드를 받아요. 도감에는 만난 몬스터가 기록돼요.',
        ),
        const TutorialStep(
          title: '이제 시작해 볼까요?',
          body: '낯선 말이 나오면 옆의 ? 를 눌러 보세요. 이 안내는 설정(톱니바퀴)에서 언제든 다시 볼 수 있어요.',
        ),
      ];

  /// 튜토리얼 카드에 세울 안내 캐릭터: 대화 상대 몬스터 (없으면 필드 첫 몬스터).
  Widget? _tutorialGuide(GameState s) {
    final m = s.monsterByUid(s.chatPartnerUid) ?? s.fieldMonsters.firstOrNull;
    return m == null ? null : PixelImage(Catalog.speciesById(m.speciesId).assetAt(m.level), height: 44);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncMusic();
      // 홈에 들어온 것이 곧 오늘 출석 (하루 1번, 습관 체크와는 별개)
      if (mounted) runGameAction(context, (r) => r.attend());
    });
  }

  /// 본문 위쪽 가운데에 1.8초 동안 알림을 띄운다. [coin]이면 금화 아이콘을 붙인다.
  void toast(String text, {bool coin = false}) {
    _toastTimer?.cancel();
    setState(() {
      _toastText = text;
      _toastCoin = coin;
    });
    _toastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _toastText = null);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _scaffold(context),
        if (_tutorial)
          Positioned.fill(
            child: TutorialOverlay(
              steps: _tutorialSteps,
              guide: _tutorialGuide(GameScope.of(context)),
              onDone: () => setState(() => _tutorial = false),
            ),
          ),
      ],
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopBar(walletKey: _walletKey),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IndexedStack(
                      index: _tab,
                      children: [
                        HomeScreen(
                          active: _tab == MainShell.homeTab,
                          tutorial: _tutorial,
                          monsterKeys: _monsterKeys,
                          iconsKey: _iconsKey,
                          sheetKey: _sheetKey,
                        ),
                        ChatScreen(active: _tab == MainShell.chatTab),
                        const GoalsScreen(),
                        DexScreen(active: _tab == MainShell.dexTab),
                        const StatsScreen(),
                      ],
                    ),
                  ),
                  if (_toastText != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 14,
                      child: IgnorePointer(child: Center(child: PixelToast(text: _toastText!, coin: _toastCoin))),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.nightDeep,
          border: Border(top: BorderSide(color: AppColors.nightLine, width: 3)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => goTab(i),
                    child: Container(
                      key: _tabKeys[i],
                      height: 62,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: _tab == i ? AppColors.gold : Colors.transparent, width: 3),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          PixelIcon(
                            layers: [PixelLayer(PixelIcons.nav[_tabIcons[i]], _tab == i ? AppColors.gold : AppColors.textMuted)],
                            size: 20,
                          ),
                          const SizedBox(height: 5),
                          Text(_tabs[i],
                              style: TextStyle(fontSize: 10.5, color: _tab == i ? AppColors.gold : AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.walletKey});

  /// 골드 · 성실볼 묶음 (튜토리얼이 가리킨다).
  final GlobalKey? walletKey;

  static const _weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];

  String _fmt(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      decoration: const BoxDecoration(
        color: AppColors.nightDeep,
        border: Border(bottom: BorderSide(color: AppColors.nightLine, width: 3)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${now.month}월 ${now.day}일',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, shadows: [
                    Shadow(color: AppColors.nightLine, offset: Offset(3, 3)),
                  ])),
              const SizedBox(width: 8),
              Text(_weekdays[now.weekday - 1], style: const TextStyle(fontSize: 13, color: AppColors.purpleSoft)),
              const SizedBox(width: 8),
              // 날짜가 길어지는 날(두 자리 월 · 일)에도 넘치지 않게 남는 폭만 쓴다
              Expanded(
                child: Text('DAY ${s.dayCount} · 연속 ${s.currentStreak}일',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ),
              const SizedBox(width: 6),
              const _SettingsButton(),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // 좁은 화면에서는 탐색 글자가 줄어들고, 골드 · 성실볼은 그대로 둔다
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                          s.checkedInToday ? '탐색 ${s.encountersLeft}회 남음' : '체크인하면 탐색 ${Economy.encountersPerDay}회',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: AppColors.gold)),
                    ),
                    const SizedBox(width: 2),
                    const HelpButton(title: '탐색이란?', items: [
                      (
                        '탐색이 뭐예요?',
                        '챗봇에서 오늘 습관을 체크하면 그날 탐색을 ${Economy.encountersPerDay}번 할 수 있어요. 탐색하면 몬스터가 나타나요. 아무도 안 나올 때도 있어요.'
                      ),
                      ('몬스터 잡기', '만난 몬스터에게 성실볼을 던지면 잡을 수 있어요. 희귀한 몬스터일수록 잘 도망가요. 성실볼은 상점에서 살 수 있어요.'),
                      ('어떤 몬스터가 나와요?', '오늘 체크한 습관의 카테고리에 사는 몬스터가 나와요. 카테고리 레벨이 오르면 새로운 몬스터가 나타나요.'),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Row(
                key: walletKey,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CoinChip(
                    text: _fmt(s.gold),
                    big: true,
                    addLabel: '골드 얻는 법',
                    onAdd: () => showInfoPopup(context, title: '골드 얻는 법', items: const [
                      ('습관 체크하기', '챗봇에서 습관을 체크하면 성실도가 쌓이고, 성실도 1점마다 ${Economy.goldPerSincerity}골드를 받아요.'),
                      ('성실도 레벨업', '카테고리 성실도 레벨이 오를 때마다 ${Economy.categoryLevelUpGold}골드를 받아요.'),
                      (
                        '목표 달성',
                        '주간 목표를 달성하면 ${Economy.weeklyGoalGold}골드, 월간 목표를 달성하면 ${Economy.monthlyGoalGold}골드를 받아요.'
                      ),
                      ('이미 있는 몬스터', '이미 가진 몬스터가 또 나오면 볼을 던지지 않고 바로 ${Economy.duplicateMonsterGold}골드를 받아요.'),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  BallChip(count: s.balls),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 상단 바 오른쪽 위 톱니바퀴 → 설정 창 (배경음악 · 계정 · 로그아웃).
class _SettingsButton extends StatelessWidget {
  const _SettingsButton();

  void _open(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '설정 닫기',
      barrierColor: AppColors.black.withValues(alpha: 0),
      pageBuilder: (ctx, _, __) => _SettingsPopup(shellContext: context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '설정',
      excludeSemantics: true,
      onTap: () => _open(context),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: PixelIcon(
            layers: [
              PixelLayer(PixelIcons.gear, AppColors.textMuted),
              PixelLayer(PixelIcons.gearHole, AppColors.nightDeep),
            ],
            size: 16,
          ),
        ),
      ),
    );
  }
}

class _SettingsPopup extends StatelessWidget {
  const _SettingsPopup({required this.shellContext});
  final BuildContext shellContext;

  static const _providerName = {
    AuthProvider.email: '이메일',
    AuthProvider.kakao: '카카오',
    AuthProvider.google: 'Google',
  };

  Future<void> _logout(BuildContext context) async {
    final nav = Navigator.of(context);
    final auth = AuthScope.maybeRead(context);
    nav.pop();
    await auth?.signOut();
    nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthGate()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final bgm = BgmScope.of(context);
    final session = AuthScope.maybeRead(context)?.session;
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: PopupCard(
          title: '설정',
          ribbonColor: AppColors.purple,
          ribbonText: AppColors.white,
          maxWidth: 290,
          children: [
            GestureDetector(
              onTap: () {}, // 카드 안을 눌러도 닫히지 않게
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('배경음악',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                      ),
                      SizedBox(
                        width: 84,
                        child: PixelButton(
                          label: bgm.enabled ? '켜짐' : '꺼짐',
                          semanticLabel: bgm.enabled ? '배경음악 끄기' : '배경음악 켜기',
                          onPressed: () => bgm.setEnabled(!bgm.enabled),
                          color: bgm.enabled ? AppColors.green : AppColors.parchment,
                          shadowColor: bgm.enabled ? AppColors.fieldGreen : AppColors.parchmentShadow,
                          textColor: AppColors.brownText,
                          height: 36,
                          depth: 3,
                          fontSize: 12,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('튜토리얼',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                      ),
                      SizedBox(
                        width: 84,
                        child: PixelButton(
                          label: '다시 보기',
                          semanticLabel: '튜토리얼 다시 보기',
                          onPressed: () {
                            Navigator.of(context).pop();
                            MainShell.of(shellContext).startTutorial();
                          },
                          color: AppColors.parchment,
                          shadowColor: AppColors.parchmentShadow,
                          textColor: AppColors.brownText,
                          height: 36,
                          depth: 3,
                          fontSize: 12,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  if (session != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      '${_providerName[session.provider]} 계정으로 로그인됨'
                      '${session.email != null ? '\n${session.email}' : ''}',
                      style: const TextStyle(fontSize: 11, height: 1.6, color: AppColors.brownMuted),
                    ),
                    const SizedBox(height: 10),
                    PixelButton(
                      label: '로그아웃',
                      onPressed: () => _logout(context),
                      color: AppColors.redSoft,
                      shadowColor: AppColors.redShadow,
                      textColor: AppColors.white,
                      height: 42,
                      depth: 4,
                      fontSize: 12,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
