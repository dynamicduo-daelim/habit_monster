package kr.habitmonster.idempotency;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * 이 API는 헤더 {@code Idempotency-Key: <UUID>}가 필요하다 (API 명세 v4 "중복 요청 방지 키").
 * 같은 키로 다시 오면 처음 결과를 그대로 돌려준다 — {@link IdempotencyFilter}.
 *
 * <p>붙이는 곳: 아이템 구매 · 간식 주기 · 체크인 제출/수정 · 탐색 · 포획 · 목표 완료 · 카테고리 열기
 * + 결정 A3로 추가: 온보딩 · 습관 추가 · 목표 등록 · 기간 연장.
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface Idempotent {
}
