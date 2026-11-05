package kr.habitmonster.common;

import java.util.List;

import kr.habitmonster.common.ApiExceptionHandler.FieldError;

/** 서비스에서 던지면 {@link ApiExceptionHandler}가 {@code {code, message, errors?}} 응답으로 바꾼다. */
public class ApiException extends RuntimeException {

	private final ErrorCode code;
	private final List<FieldError> errors;
	/** {@code EMAIL_REGISTERED_WITH_OTHER_METHOD}일 때 원래 가입 방법 (kakao · google · email). */
	private final String provider;
	/** 타이머 오류(명세 v6 9장)일 때 — 이미 있는 타이머 번호 · 끝난 이유. */
	private final Long timerId;
	private final String endReason;

	public ApiException(ErrorCode code) {
		this(code, code.message);
	}

	public ApiException(ErrorCode code, String message) {
		this(code, message, List.of());
	}

	/** 온보딩 일괄 제출처럼 틀린 항목을 한꺼번에 알려줄 때. */
	public ApiException(ErrorCode code, String message, List<FieldError> errors) {
		this(code, message, errors, null);
	}

	private ApiException(ErrorCode code, String message, List<FieldError> errors, String provider) {
		this(code, message, errors, provider, null, null);
	}

	private ApiException(ErrorCode code, String message, List<FieldError> errors, String provider, Long timerId,
			String endReason) {
		super(message);
		this.code = code;
		this.errors = List.copyOf(errors);
		this.provider = provider;
		this.timerId = timerId;
		this.endReason = endReason;
	}

	/** 409 {@code TIMER_ALREADY_RUNNING} — 앱이 그 타이머를 이어서 쓰거나 멈추게 번호를 알려 준다. */
	public static ApiException timerAlreadyRunning(long timerId) {
		return new ApiException(ErrorCode.TIMER_ALREADY_RUNNING, ErrorCode.TIMER_ALREADY_RUNNING.message, List.of(), null,
				timerId, null);
	}

	/** 409 {@code TIMER_NOT_RUNNING} — 어떻게 끝났는지(USER · MAX_DURATION · HABIT_STOPPED)도 알려 준다. */
	public static ApiException timerNotRunning(String endReason) {
		return new ApiException(ErrorCode.TIMER_NOT_RUNNING, ErrorCode.TIMER_NOT_RUNNING.message, List.of(), null, null,
				endReason);
	}

	/** 다른 방법으로 가입된 이메일 — 사용자에게 원래 가입 방법을 알려 준다. */
	public static ApiException registeredWithOtherMethod(String provider, String message) {
		return new ApiException(ErrorCode.EMAIL_REGISTERED_WITH_OTHER_METHOD, message, List.of(), provider);
	}

	public ErrorCode code() {
		return code;
	}

	public List<FieldError> errors() {
		return errors;
	}

	public String provider() {
		return provider;
	}

	public Long timerId() {
		return timerId;
	}

	public String endReason() {
		return endReason;
	}
}
