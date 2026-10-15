package kr.habitmonster.common;

import java.util.List;

import kr.habitmonster.common.ApiExceptionHandler.FieldError;

/** 서비스에서 던지면 {@link ApiExceptionHandler}가 {@code {code, message, errors?}} 응답으로 바꾼다. */
public class ApiException extends RuntimeException {

	private final ErrorCode code;
	private final List<FieldError> errors;

	public ApiException(ErrorCode code) {
		this(code, code.message);
	}

	public ApiException(ErrorCode code, String message) {
		this(code, message, List.of());
	}

	/** 온보딩 일괄 제출처럼 틀린 항목을 한꺼번에 알려줄 때. */
	public ApiException(ErrorCode code, String message, List<FieldError> errors) {
		super(message);
		this.code = code;
		this.errors = List.copyOf(errors);
	}

	public ErrorCode code() {
		return code;
	}

	public List<FieldError> errors() {
		return errors;
	}
}
