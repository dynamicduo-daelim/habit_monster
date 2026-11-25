package kr.habitmonster.quest;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** {@code quest.quest_def} · {@code quest.user_quest}만 읽고 쓴다 (모듈 = 스키마). */
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
	 * 목표에 닿은 행을 완료로 바꾼다 — 조건부 UPDATE라 한 번만 성공한다. 바꿨으면 그 행의 보상(만들 때 고정한 값),
	 * 이미 완료였으면 비어 있다.
	 */
	Optional<Integer> complete(long userQuestId) {
		return db.sql("""
			update quest.user_quest set status = 'DONE', completed_at = now()
			 where id = ? and status = 'IN_PROGRESS' and progress >= target
			returning reward_gold""")
			.param(userQuestId).query(Integer.class).optional();
	}
}
