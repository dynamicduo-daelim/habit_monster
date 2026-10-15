package kr.habitmonster.common;

import org.springframework.http.HttpStatus;

/**
 * 앱과 같은 오류 코드. 응답은 {@code {"code": ..., "message": ..., "errors"?: [...]}}이고, message는 앱이 화면에 그대로 보여준다.
 * (frontend/lib/core/auth/auth_service.dart 의 AuthException 문구와 맞춤 · API 명세 v4 "에러 코드 목록")
 */
public enum ErrorCode {
	// 400
	INVALID_REQUEST(HttpStatus.BAD_REQUEST, "입력값을 확인해 주세요"),
	INVALID_EMAIL(HttpStatus.BAD_REQUEST, "이메일 주소를 확인해 주세요"),
	WEAK_PASSWORD(HttpStatus.BAD_REQUEST, "비밀번호는 8자 이상이에요"),
	// 401
	INVALID_TOKEN(HttpStatus.UNAUTHORIZED, "다시 로그인해 주세요"),
	TOKEN_EXPIRED(HttpStatus.UNAUTHORIZED, "로그인이 만료됐어요"),
	INVALID_CREDENTIALS(HttpStatus.UNAUTHORIZED, "이메일 또는 비밀번호가 맞지 않아요"),
	// 403
	ACCOUNT_WITHDRAWN(HttpStatus.FORBIDDEN, "탈퇴한 계정이에요"),
	ONBOARDING_REQUIRED(HttpStatus.FORBIDDEN, "시작하기를 먼저 끝내 주세요"),
	// 404
	NOT_FOUND(HttpStatus.NOT_FOUND, "찾을 수 없어요"),
	UNSUPPORTED_PROVIDER(HttpStatus.NOT_FOUND, "지원하지 않는 로그인 방식이에요"),
	// 409
	EMAIL_TAKEN(HttpStatus.CONFLICT, "이미 가입된 이메일이에요"),
	BUSINESS_DATE_CHANGED(HttpStatus.CONFLICT, "날짜가 바뀌었어요. 화면을 새로 불러올게요"),
	REQUEST_IN_PROGRESS(HttpStatus.CONFLICT, "처리 중이에요. 잠시 후 다시 시도해 주세요"),
	// 422
	IDEMPOTENCY_KEY_REUSED(HttpStatus.UNPROCESSABLE_CONTENT, "요청을 확인해 주세요"),
	// 503
	SOCIAL_NOT_CONFIGURED(HttpStatus.SERVICE_UNAVAILABLE, "아직 준비 중인 로그인 방식이에요");

	public final HttpStatus status;
	public final String message;

	ErrorCode(HttpStatus status, String message) {
		this.status = status;
		this.message = message;
	}
}
