package kr.habitmonster.monster;

import java.time.LocalDate;

/**
 * 이벤트: 교감(쓰다듬기 PET · 놀아주기 PLAY · 끌기 DRAG)이 <b>기록됐다</b> — 몬스터마다 하루 첫 번째만.
 * 409로 거절된 것 · 이미 끈 몬스터의 200 {@code gain 0}은 보내지 않는다. 호감도가 최대라 {@code gain}이 0이어도 기록됐으면 보낸다.
 * 같은 트랜잭션에서 동기로 전달된다 (D-85). 받는 곳: 퀘스트 {@code DAILY_PET}(PET만).
 */
public record AffectionGiven(long userId, long userMonsterId, String action, LocalDate businessDate) {
}
