import 'package:flutter/material.dart';

import '../../core/constants/economy.dart';
import '../../core/state/game_state.dart';
import '../../core/widgets/help_button.dart';

// 홈 바텀시트(HabitSheet)는 11-26에 뺐다 — 습관 · 성실도는 첫 화면 "오늘" 탭에 (D-99). 성실도 ? 도움말만 남는다.

/// "오늘의 성실도" 옆 ? 버튼: 성실도가 무엇이고 어디에 쓰이는지.
class SincerityHelp extends StatelessWidget {
  const SincerityHelp({super.key});

  @override
  Widget build(BuildContext context) {
    return const HelpButton(title: '성실도란?', items: [
      ('성실도가 뭐예요?', '오늘 습관을 얼마나 지켰는지 보여주는 점수예요. 챗봇에서 오늘 습관을 체크하면 쌓여요.'),
      (
        '어떻게 정해져요?',
        '목표에 가까울수록 점수가 높고, 습관 하나에 최대 ${Economy.maxSincerityPerHabit}점이에요. '
            '점수가 높은 습관 ${Economy.dailyHabitCap}개만 더해서 하루에 최대 ${GameState.maxDailyScore}점까지 받아요.'
      ),
      (
        '어디에 쓰여요?',
        '성실도 1점마다 ${Economy.goldPerSincerity}골드를 받아요. 카테고리 레벨도 함께 올라서, '
            '레벨이 오르면 ${Economy.categoryLevelUpGold}골드를 받고 탐색에서 새로운 몬스터를 만날 수 있어요.'
      ),
    ]);
  }
}
