package kr.habitmonster.ai;

import java.time.LocalDate;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** {@code ai.daily_call_count} — 사용자 · 업무 날짜별 AI 해석 호출 수 (스키마 v1.9). */
@Repository
class CallCountRepository {

	private final JdbcClient db;

	CallCountRepository(JdbcClient db) {
		this.db = db;
	}

	/**
	 * 한 문장으로 올리기 + 한도 검사 (동시에 두 요청이 와도 한도를 넘지 않게). 올렸으면 true,
	 * 이미 한도에 닿아 행이 안 돌아오면 false.
	 */
	boolean tryIncrement(long userId, LocalDate day, int limit) {
		return db.sql("""
			insert into ai.daily_call_count (user_id, call_date, call_count) values (?, ?, 1)
			on conflict (user_id, call_date) do update
			   set call_count = ai.daily_call_count.call_count + 1, updated_at = now()
			 where ai.daily_call_count.call_count < ?
			returning call_count""")
			.params(userId, day, limit).query(Integer.class).optional().isPresent();
	}
}
