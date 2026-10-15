import 'dart:math';

final Random _random = Random.secure();

/// 중복 요청 방지 키 (`Idempotency-Key` 헤더, UUID v4).
///
/// 버튼을 누를 때 하나 만들고, 응답을 못 받아 **다시 보낼 때는 같은 키**를 쓴다.
/// 그러면 서버가 "이미 처리한 요청"으로 알아보고 처음 결과를 그대로 돌려줘서, 골드 · 아이템이 두 번 처리되지 않는다.
/// (패키지 없이 만든다 — UUID 하나 때문에 의존성을 늘리지 않으려고.)
String newIdempotencyKey() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // 버전 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 변형
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
