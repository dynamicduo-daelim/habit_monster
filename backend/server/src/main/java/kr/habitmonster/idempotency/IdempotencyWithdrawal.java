package kr.habitmonster.idempotency;

import kr.habitmonster.auth.WithdrawalStep;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** 탈퇴하면 그 사용자의 중복 방지 키 기록을 지운다 (DB v1.7 원칙 7: 물리 삭제 대상). */
@Component
class IdempotencyWithdrawal implements WithdrawalStep {

	private final JdbcTemplate jdbc;

	IdempotencyWithdrawal(JdbcTemplate jdbc) {
		this.jdbc = jdbc;
	}

	@Override
	public void onWithdraw(long userId) {
		jdbc.update("delete from api.idempotency_record where user_id = ?", userId);
	}
}
