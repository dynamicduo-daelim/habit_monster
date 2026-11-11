package kr.habitmonster.ai;

import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** {@code ai.checkin_dialogue} — 체크인 revision당 대사 1개 (스키마 v1.7). */
@Repository
class DialogueRepository {

	private final JdbcClient db;

	DialogueRepository(JdbcClient db) {
		this.db = db;
	}

	Optional<CheckinDialogues.Line> find(long checkinId, int revision) {
		return db.sql("""
			select revision, line_text as line, source from ai.checkin_dialogue
			 where daily_checkin_id = ? and revision = ?""")
			.params(checkinId, revision).query(CheckinDialogues.Line.class).optional();
	}

	/** 이미 있으면 아무것도 하지 않는다 (기본 키 = daily_checkin_id, revision). */
	void insertIfAbsent(long userId, long checkinId, int revision, String line, String source) {
		db.sql("""
			insert into ai.checkin_dialogue (daily_checkin_id, revision, user_id, line_text, source)
			values (?, ?, ?, ?, ?) on conflict (daily_checkin_id, revision) do nothing""")
			.params(checkinId, revision, userId, line, source).update();
	}

	/** 탈퇴: 이 사용자의 대사 · 하루 호출 수를 지운다 (DB 원칙 — ai의 대화 · 대사는 물리 삭제). */
	void deleteUser(long userId) {
		db.sql("delete from ai.checkin_dialogue where user_id = ?").param(userId).update();
		db.sql("delete from ai.daily_call_count where user_id = ?").param(userId).update();
	}
}
