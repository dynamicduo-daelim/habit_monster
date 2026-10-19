package kr.habitmonster.goal;

import java.time.LocalDate;
import java.util.List;

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

	long insertGoal(long userId, String goalType, LocalDate periodStart, String title, String detail) {
		return db.sql("""
			insert into goal.goal (user_id, goal_type, period_start, title, detail) values (?, ?, ?, ?, ?) returning id""")
			.params(userId, goalType, periodStart, title, detail).query(Long.class).single();
	}

	record GoalRow(long goalId, String title, String detail, String status) {
	}

	/** 그 기간의 목표 (삭제한 것 빼고, 등록 순서). */
	List<GoalRow> goals(long userId, String goalType, LocalDate periodStart) {
		return db.sql("""
			select id as goal_id, title, detail, status from goal.goal
			 where user_id = ? and goal_type = ? and period_start = ? and status <> 'DELETED' order by id""")
			.params(userId, goalType, periodStart).query(GoalRow.class).list();
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
