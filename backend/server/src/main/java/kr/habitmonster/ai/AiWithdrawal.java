package kr.habitmonster.ai;

import kr.habitmonster.auth.WithdrawalStep;

import org.springframework.stereotype.Component;

/** 탈퇴하면 체크인 대사 · 하루 AI 호출 수를 지운다 (API 명세 "DELETE /me", schema.sql 머리말 — ai의 대사는 물리 삭제). */
@Component
class AiWithdrawal implements WithdrawalStep {

	private final DialogueRepository dialogues;

	AiWithdrawal(DialogueRepository dialogues) {
		this.dialogues = dialogues;
	}

	@Override
	public void onWithdraw(long userId) {
		dialogues.deleteUser(userId);
	}
}
