package kr.habitmonster.checkin;

import java.util.Optional;

import kr.habitmonster.ai.CheckinDialogues;
import kr.habitmonster.ai.CheckinDialogues.Line;
import kr.habitmonster.ai.CheckinInterpreter;
import kr.habitmonster.ai.DialogueWriter;
import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.habit.HabitService;
import kr.habitmonster.habit.HabitService.DialogueContext;
import kr.habitmonster.monster.MonsterService;

import org.springframework.stereotype.Service;

/**
 * 체크인 대사 {@code POST /checkins/today/dialogue} (명세 v6 5장, 기획 {@code docs/기획/2026-11-08-AI대사-알림.md}).
 *
 * <p>순서: ① 오늘 최신 revision · 문맥 읽기(짧은 트랜잭션) → 이미 저장된 대사가 있으면 그대로 → ② 모델 호출(트랜잭션 밖, 최대 3초)
 * → ③ 저장(새 트랜잭션). DB 잠금을 쥔 채 네트워크를 기다리지 않으려고 이 메서드에는 트랜잭션을 걸지 않는다.
 * 대사는 보상에 영향이 없다 — 늦거나 실패해도 체크인 결과는 그대로다.
 */
@Service
public class CheckinDialogueService {

	private final HabitService habits;
	private final MonsterService monsters;
	private final DialogueWriter writer;
	private final CheckinDialogues dialogues;

	CheckinDialogueService(HabitService habits, MonsterService monsters, DialogueWriter writer,
			CheckinDialogues dialogues) {
		this.habits = habits;
		this.monsters = monsters;
		this.writer = writer;
		this.dialogues = dialogues;
	}

	public Line dialogue(long userId) {
		DialogueContext ctx = habits.dialogueContext(userId)
			.orElseThrow(() -> new ApiException(ErrorCode.CHECKIN_REQUIRED));
		Optional<Line> saved = dialogues.saved(ctx.checkinId(), ctx.revision());
		if (saved.isPresent()) {
			return saved.get(); // 같은 revision이면 모델을 다시 부르지 않는다
		}
		CheckinInterpreter.Partner partner = monsters.partner(userId)
			.map(p -> new CheckinInterpreter.Partner(p.name(), p.affectionTier())).orElse(null);
		DialogueWriter.Written w = writer.write(new DialogueWriter.Request(partner, ctx.revision(), ctx.habits().stream()
			.map(h -> new DialogueWriter.HabitLine(h.name(), h.categoryName(), h.unit(), h.scoringMode(), h.target(),
					h.value()))
			.toList()));
		return dialogues.save(userId, ctx.checkinId(), ctx.revision(), w.line(), w.source());
	}
}
