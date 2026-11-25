package kr.habitmonster.quest;

import kr.habitmonster.checkin.CheckinSubmitted;
import kr.habitmonster.habit.TimerStopped;
import kr.habitmonster.monster.AffectionGiven;
import kr.habitmonster.monster.MonsterTalked;

import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * 다른 모듈의 이벤트 → 퀘스트 진행 (결정 D-85). {@code @EventListener}는 보낸 쪽과 같은 스레드 · 같은 트랜잭션에서 바로 돈다
 * → 원래 행동과 퀘스트 진행이 함께 커밋되거나 함께 취소된다. 보내는 모듈은 퀘스트를 모른다.
 * 이벤트 목록은 {@code docs/quest/README.md}.
 */
@Component
class QuestListener {

	private final QuestService quests;

	QuestListener(QuestService quests) {
		this.quests = quests;
	}

	@EventListener
	void on(CheckinSubmitted e) {
		quests.progressDaily(e.userId(), e.businessDate(), QuestService.DAILY_CHECKIN);
	}

	@EventListener
	void on(AffectionGiven e) {
		if ("PET".equals(e.action())) {
			quests.progressDaily(e.userId(), e.businessDate(), QuestService.DAILY_PET);
		}
	}

	@EventListener
	void on(MonsterTalked e) {
		quests.progressDaily(e.userId(), e.businessDate(), QuestService.DAILY_TALK);
	}

	@EventListener
	void on(TimerStopped e) {
		quests.progressDaily(e.userId(), e.businessDate(), QuestService.DAILY_TIMER);
	}
}
