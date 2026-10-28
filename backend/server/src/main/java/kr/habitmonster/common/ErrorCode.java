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
	INVALID_PROVIDER_TOKEN(HttpStatus.UNAUTHORIZED, "로그인을 확인하지 못했어요. 다시 시도해 주세요"),
	// 403
	ACCOUNT_WITHDRAWN(HttpStatus.FORBIDDEN, "탈퇴한 계정이에요"),
	ONBOARDING_REQUIRED(HttpStatus.FORBIDDEN, "시작하기를 먼저 끝내 주세요"),
	// 404
	NOT_FOUND(HttpStatus.NOT_FOUND, "찾을 수 없어요"),
	UNSUPPORTED_PROVIDER(HttpStatus.NOT_FOUND, "지원하지 않는 로그인 방식이에요"),
	CHECKIN_NOT_FOUND(HttpStatus.NOT_FOUND, "오늘 체크인을 먼저 해 주세요"),
	/** 도감 상세: 본 적 없는 종 (이름 · 그림을 알려 주지 않는다). */
	NOT_DISCOVERED(HttpStatus.NOT_FOUND, "아직 만나지 못한 몬스터예요"),
	// 409
	EMAIL_TAKEN(HttpStatus.CONFLICT, "이미 가입된 이메일이에요"),
	/** 응답에 {@code provider}(원래 가입 방법, 소문자)가 같이 간다. */
	EMAIL_REGISTERED_WITH_OTHER_METHOD(HttpStatus.CONFLICT, "다른 방법으로 가입된 이메일이에요"),
	ALREADY_ONBOARDED(HttpStatus.CONFLICT, "이미 시작하기를 마쳤어요"),
	BUSINESS_DATE_CHANGED(HttpStatus.CONFLICT, "날짜가 바뀌었어요. 화면을 새로 불러올게요"),
	REQUEST_IN_PROGRESS(HttpStatus.CONFLICT, "처리 중이에요. 잠시 후 다시 시도해 주세요"),
	ALREADY_SUBMITTED(HttpStatus.CONFLICT, "오늘 체크인은 이미 했어요"),
	/** 앱은 습관 추가 · 연장을 안내한다. */
	NO_ACTIVE_HABIT(HttpStatus.CONFLICT, "오늘 체크인할 습관이 없어요"),
	CHECKIN_REQUIRED(HttpStatus.CONFLICT, "오늘 체크인을 먼저 해 주세요"),
	/** 이미 던졌거나, 다시 탐색 · 날짜가 바뀌어 사라진 등장. */
	ENCOUNTER_CLOSED(HttpStatus.CONFLICT, "몬스터가 이미 떠났어요"),
	/** 쓰다듬기 · 놀아주기는 몬스터마다 하루 1번. 앱은 실패가 아니라 안내로 보여 준다. */
	ALREADY_DONE_TODAY(HttpStatus.CONFLICT, "오늘은 이미 했어요. 내일 또 해 주세요"),
	/** 기간 연장은 기간을 채운(ENDED) 습관만. */
	HABIT_NOT_ENDED(HttpStatus.CONFLICT, "기간을 다 채운 습관만 연장할 수 있어요"),
	HABIT_ALREADY_STOPPED(HttpStatus.CONFLICT, "이미 그만둔 습관이에요"),
	ALREADY_OPENED(HttpStatus.CONFLICT, "이미 연 카테고리예요"),
	/** 완료한 목표는 수정 · 삭제 · 다시 완료할 수 없다 (완료는 되돌릴 수 없음). */
	GOAL_COMPLETED(HttpStatus.CONFLICT, "이미 완료한 목표예요"),
	/** 기간(등록한 날부터 7일 · 30일)이 끝난 목표. */
	GOAL_PERIOD_ENDED(HttpStatus.CONFLICT, "기간이 끝난 목표예요"),
	/** 등록한 날에는 완료할 수 없다 (C1 — 등록 → 바로 완료로 골드 벌기 방지). 명세 v5 보충 10-28에 사용자 요청으로 추가. */
	GOAL_TOO_EARLY(HttpStatus.CONFLICT, "목표는 다음 날부터 완료할 수 있어요"),
	// 422
	IDEMPOTENCY_KEY_REUSED(HttpStatus.UNPROCESSABLE_CONTENT, "요청을 확인해 주세요"),
	NOT_ENOUGH_GOLD(HttpStatus.UNPROCESSABLE_CONTENT, "골드가 모자라요"),
	/** 앱은 볼 사기 버튼을 보여 준다. */
	NO_BALL(HttpStatus.UNPROCESSABLE_CONTENT, "성실볼이 없어요"),
	NO_EXPLORE_LEFT(HttpStatus.UNPROCESSABLE_CONTENT, "오늘 탐색을 다 했어요"),
	NO_ITEM(HttpStatus.UNPROCESSABLE_CONTENT, "물약이 없어요"),
	MAX_LEVEL(HttpStatus.UNPROCESSABLE_CONTENT, "이미 최고 레벨이에요"),
	/** 필드에 1마리일 때 넣기 · 꽉 찼을 때 꺼내기. */
	FIELD_LIMIT(HttpStatus.UNPROCESSABLE_CONTENT, "필드 자리를 확인해 주세요"),
	CATEGORY_LOCKED(HttpStatus.UNPROCESSABLE_CONTENT, "아직 열지 않은 카테고리예요"),
	/** 카테고리 해금권 없음 — 가진 종이 5 · 10 · 15마리가 될 때 1장씩. */
	NO_TICKET(HttpStatus.UNPROCESSABLE_CONTENT, "카테고리를 열 해금권이 없어요"),
	/** 진행 중 + 기간 완료가 이미 {@code max_active_habits}(5)개. 기간 완료 습관을 연장하거나 그만두면 자리가 생긴다. */
	HABIT_LIMIT(HttpStatus.UNPROCESSABLE_CONTENT, "습관 칸이 꽉 찼어요"),
	/** 진행 중 + 기간 완료가 1개뿐이면 그만둘 수 없다 (D-14 · 사용자 결정 10-21). 명세 v5에 사용자 요청으로 추가. */
	LAST_HABIT(HttpStatus.UNPROCESSABLE_CONTENT, "습관은 1개 이상 있어야 해요"),
	/** 기간이 남은 목표(진행 중 · 완료)가 칸을 다 차지함. 기간이 끝나거나 삭제하면 빈다. */
	GOAL_SLOT_FULL(HttpStatus.UNPROCESSABLE_CONTENT, "목표 칸이 꽉 찼어요"),
	// 503
	SOCIAL_NOT_CONFIGURED(HttpStatus.SERVICE_UNAVAILABLE, "아직 준비 중인 로그인 방식이에요");

	public final HttpStatus status;
	public final String message;

	ErrorCode(HttpStatus status, String message) {
		this.status = status;
		this.message = message;
	}
}
