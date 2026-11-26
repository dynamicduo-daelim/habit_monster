package kr.habitmonster.habit;

import java.time.LocalDate;

/**
 * 이벤트: 오늘 <b>처음</b> 출석했다 ({@code POST /me/attendance} — 같은 날 다시 부르면 보내지 않는다).
 * 같은 트랜잭션에서 동기로 전달된다 (D-85). 받는 곳: 주간 퀘스트 {@code WEEKLY_ATTEND} ({@code docs/quest/README.md}).
 */
public record Attended(long userId, LocalDate businessDate) {
}
