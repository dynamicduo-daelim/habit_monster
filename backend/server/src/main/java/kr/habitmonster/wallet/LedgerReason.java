package kr.habitmonster.wallet;

/**
 * 원장 사유 코드 = DB {@code wallet.ledger_reason} 시드 그대로. 사유마다 적립(CREDIT) · 차감(DEBIT) 방향이 DB에 정해져 있어서
 * 방향이 틀리면 원장 INSERT가 외래키로 막힌다.
 *
 * <p>{@code ref_id} 규칙 (schema.sql 주석): CHECKIN → daily_checkin.id / LEVELUP → daily_checkin.id:카테고리 코드 /
 * PERIOD_BONUS → habit_period.id / GOAL_* → goal.id / DUPLICATE → explore_log.id / SHOP_PURCHASE → purchase.id
 */
public enum LedgerReason {
	CHECKIN, LEVELUP, PERIOD_BONUS, GOAL_WEEKLY, GOAL_MONTHLY, DUPLICATE, SHOP_PURCHASE, ADJUST
}
