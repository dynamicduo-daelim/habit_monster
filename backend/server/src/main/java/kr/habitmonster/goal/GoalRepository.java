package kr.habitmonster.goal;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** {@code goal} 스키마만 읽고 쓴다. */
@Repository
class GoalRepository {

	private final JdbcClient db;

	GoalRepository(JdbcClient db) {
		this.db = db;
	}

	void createGoalUser(long userId) {
		db.sql("insert into goal.goal_user (user_id) values (?)").param(userId).update();
	}

	/** 같은 사람의 목표 요청을 한 줄로 세운다 (잠금 순서: habit_user → goal_user → … → wallet). */
	Optional<Long> lockGoalUser(long userId) {
		return db.sql("select user_id from goal.goal_user where user_id = ? for no key update").param(userId)
			.query(Long.class).optional();
	}

	long insertGoal(long userId, String goalType, LocalDate periodStart, String title, String detail) {
		return db.sql("""
			insert into goal.goal (user_id, goal_type, period_start, title, detail) values (?, ?, ?, ?, ?) returning id""")
			.params(userId, goalType, periodStart, title, detail).query(Long.class).single();
	}

	record GoalRow(long goalId, String goalType, LocalDate periodStart, String title, String detail, String status) {
	}

	/** 기간이 남은 목표 = {@code since}(오늘 − 기간 + 1) 이후에 등록한 것, 삭제한 것 빼고 등록 순서. */
	List<GoalRow> liveGoals(long userId, String goalType, LocalDate since) {
		return db.sql("""
			select id as goal_id, goal_type, period_start, title, detail, status from goal.goal
			 where user_id = ? and goal_type = ? and period_start >= ? and status <> 'DELETED' order by id""")
			.params(userId, goalType, since).query(GoalRow.class).list();
	}

	/** 내 목표 하나 (삭제한 것은 없는 것으로). */
	Optional<GoalRow> goal(long userId, long goalId) {
		return db.sql("""
			select id as goal_id, goal_type, period_start, title, detail, status from goal.goal
			 where id = ? and user_id = ? and status <> 'DELETED'""")
			.params(goalId, userId).query(GoalRow.class).optional();
	}

	void updateTexts(long goalId, String title, String detail) {
		db.sql("update goal.goal set title = ?, detail = ?, updated_at = now() where id = ?")
			.params(title, detail, goalId).update();
	}

	void delete(long goalId) {
		db.sql("update goal.goal set status = 'DELETED', deleted_at = now(), updated_at = now() where id = ?")
			.param(goalId).update();
	}

	void complete(long goalId) {
		db.sql("update goal.goal set status = 'COMPLETED', completed_at = now(), updated_at = now() where id = ?")
			.param(goalId).update();
	}

	/** 유료로 더한 주간 칸 수 (결제 도입 전에는 항상 0). */
	int extraWeeklySlots(long userId) {
		return db.sql("select extra_weekly_slots from goal.goal_user where user_id = ?").param(userId)
			.query(Integer.class).optional().orElse(0);
	}

	/** 탈퇴: 목표 제목 · 상세를 비운다 (DB 원칙 7). */
	void clearTexts(long userId) {
		db.sql("update goal.goal set title = null, detail = null, updated_at = now() where user_id = ?").param(userId).update();
	}
}
