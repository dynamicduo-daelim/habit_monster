import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../core/widgets/popup_card.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../core/theme/app_theme.dart';
import 'home_parts.dart' show CheckerPainter, CoinIcon;

/// "몇 개 살까?" 수량 팝업: −/+ · 1/5/10/최대 · 합계.
class QuantityPopup extends StatefulWidget {
  const QuantityPopup({super.key, required this.item, required this.onCancel, required this.onBuy});
  final ShopItem item;
  final VoidCallback onCancel;
  final ValueChanged<int> onBuy;

  /// 한 번에 살 수 있는 최대 개수.
  static const int maxCount = 99;

  @override
  State<QuantityPopup> createState() => _QuantityPopupState();
}

class _QuantityPopupState extends State<QuantityPopup> {
  int _n = 1;

  void _set(int n) => setState(() => _n = n.clamp(1, QuantityPopup.maxCount));

  @override
  Widget build(BuildContext context) {
    final s = GameScope.of(context);
    final it = widget.item;
    final max = math.max(1, s.gold ~/ it.price);
    final total = it.price * _n;
    final cant = total > s.gold;
    return PopupCard(
      title: '몇 개 살까?',
      ribbonColor: AppColors.woodDark,
      ribbonText: AppColors.paper,
      maxWidth: 290,
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.offWhite,
                border: Border.all(color: AppColors.ink, width: 3),
              ),
              child: PixelImage(it.asset, height: 38),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                  const SizedBox(height: 3),
                  Text('개당 ${it.price}G · 지금 보유 ${s.ownedCount(it)}개',
                      style: const TextStyle(fontSize: 10, color: AppColors.brownMuted)),
                ],
              ),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(
              width: 46,
              child: PixelButton(
                label: '−',
                semanticLabel: '하나 줄이기',
                onPressed: () => _set(_n - 1),
                color: AppColors.skyCard,
                shadowColor: AppColors.skyCardShadow,
                textColor: AppColors.brownText,
                height: 46,
                depth: 4,
                fontSize: 22,
                padding: EdgeInsets.zero,
                // Galmuri에 '−' 글자가 없어서 막대로 그린다.
                child: Container(width: 14, height: 4, color: AppColors.brownText),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brownText,
                  border: Border.all(color: AppColors.ink, width: 3),
                ),
                child: Text('$_n',
                    style: const TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.butter)),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 46,
              child: PixelButton(
                label: '+',
                semanticLabel: '하나 늘리기',
                onPressed: () => _set(_n + 1),
                color: AppColors.yellowButton,
                shadowColor: AppColors.yellowShadow,
                textColor: AppColors.brownText,
                height: 46,
                depth: 4,
                fontSize: 22,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        Row(
          children: [
            for (final (i, (label, n)) in [('1개', 1), ('5개', 5), ('10개', 10), ('최대', max)].indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTap: () => _set(n),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 34),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _n == n.clamp(1, QuantityPopup.maxCount) ? AppColors.butter : AppColors.parchment,
                      border: Border.all(color: AppColors.ink, width: 3),
                    ),
                    child: Text(label,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                  ),
                ),
              ),
            ],
          ],
        ),
        Row(
          children: [
            const Text('합계', style: TextStyle(fontSize: 11, color: AppColors.brownMuted)),
            const Spacer(),
            const CoinIcon(size: 14),
            const SizedBox(width: 5),
            Text(formatNum(total),
                style: TextStyle(fontFamily: AppTheme.pixelFont, 
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cant ? AppColors.red : AppColors.goldDeep,
                )),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: PixelButton(
                  label: '취소',
                  onPressed: widget.onCancel,
                  color: AppColors.parchment,
                  shadowColor: AppColors.parchmentShadow,
                  textColor: AppColors.brownText,
                  height: 46,
                  depth: 4,
                  fontSize: 12,
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PixelButton(
                  label: cant ? '골드가 부족해요' : '$_n개 사기',
                  onPressed: cant ? null : () => widget.onBuy(_n),
                  height: 46,
                  depth: 4,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 산 물건 정보 (구매 완료 팝업용).
class Purchase {
  const Purchase(this.item, this.count, this.ownedAfter);
  final ShopItem item;
  final int count;
  final int ownedAfter;
  int get price => item.price * count;
  bool get isBall => item.id == Catalog.seongsilBall.id;
}

/// "구매 완료!" 팝업: 몬스터에게 주기(성실볼은 탐색하러 가기) / 확인.
class PurchaseDonePopup extends StatelessWidget {
  const PurchaseDonePopup({
    super.key,
    required this.purchase,
    required this.bobUp,
    required this.onUse,
    required this.onClose,
  });
  final Purchase purchase;
  final bool bobUp;
  final VoidCallback onUse;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    return PopupCard(
      title: '구매 완료!',
      ribbonColor: AppColors.green,
      ribbonText: AppColors.brownText,
      maxWidth: 280,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(border: Border.all(color: AppColors.ink, width: 3)),
          child: CustomPaint(
            painter: const CheckerPainter(AppColors.checker, AppColors.offWhite),
            child: Center(
              child: Transform.translate(
                offset: Offset(0, bobUp ? -4 : 0),
                child: PixelImage(p.item.asset, height: 56),
              ),
            ),
          ),
        ),
        Text('${p.item.name} ×${p.count}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.brownText)),
        Text('가방에 넣었어요 · 보유 ${p.ownedAfter}개',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, height: 1.7, color: AppColors.brownMuted)),
        Container(
          color: AppColors.brownText,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CoinIcon(size: 14),
              const SizedBox(width: 5),
              Text('-${formatNum(p.price)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.butter)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: PixelButton(
                  label: p.isBall ? '탐색하러 가기' : '몬스터에게 주기',
                  onPressed: onUse,
                  color: AppColors.skyCard,
                  shadowColor: AppColors.skyCardShadow,
                  textColor: AppColors.brownText,
                  height: 44,
                  depth: 4,
                  fontSize: 11.5,
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PixelButton(label: '확인', onPressed: onClose, height: 44, depth: 4, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
