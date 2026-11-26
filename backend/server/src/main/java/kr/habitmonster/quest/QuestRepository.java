package kr.habitmonster.quest;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** {@code quest.quest_def} · {@code quest.user_quest} · {@code quest.user_month}만 읽고 쓴다 (모듈 = 스키마). */
@Repository
class QuestRepository {

	/** 조회용 한 줄 (마스터의 제목 · 순서를 붙여서). */
	record QuestRow(long id, String questCode, String title, int progress, int target, int rewardGold, String status) {
	}

	/** 진행을 올린 결과. */
	record Advanced(long id, int progress, int target) {
	}

	private final JdbcClient db;

	QuestRepository(JdbcClient db) {
		this.db = db;
	}

	/**
	 * 그 기간의 퀘스트 행을 만든다 (이미 있으면 그대로). 목표 · 보상은 지금 마스터 값으로 고정된다.
	 * 동시에 두 요청이 만들어도 유니크 키 {@code (user_id, period_start, quest_code)}가 한 행만 남긴다.
	 */
	void createMissing(long userId, LocalDate periodStart, String kind) {
		db.sql("""
			insert into quest.user_quest (user_id, period_start, quest_code, target, reward_gold)
			select ?, ?, d.code, d.target_count, d.reward_gold
			  from quest.quest_def d
			 where d.kind = ? and d.is_active
			on conflict (user_id, period_start, quest_code) do nothing""")
			.params(userId, periodStart, kind).update();
	}

	List<QuestRow> quests(long userId, LocalDate periodStart, String kind) {
		return db.sql("""
			select q.id, q.quest_code, d.title, q.progress, q.target, q.reward_gold, q.status
			  from quest.user_quest q join quest.quest_def d on d.code = q.quest_code
			 where q.user_id = ? and q.period_start = ? and d.kind = ?
			 order by d.sort_order""")
			.params(userId, periodStart, kind).query(QuestRow.class).list();
	}

	/** 진행 +1 (목표까지만, 진행 중인 것만). 이미 끝났거나 목표에 닿았으면 비어 있다. */
	Optional<Advanced> advance(long userId, LocalDate periodStart, String questCode) {
		return db.sql("""
			update quest.user_quest set progress = progress + 1
			 where user_id = ? and period_start = ? and quest_code = ? and status = 'IN_PROGRESS' and progress < target
			returning id, progress, target""")
			.params(userId, periodStart, questCode).query(Advanced.class).optional();
	}

	/**
	 * 진행도를 계산값으로 맞춘다 (주간 — 기록에서 계산). {@code GREATEST}라 내려가지 않고, 목표에서 멈춘다.
	 * 진행 중인 행만 — 이미 끝났으면 비어 있다.
	 */
	Optional<Advanced> raise(long userId, LocalDate periodStart, String questCode, int value) {
		return db.sql("""
			update quest.user_quest set progress = greatest(progress, least(?, target))
			 where user_id = ? and period_start = ? and quest_code = ? and status = 'IN_PROGRESS'
			returning id, progress, target""")
			.params(value, userId, periodStart, questCode).query(Advanced.class).optional();
	}

	/** 완료한 퀘스트의 보상(만들 때 고정한 값)과 제목 — 선물 한 줄이 된다. */
	record Completed(int rewardGold, String title) {
	}

	/**
	 * 목표에 닿은 행을 완료로 바꾼다 — 조건부 UPDATE라 한 번만 성공한다. 바꿨으면 그 행의 보상 · 제목,
	 * 이미 완료였으면 비어 있다.
	 */
	Optional<Completed> complete(long userQuestId) {
		return db.sql("""
			update quest.user_quest q set status = 'DONE', completed_at = now()
			  from quest.quest_def d
			 where d.code = q.quest_code and q.id = ? and q.status = 'IN_PROGRESS' and q.progress >= q.target
			returning q.reward_gold, d.title""")
			.param(userQuestId).query(Completed.class).optional();
	}

