package kr.habitmonster.goal;

import kr.habitmonster.auth.WithdrawalStep;

import org.springframework.stereotype.Component;

/** 탈퇴하면 목표 제목 · 상세를 비운다 (API 명세 v5 "DELETE /me", DB 원칙 7). */
@Component
class GoalWithdrawal implements WithdrawalStep {

	private final GoalService goals;

	GoalWithdrawal(GoalService goals) {
		this.goals = goals;
	}

	@Override
	public void onWithdraw(long userId) {
		goals.clearPersonalText(userId);
	}
}
