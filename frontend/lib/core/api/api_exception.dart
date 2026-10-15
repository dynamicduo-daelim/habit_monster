/// 게임 API 오류. 서버의 `{code, message, provider?}`를 그대로 담는다 (API 명세 v5 "에러 코드 목록").
/// [message]는 화면에 그대로 보여줄 문구다.
///
/// 앱에서 만드는 코드: NETWORK(서버 연결 실패) · SERVER(형식을 알 수 없는 오류)
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status, this.provider});

  final String code;
  final String message;

  /// HTTP 상태 코드 (앱에서 만든 오류면 null).
  final int? status;

  /// `EMAIL_REGISTERED_WITH_OTHER_METHOD`일 때 원래 가입 방법 (kakao · google · email).
  final String? provider;

  static const network = ApiException('NETWORK', '서버에 연결할 수 없어요. 잠시 후 다시 시도해 주세요');

  @override
  String toString() => 'ApiException($code)';
}