	// ---------- 월간 배지 (v1.14, D-91) ----------
	/** 이번 달 한 줄 ({@code quest.user_month}). */
	record MonthRow(long id, LocalDate monthStart, int completedCount, boolean badgeEarned) {
	}

	/** 받은 배지 한 줄 — {@code earnedMs} = 받은 시각(밀리초). */
	record BadgeRow(LocalDate monthStart, long earnedMs) {
	}

	private static final String MONTH_COLUMNS = "id, month_start, completed_count, badge_earned_at is not null as badge_earned";

	/**
	 * 퀘스트 하나를 완료했을 때 그달 수를 센다 — 한 문장이라 두 번 세지 않는다.
	 * <ul>
	 * <li>그달 줄이 없으면 만들면서 시작값 = 1(방금 것) + 그달 이미 완료한 다른 퀘스트 수 — 이 기능 전 완료분도 들어간다</li>
	 * <li>있으면 +1</li>
	 * </ul>
	 * 방금 것을 기록에서 세지 않고 1로 더하는 이유: 완료 시각은 DB 시계, 그달 범위는 업무 날짜라 둘이 어긋나도(테스트의 날짜 흉내 등)
	 * 방금 완료한 것은 반드시 1개로 들어가게.
	 *
	 * @param from 그달 1일 00시 · @param to 다음 달 1일 00시 (업무 시간대)
	 */
	MonthRow countCompletion(long userId, LocalDate monthStart, Instant from, Instant to, long completedQuestId) {
		return db.sql("""
			insert into quest.user_month (user_id, month_start, completed_count)
			select ?, ?, 1 + count(*) from quest.user_quest
			 where user_id = ? and status = 'DONE' and id <> ? and completed_at >= ? and completed_at < ?
			on conflict (user_id, month_start) do update set completed_count = quest.user_month.completed_count + 1
			returning\s""" + MONTH_COLUMNS) // \s: 텍스트 블록은 줄 끝 공백을 지운다 ("returningid"가 됐었다)
			.params(userId, monthStart, userId, completedQuestId, Timestamp.from(from), Timestamp.from(to))
			.query(MonthRow.class).single();
	}

	/** 조회 때: 그달 줄이 없으면 그달 이미 완료한 수로 만든다 (+1 없음). 있으면 그대로. 그 줄을 돌려준다. */
	MonthRow ensureMonth(long userId, LocalDate monthStart, Instant from, Instant to) {
		db.sql("""
			insert into quest.user_month (user_id, month_start, completed_count)
			select ?, ?, count(*) from quest.user_quest
			 where user_id = ? and status = 'DONE' and completed_at >= ? and completed_at < ?
			on conflict (user_id, month_start) do nothing""")
			.params(userId, monthStart, userId, Timestamp.from(from), Timestamp.from(to)).update();
		return db.sql("select " + MONTH_COLUMNS + " from quest.user_month where user_id = ? and month_start = ?")
			.params(userId, monthStart).query(MonthRow.class).single();
	}

	/** 목표에 닿았으면 배지 시각을 채운다 — 조건부라 한 번만 성공. 성공하면 그 줄 id (= 볼 선물의 출처 번호). */
	Optional<Long> earnBadge(long monthId, int target) {
		return db.sql("""
			update quest.user_month set badge_earned_at = now()
			 where id = ? and badge_earned_at is null and completed_count >= ? returning id""")
			.params(monthId, target).query(Long.class).optional();
	}

	/** 받은 배지만, 최신 달부터. */
	List<BadgeRow> badges(long userId) {
		return db.sql("""
			select month_start, (extract(epoch from badge_earned_at) * 1000)::bigint as earned_ms from quest.user_month
			 where user_id = ? and badge_earned_at is not null order by month_start desc""")
			.param(userId).query(BadgeRow.class).list();
	}
}
