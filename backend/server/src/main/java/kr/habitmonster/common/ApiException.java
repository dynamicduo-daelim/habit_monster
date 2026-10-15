package kr.habitmonster.common;

import java.util.List;

import kr.habitmonster.common.ApiExceptionHandler.FieldError;

/** 서비스에서 던지면 {@link ApiExceptionHandler}가 {@code {code, message, errors?}} 응답으로 바꾼다. */
public class ApiException extends RuntimeException {

	private final ErrorCode code;
	private final List<FieldError> errors;
	/** {@code EMAIL_REGISTERED_WITH_OTHER_METHOD}일 때 원래 가입 방법 (kakao · google · email). */
	private final String provider;

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
		super(message);
		this.code = code;
		this.errors = List.copyOf(errors);
		this.provider = provider;
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
}
