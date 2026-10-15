package kr.habitmonster.auth;

/**
 * 회원 탈퇴 때 각 모듈이 자기 데이터를 정리하는 연결 고리.
 *
 * <p>DB 원칙: 각 모듈은 자기 스키마만 쓴다. 그래서 회원(identity) 쪽이 습관 · 목표 · AI 테이블을 직접 지우지 않고,
 * 모듈마다 이 인터페이스를 구현해 두면 {@link AuthService#withdraw}가 같은 트랜잭션에서 모두 부른다.
 * 예: 습관 모듈은 습관 이름을 비우고, AI 모듈은 대화를 지운다 (API 명세 v5 "DELETE /me").
 * 지금은 중복 방지 키 기록만 있고, 나머지는 각 모듈을 만들 때 붙인다.
 */
public interface WithdrawalStep {

	void onWithdraw(long userId);
}
