import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/pixel_icons.dart';
import 'onboarding_controller.dart';
import 'onboarding_parts.dart';

/// 온보딩 1단계: 모험의 길(카테고리) 최대 3개 + 첫 파트너 고르기.
class StepCategories extends StatelessWidget {
  const StepCategories({super.key, required this.c, required this.tick});
  final OnboardingController c;

  /// 0.5초마다 1씩 오르는 박자 (통통 튀는 효과).
  final int tick;

  @override
  Widget build(BuildContext context) {
    const cats = Catalog.categories;
    return OnboardingFrame(
      bottom: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.brownText,
              border: Border.all(color: AppColors.ink, width: 3),
            ),
            child: Text('${c.picked.length}/${OnboardingController.maxCategories}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.butter)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PixelButton(
              label: '이 길로 간다 ▶',
              onPressed: c.picked.isEmpty ? null : c.confirmCategories,
              disabledColor: AppColors.nightLine2,
              disabledShadowColor: AppColors.ink,
              disabledTextColor: AppColors.night,
            ),
          ),
        ],
      ),
      children: [
        const StepHeader(step: 1, title: '모험의 길 고르기'),
        const ProfessorTip(text: '세 갈래의 길을 골라보게! 고른 길의 몬스터만 탐색에서 만날 수 있다네.'),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            children: [
              for (var r = 0; r < cats.length; r += 2) ...[
                if (r > 0) const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _CategoryCard(cat: cats[r], c: c)),
                      const SizedBox(width: 10),
                      Expanded(child: r + 1 < cats.length ? _CategoryCard(cat: cats[r + 1], c: c) : const SizedBox()),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(padding: const EdgeInsets.only(top: 6), child: _StarterBox(c: c, tick: tick)),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.cat, required this.c});
  final HabitCategory cat;
  final OnboardingController c;

  @override
  Widget build(BuildContext context) {
    final sel = c.picked.contains(cat.id);
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        PressCard(
          onTap: () => c.toggleCategory(cat.id),
          sunk: sel,
          sinkBy: 4,
          depth: 5,
          color: sel ? AppColors.butter : AppColors.cream,
          padding: const EdgeInsets.all(10),
          semanticLabel: '${cat.name} 길',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cat.color,
                      border: Border.all(color: AppColors.ink, width: 3),
                    ),
                    child: CategoryIcon(cat.id, size: 26),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cat.name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                        const SizedBox(height: 3),
                        Text('${cat.type} 타입', style: const TextStyle(fontSize: 9.5, color: AppColors.brownMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(cat.measures.map((m) => m.label).join(' · '),
                  style: const TextStyle(fontSize: 9.5, height: 1.6, color: AppColors.brownMuted)),
            ],
          ),
        ),
        if (sel)
          Positioned(
            right: -7,
            top: -7 + 4,
            child: IgnorePointer(
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.green,
                  border: Border.all(color: AppColors.ink, width: 3),
                ),
                child: const PixelIcon(
                  layers: [PixelLayer(PixelIcons.checkStroke, AppColors.brownText)],
                  size: 12,
                  strokeWidth: 3.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "첫 파트너는 누구?" 상자 + 후보 3자리.
class _StarterBox extends StatelessWidget {
  const _StarterBox({required this.c, required this.tick});
  final OnboardingController c;
  final int tick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.purpleDeep,
        border: Border.all(color: AppColors.ink, width: 4),
        boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(5, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Transform.translate(
                offset: Offset(0, tick.isOdd ? -4 : 0),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.butter,
                    border: Border.all(color: AppColors.ink, width: 3),
                  ),
                  child: const Text('?',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('첫 파트너는 누구?',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.white)),
                    SizedBox(height: 3),
                    Text('고른 길마다 한 마리씩 함께 가요. 먼저 이야기 나눌 첫 파트너를 골라보세요!',
                        style: TextStyle(fontSize: 9.5, height: 1.6, color: AppColors.purpleSoft)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _StarterSlot(c: c, index: i, tick: tick)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StarterSlot extends StatelessWidget {
  const _StarterSlot({required this.c, required this.index, required this.tick});
  final OnboardingController c;
  final int index;
  final int tick;

  @override
  Widget build(BuildContext context) {
    final cid = index < c.picked.length ? c.picked[index] : null;
    final cat = cid == null ? null : Catalog.category(cid);
    final spId = cid == null ? null : Catalog.starters[cid];
    final species = spId == null ? null : Catalog.speciesById(spId);
    final chosen = cid != null && c.starter == cid;
    final bob = (tick + index).isOdd ? -3.0 : 0.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        PressCard(
          onTap: () => c.pickStarter(index),
          sunk: chosen,
          sinkBy: 4,
          depth: 5,
          minHeight: 118,
          color: chosen ? AppColors.butter : (cat != null ? AppColors.purpleCard : AppColors.introFloor),
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          semanticLabel: cat != null ? '${cat.name} 길의 첫 파트너 후보' : '빈 자리',
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  // 발밑 그림자
                  Positioned(
                    bottom: -6,
                    child: Container(width: 56, height: 10, color: AppColors.ink.withValues(alpha: 0.35)),
                  ),
                  Transform.translate(
                    offset: Offset(0, bob),
                    child: species != null
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 62, maxWidth: 80),
                            child: Opacity(
                              opacity: 0.85,
                              child: ColorFiltered(
                                colorFilter: const ColorFilter.mode(AppColors.black, BlendMode.srcIn),
                                child: PixelImage(species.asset, height: 62),
                              ),
                            ),
                          )
                        : PixelIcon(
                            layers: PixelIcons.ball(cat?.color ?? AppColors.purple),
                            size: 40,
                            outline: 1.5,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                chosen && species != null ? species.name : '???',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: chosen ? AppColors.brownText : AppColors.white,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: cat?.color ?? AppColors.textMuted,
                  border: Border.all(color: AppColors.ink, width: 2),
                ),
                child: Text(
                  cat != null ? '${cat.type} 타입' : '길을 골라요',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.brownText),
                ),
              ),
            ],
          ),
        ),
        if (chosen)
          Positioned(
            left: 0,
            right: 0,
            top: -12 + 4,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    border: Border.all(color: AppColors.ink, width: 3),
                  ),
                  child: const Text('이 친구로!',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.white)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
