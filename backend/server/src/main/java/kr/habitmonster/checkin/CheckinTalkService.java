package kr.habitmonster.checkin;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import kr.habitmonster.ai.AiCallLimit;
import kr.habitmonster.ai.CheckinInterpreter.HistoryLine;
import kr.habitmonster.ai.CheckinInterpreter.Partner;
import kr.habitmonster.ai.TalkWriter;
import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.habit.HabitService;
import kr.habitmonster.habit.HabitService.DialogueContext;
import kr.habitmonster.monster.MonsterService;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import tools.jackson.databind.json.JsonMapper;

/**
 * 체크인 뒤 자유 대화 {@code POST /chat/talk} (기획 {@code docs/기획/2026-11-15-몬스터-대화.md} B).
 *
 * <p>습관 · 몬스터 모듈에서 문맥(오늘 기록 · 최근 7일 · 대화 상대)을 값으로 모아 {@link TalkWriter}에 넘긴다.
 * <b>아무것도 저장 · 확정하지 않는다</b> — 호감도도 오르지 않는다 (사용자 11-15). 하루 AI 호출 한도는 해석과 함께 센다.
 * 모델 호출(최대 5초) 동안 DB 연결을 잡지 않게 이 메서드에는 트랜잭션을 걸지 않는다 (습관 모듈 조회는 각자 짧은 트랜잭션).
 */
@Service
public class CheckinTalkService {

	public record TalkRequest(LocalDate businessDate, String message, List<HistoryLine> history) {
	}

	private final HabitService habits;
	private final MonsterService monsters;
	private final TalkWriter writer;
	private final BusinessDates dates;
	private final AiCallLimit callLimit;
	private final JsonMapper json;

	CheckinTalkService(HabitService habits, MonsterService monsters, TalkWriter writer, BusinessDates dates,
			AiCallLimit callLimit, JsonMapper json) {
		this.json = json;
		this.habits = habits;
		this.monsters = monsters;
		this.writer = writer;
		this.dates = dates;
		this.callLimit = callLimit;
	}

	/** 문제 분석용 임시 대화 기록 (logback-spring.xml의 talk-log 파일). 기본 꺼짐 — 로컬 프로필에서만 켠다. */
	private static final Logger TALK_LOG = LoggerFactory.getLogger("talk-log");

	private static final int LOG_HISTORY_LINES = 3;

	public TalkWriter.Reply talk(long userId, TalkRequest req) {
		LocalDate today = dates.requireToday(req.businessDate()); // 업무 날짜 (다르면 409)
		String message = req.message() == null ? "" : req.message().strip();
		List<HistoryLine> history = req.history() == null ? List.of() : req.history();
		CheckinChatService.validate(message, history);

		// 오늘 기록: 제출했으면 최신 값, 아직이면 습관 이름 · 목표만
		Optional<DialogueContext> checked = habits.dialogueContext(userId);
		List<TalkWriter.TodayHabit> todayHabits = checked
			.map(c -> c.habits().stream()
				.map(h -> new TalkWriter.TodayHabit(h.name(), h.unit(), h.scoringMode(), h.target(), h.value()))
				.toList())
			.orElseGet(() -> habits.chatHabits(userId).stream()
				.map(h -> new TalkWriter.TodayHabit(h.name(), h.unit(), h.scoringMode(), h.target(), null))
				.toList());

		if (!callLimit.tryUse(userId, today)) { // 해석과 같은 하루 한도 (ai.daily_call_count)
			throw new ApiException(ErrorCode.AI_RATE_LIMITED);
		}
		Partner partner = CheckinChatService.partnerOf(monsters, userId);
		TalkWriter.Reply reply = writer.write(new TalkWriter.Request(partner, message, history, checked.isPresent(),
				todayHabits, CheckinChatService.memoryOf(habits, userId)));
		logTurn(userId, partner, message, history, reply);
		return reply;
	}

	/** 한 턴을 JSON 한 줄로. 사용자 번호만 남기고 이름 · 이메일은 남기지 않는다. 기록 실패가 대화를 막지 않게 한다. */
	private void logTurn(long userId, Partner partner, String message, List<HistoryLine> history, TalkWriter.Reply reply) {
		if (!TALK_LOG.isInfoEnabled()) {
			return;
		}
		try {
			Map<String, Object> line = new LinkedHashMap<>();
			line.put("userId", userId);
			line.put("species", partner == null ? null : partner.speciesCode());
			line.put("tier", partner == null ? null : partner.affectionTier());
			line.put("before", history.subList(Math.max(0, history.size() - LOG_HISTORY_LINES), history.size()).stream()
				.map(h -> h.role() + ": " + h.text()).toList());
			line.put("user", message);
			line.put("reply", reply.reply());
			line.put("source", reply.source());
			line.put("safety", reply.safety());
			TALK_LOG.info(json.writeValueAsString(line));
		}
		catch (RuntimeException e) {
			// 기록은 덤이다 — 실패해도 대답은 그대로 간다
		}
	}
}
