package kr.habitmonster.common;

import java.util.List;

import com.fasterxml.jackson.annotation.JsonInclude;

import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

@RestControllerAdvice
public class ApiExceptionHandler {

	/** {@code errors}는 여러 필드가 한꺼번에 틀릴 수 있는 400에서만 담는다 (없으면 응답에서 빠짐). */
	@JsonInclude(JsonInclude.Include.NON_NULL)
	public record ErrorBody(String code, String message, List<FieldError> errors) {
	}

	public record FieldError(String field, String reason) {
	}

	public static ResponseEntity<ErrorBody> body(ErrorCode code, String message) {
		return ResponseEntity.status(code.status).body(new ErrorBody(code.name(), message, null));
	}

	@ExceptionHandler(ApiException.class)
	ResponseEntity<ErrorBody> api(ApiException e) {
		List<FieldError> errors = e.errors().isEmpty() ? null : e.errors();
		return ResponseEntity.status(e.code().status).body(new ErrorBody(e.code().name(), e.getMessage(), errors));
	}

	@ExceptionHandler(MethodArgumentNotValidException.class)
	ResponseEntity<ErrorBody> invalid(MethodArgumentNotValidException e) {
		List<FieldError> errors = e.getBindingResult().getFieldErrors().stream()
			.map(f -> new FieldError(f.getField(), f.getDefaultMessage()))
			.toList();
		return ResponseEntity.status(ErrorCode.INVALID_REQUEST.status)
			.body(new ErrorBody(ErrorCode.INVALID_REQUEST.name(), ErrorCode.INVALID_REQUEST.message, errors));
	}

	/** 없는 경로도 {@code {code, message}} 모양으로 (Spring 기본 오류 JSON 대신). */
	@ExceptionHandler(NoResourceFoundException.class)
	ResponseEntity<ErrorBody> notFound(NoResourceFoundException e) {
		return body(ErrorCode.NOT_FOUND, ErrorCode.NOT_FOUND.message);
	}

	@ExceptionHandler(HttpMessageNotReadableException.class)
	ResponseEntity<ErrorBody> unreadable(HttpMessageNotReadableException e) {
		return body(ErrorCode.INVALID_REQUEST, ErrorCode.INVALID_REQUEST.message);
	}
}
