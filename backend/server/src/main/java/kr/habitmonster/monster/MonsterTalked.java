package kr.habitmonster.monster;

import java.time.LocalDate;

/**
 * 이벤트: 말 걸기({@code GET /monsters/{id}/line})가 성공했다. 같은 트랜잭션에서 동기로 전달된다 (D-85).
 * 받는 곳: 퀘스트 {@code DAILY_TALK}. 말 걸기 기록 테이블은 아직 없다 (퀘스트 7단계).
 */
public record MonsterTalked(long userId, long userMonsterId, LocalDate businessDate) {
}
