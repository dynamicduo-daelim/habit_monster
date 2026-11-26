package kr.habitmonster.gift;

/**
 * 선물 출처 = DB {@code gift.gift_source} 시드 그대로 (스키마 v1.13). 골드가 있는 선물은 받을 때 이 이름과 같은 원장 사유로 적립한다
 * ({@code LedgerReason.valueOf(name())}) — 그래서 골드를 주는 출처는 원장 사유에도 있어야 한다 (verify S-33).
 */
public enum GiftSource {
	/** 일일 퀘스트 완료 — {@code source_ref} = {@code quest.user_quest.id} */
	QUEST_DAILY,
	/** 주간 퀘스트 완료 — {@code source_ref} = {@code quest.user_quest.id} */
	QUEST_WEEKLY
}
