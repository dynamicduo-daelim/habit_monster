/// 숫자에 천 단위 쉼표를 넣는다. 소수가 없으면 정수로 보여준다 (시안의 `fmtNum`).
/// 예) 10000 → '10,000', 2.5 → '2.5', 30.0 → '30'
String formatNum(num v) {
  final text = v == v.roundToDouble() ? v.round().toString() : v.toString();
  return text.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

bool _hasBatchim(String word) {
  if (word.isEmpty) return false;
  final code = word.codeUnitAt(word.length - 1);
  return code >= 0xAC00 && code <= 0xD7A3 && (code - 0xAC00) % 28 != 0;
}

/// 이름 뒤에 '와/과'를 붙인다. 예) '콩지와', '토독과'
String withWa(String name) => '$name${_hasBatchim(name) ? '과' : '와'}';

/// 목적격 조사 '을/를'만 돌려준다. 예) josaEulReul('잿불 늑대') → '를'
String josaEulReul(String name) => _hasBatchim(name) ? '을' : '를';

/// 주격 조사 '이/가'만 돌려준다. 예) josaIGa('새싹냥') → '이'
String josaIGa(String name) => _hasBatchim(name) ? '이' : '가';

/// 보조사 '은/는'만 돌려준다. 예) josaEunNeun('전공 공부') → '는'
String josaEunNeun(String name) => _hasBatchim(name) ? '은' : '는';
