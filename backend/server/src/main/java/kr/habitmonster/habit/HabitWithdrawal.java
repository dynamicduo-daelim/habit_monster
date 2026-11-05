package kr.habitmonster.habit;

import kr.habitmonster.auth.WithdrawalStep;

import org.springframework.stereotype.Component;

/** 탈퇴하면 습관 이름을 비우고 타이머를 끝낸다 (API 명세 v5 "DELETE /me", DB 원칙 7). 기록 행은 통계용으로 남는다. */
@Component
class HabitWithdrawal implements WithdrawalStep {

	private final HabitService habits;
	private final TimerService timers;

	HabitWithdrawal(HabitService habits, TimerService timers) {
		this.habits = habits;
		this.timers = timers;
	}

	@Override
	public void onWithdraw(long userId) {
		habits.clearPersonalText(userId);
		timers.endAll(userId); // 끝나지 않은 타이머를 끝낸다 (명세 v6 9장 · DB 제안 3장)
	}
}
