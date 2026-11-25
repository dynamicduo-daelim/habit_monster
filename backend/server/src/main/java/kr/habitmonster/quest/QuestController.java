package kr.habitmonster.quest;

import kr.habitmonster.quest.QuestService.Quests;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** 퀘스트 API (API 명세 v8 10장). 경로는 {@code /api/v1} 뒤. 진행은 다른 API의 결과로 서버가 올리고, 여기는 조회만. */
@RestController
class QuestController {

	private final QuestService quests;

	QuestController(QuestService quests) {
		this.quests = quests;
	}

	/** 오늘의 퀘스트. 그날 첫 조회면 일일 퀘스트를 만든다 (그래서 쓰기 트랜잭션). */
	@GetMapping("/quests")
	Quests quests(@AuthenticationPrincipal Jwt jwt) {
		return quests.today(Long.parseLong(jwt.getSubject()));
	}
}
