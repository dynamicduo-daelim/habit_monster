package kr.habitmonster.habit;

import java.time.LocalDate;

/**
 * 이벤트: 습관 타이머가 끝나 기록이 생겼다 ({@code STOPPED} — 직접 끝냄 {@code USER} · 최대 시간 {@code MAX_DURATION} ·
 * 습관 그만둠 {@code HABIT_STOPPED}). 탈퇴 정리로 끝낸 것은 보내지 않는다. {@code businessDate}는 기록되는 날(끝난 날)이라
 * 자동 종료가 늦게 정리되면 어제일 수 있다. 같은 트랜잭션에서 동기로 전달된다 (D-85). 받는 곳: 퀘스트 {@code DAILY_TIMER}.
 */
public record TimerStopped(long userId, long habitId, LocalDate businessDate, int minutes, String endReason) {
}
