package kr.habitmonster.ai;

import java.util.Optional;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 저장한 체크인 대사 {@code ai.checkin_dialogue} (스키마 v1.7) — 체크인 revision당 1개.
 * 읽기 · 저장이 각각 짧은 트랜잭션이라, 모델 호출(최대 3초)은 그 사이 트랜잭션 밖에서 한다.
 */
@Service
public class CheckinDialogues {

	/** {@code POST /checkins/today/dialogue} 응답 그대로. */
	public record Line(int revision, String line, String source) {
	}

	private final DialogueRepository dialogues;

	CheckinDialogues(DialogueRepository dialogues) {
		this.dialogues = dialogues;
	}

	@Transactional(readOnly = true)
	public Optional<Line> saved(long checkinId, int revision) {
		return dialogues.find(checkinId, revision);
	}

	/**
	 * 저장한다. 같은 revision이 이미 있으면(동시에 두 요청이 왔을 때) 먼저 저장된 것을 돌려준다 —
	 * 같은 revision에는 언제나 같은 대사.
	 */
	@Transactional
	public Line save(long userId, long checkinId, int revision, String line, String source) {
		dialogues.insertIfAbsent(userId, checkinId, revision, line, source);
		return dialogues.find(checkinId, revision).orElseThrow();
	}
}
