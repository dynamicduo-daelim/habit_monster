package kr.habitmonster.checkin;

import java.time.LocalDate;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;

import kr.habitmonster.ai.CheckinInterpreter;
import kr.habitmonster.ai.CheckinInterpreter.DraftAnswer;
import kr.habitmonster.ai.CheckinInterpreter.HabitContext;
import kr.habitmonster.ai.CheckinInterpreter.HistoryLine;
import kr.habitmonster.ai.CheckinInterpreter.Result;
import kr.habitmonster.common.ApiException;
import kr.habitmonster.common.BusinessDates;
import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.habit.HabitService;
import kr.habitmonster.habit.HabitService.ChatHabit;
import kr.habitmonster.monster.MonsterService;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * 챗봇 대화 해석 {@code POST /checkins/today/interpret} (제안 {@code docs/제안/2026-10-30-AI챗봇-API.md}, 결정 D-57).
 *
 * <p>습관 · 몬스터 모듈에서 오늘 문맥을 값으로 모아 AI 해석({@link CheckinInterpreter})에 넘긴다. <b>아무것도 저장 · 확정하지 않는다</b> —
 * 앱이 후보를 확인 카드로 보여 주고, 사용자가 [맞아]를 누르면 기존 체크인 제출로 간다. 그래서 중복 방지 키가 필요 없다.
 * 모델 호출(최대 3초)을 하는 동안 DB 연결을 잡고 있지 않게 트랜잭션을 걸지 않는다.
 */
@Service
public class CheckinChatService {

	public record InterpretRequest(LocalDate businessDate, String message, List<HistoryLine> history,
			List<DraftAnswer> draft, Long askingHabitId) {
	}

	/** 응답 = 해석 결과 + 아직 기록 후보가 없는 습관 (등록 순서). */
	public record Interpreted(String reply, List<CheckinInterpreter.Answer> answers, CheckinInterpreter.AskAgain askAgain,
			List<Long> remainingHabitIds, boolean safety, String source) {
	}

	static final int MAX_MESSAGE = 300;
	static final int MAX_HISTORY = 10;

	private final HabitService habits;
	private final MonsterService monsters;
	private final CheckinInterpreter interpreter;
	private final BusinessDates dates;
	private final int dailyLimit;

	/** 사용자 · 날짜별 하루 호출 수 (서버 메모리 — 서버를 다시 켜면 처음부터. 설정값 · DB 기록은 DB 제안 5번 합의 뒤). */
	private final Map<String, AtomicInteger> calls = new ConcurrentHashMap<>();

	CheckinChatService(HabitService habits, MonsterService monsters, CheckinInterpreter interpreter, BusinessDates dates,
			@Value("${app.llm.daily-call-limit:60}") int dailyLimit) {
		this.habits = habits;
		this.monsters = monsters;
		this.interpreter = interpreter;
		this.dates = dates;
		this.dailyLimit = dailyLimit;
	}

	public Interpreted interpret(long userId, InterpretRequest req) {
		LocalDate today = dates.requireToday(req.businessDate()); // ⑤ 업무 날짜
		String message = req.message() == null ? "" : req.message().strip();
		List<HistoryLine> history = req.history() == null ? List.of() : req.history();
		List<DraftAnswer> draft = req.draft() == null ? List.of() : req.draft();
		if (message.isEmpty() || message.length() > MAX_MESSAGE || history.size() > MAX_HISTORY
				|| history.stream().anyMatch(h -> h == null || h.text() == null || h.text().length() > MAX_MESSAGE)) {
			throw new ApiException(ErrorCode.INVALID_REQUEST);
		}
		List<ChatHabit> today0 = habits.chatHabits(userId);
		if (today0.isEmpty()) {
			throw new ApiException(ErrorCode.NO_ACTIVE_HABIT);
		}
		if (calls.computeIfAbsent(userId + ":" + today, k -> new AtomicInteger()).incrementAndGet() > dailyLimit) {
			throw new ApiException(ErrorCode.AI_RATE_LIMITED);
		}

		List<HabitContext> context = today0.stream()
			.map(h -> new HabitContext(h.habitId(), h.name(), h.categoryName(), h.unit(), h.scoringMode(), h.target(),
					h.maxValue(), h.options()))
			.toList();
		CheckinInterpreter.Partner partner = monsters.partner(userId)
			.map(p -> new CheckinInterpreter.Partner(p.name(), p.affectionTier())).orElse(null);
		Result r = interpreter.interpret(new CheckinInterpreter.Request(partner, context, message, history, draft,
				req.askingHabitId()));

		Set<Long> recorded = draft.stream().map(DraftAnswer::habitId).collect(Collectors.toCollection(HashSet::new));
		r.answers().forEach(a -> recorded.add(a.habitId()));
		List<Long> remaining = context.stream().map(HabitContext::habitId).filter(id -> !recorded.contains(id)).toList();
		return new Interpreted(r.reply(), r.answers(), r.askAgain(), remaining, r.safety(), r.source());
	}
}
