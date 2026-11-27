import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/models.dart';
import '../../data/pixel_icons.dart';
import '../shell/game_action.dart';

/// 선물함: 받을 선물(퀘스트 보상 · [받기] · [모두 받기])만 보인다 (11-26 — 퀘스트 목록은 뺌).
/// 퀘스트를 깨면 보상이 선물로 쌓이고, [받기]를 눌러야 골드가 들어온다 — 서버(명세 v10 11장)와 시연 모드가 같다
/// (기획 2026-11-26-선물함).
class GiftBoxScreen extends StatefulWidget {
  const GiftBoxScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GiftBoxScreen()));

  @override
  State<GiftBoxScreen> createState() => _GiftBoxScreenState();
}

class _GiftBoxScreenState extends State<GiftBoxScreen> {
  QuestBoard? _board;
  bool _loading = true;
  bool _busy = false;
  String? _toastText;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  void _toast(String text) {
    _toastTimer?.cancel();
    setState(() => _toastText = text);
    _toastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _toastText = null);
    });
  }

  /// 열 때마다 다시 조회 (완료 알림이 응답에 없어서, 명세 v9).
  Future<void> _load() async {
    final b = await runGameAction(context, (r) => r.loadQuests(), onError: _toast);
    if (!mounted) return;
    setState(() {
      _board = b;
      _loading = false;
    });
  }

  /// 하나 받기 · 모두 받기. 실패(예: 이미 받은 선물)는 문구를 띄우고, 어느 쪽이든 목록을 다시 불러온다.
  Future<void> _claim(Gift? one) async {
    if (_busy) return;
    setState(() => _busy = true);
    final got = await runGameAction(context, (r) => one == null ? r.claimAllGifts() : r.claimGift(one), onError: _toast);
    if (!mounted) return;
    setState(() => _busy = false);
    if ((got ?? 0) > 0) _toast('+${got}G 받았어요!');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    GameScope.of(context); // 골드가 바뀌면 다시 그림
    final b = _board;
    return Scaffold(
      backgroundColor: AppColors.night,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(onBack: () => Navigator.of(context).pop()),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                      : b == null
                          ? const _Empty(text: '퀘스트를 불러오지 못했어요')
                          : !b.enabled
                              ? const _Empty(text: '지금은 퀘스트가 쉬는 중이에요')
                              : ListView(
                                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                                  children: [
                                    // 받을 보상만 (11-26 피드백 — 퀘스트 목록은 뺌)
                                    _GiftSection(board: b, busy: _busy, onClaim: _claim),
                                  ],
                                ),
                ),
              ],
            ),
            if (_toastText != null)
              Positioned(
                left: 0,
                right: 0,
                top: 70,
                child: IgnorePointer(child: Center(child: PixelToast(text: _toastText!))),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      decoration: const BoxDecoration(
        color: AppColors.nightDeep,
        border: Border(bottom: BorderSide(color: AppColors.nightLine, width: 3)),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: '닫기',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBack,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.nightRaised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.nightLine2, width: 2),
                ),
                child: const Text('◀', style: TextStyle(fontSize: 14, color: AppColors.text)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const PixelIcon(layers: PixelIcons.fieldGift, size: 28, outline: 2),
          const SizedBox(width: 8),
          const Text('선물함',
              style: TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text)),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Center(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)));
}

/// 받을 선물: 퀘스트마다 한 장 + [받기], 두 개 이상이면 [모두 받기]. 서버 모드는 안내 한 줄.
class _GiftSection extends StatelessWidget {
  const _GiftSection({required this.board, required this.busy, required this.onClaim});
  final QuestBoard board;
  final bool busy;
  final void Function(Gift? one) onClaim;

  @override
  Widget build(BuildContext context) {
    final gifts = board.gifts;
    final total = gifts.fold(0, (a, g) => a + g.gold);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('받을 선물',
                  style: TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
            ),
            if (gifts.length > 1)
              Semantics(
                button: true,
                label: '모두 받기',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: busy ? null : () => onClaim(null),
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.goldLight, width: 2),
                    ),
                    child: Text('모두 받기 · ${total}G',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.night)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (gifts.isEmpty)
          const _Note(text: '받을 선물이 없어요 · 퀘스트를 깨면 여기 쌓여요')
        else
          for (final g in gifts) ...[
            _GiftCard(gift: g, busy: busy, onClaim: () => onClaim(g)),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.nightPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.nightLine, width: 3),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.textMuted)),
    );
  }
}

class _GiftCard extends StatelessWidget {
  const _GiftCard({required this.gift, required this.busy, required this.onClaim});
  final Gift gift;
  final bool busy;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.nightRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gold, width: 3),
      ),
      child: Row(
        children: [
          const PixelIcon(layers: PixelIcons.fieldGift, size: 32, outline: 2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gift.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                const SizedBox(height: 2),
                Text('${gift.weekly ? '이번 주' : '오늘의'} 퀘스트 보상${gift.itemName != null && gift.quantity > 0 ? ' · ${gift.itemName} ${gift.quantity}개' : ''}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: '${gift.title} 보상 받기',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: busy ? null : onClaim,
              child: Container(
                height: 44,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.goldLight, width: 2),
                  boxShadow: const [BoxShadow(color: AppColors.goldShadow, offset: Offset(0, 3))],
                ),
                child: Text(gift.gold > 0 ? '${gift.gold}G 받기' : '받기',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.night)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
