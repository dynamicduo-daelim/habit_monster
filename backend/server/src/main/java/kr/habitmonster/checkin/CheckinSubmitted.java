package kr.habitmonster.checkin;

import java.time.LocalDate;

/**
 * 이벤트: 오늘 체크인을 <b>처음</b> 제출했다 (다시 체크 PUT은 보내지 않는다). 결과(전부 "못했어"여도)와 상관없다.
 * 같은 트랜잭션에서 동기로 전달된다 (결정 D-85). 받는 곳: 퀘스트 {@code DAILY_CHECKIN} ({@code docs/quest/README.md} 이벤트 목록).
 */
public record CheckinSubmitted(long userId, LocalDate businessDate) {
}
