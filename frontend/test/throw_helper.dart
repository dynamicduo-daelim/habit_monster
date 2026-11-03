import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 탐색 화면의 성실볼 (위로 밀어 던진다).
final ballFinder = find.byKey(const ValueKey('throw_ball'));

/// 탐색 화면에 나온 몬스터 그림의 가운데.
Offset monsterCenter(WidgetTester tester) => tester.getCenter(find.byKey(const ValueKey('explore_monster')));

/// 성실볼을 [target] 쪽으로 휙 민다. 날아가는 거리 = 빠르기 × 0.18 (explore_view `_flingReach`)라서
/// 볼에서 [target]까지 거리에 맞춰 빠르기를 정한다. [sideways]만큼 옆으로 빗겨 던질 수 있다.
Future<void> flingBall(WidgetTester tester, Offset target, {double sideways = 0}) async {
  final start = tester.getCenter(ballFinder);
  final goal = target + Offset(sideways, 0);
  final dir = (goal - start) / (goal - start).distance;
  final pull = dir * 30; // 손가락이 움직이는 거리 (볼도 같이 움직이고, 손을 뗀 자리에서 날아간다)
  await swipeFrom(tester, start, pull, (goal - start - pull).distance / 0.18);
}

/// 던진 뒤 연출(날아감 · 빨려 들기 · 흔들흔들 · 터짐)이 끝날 때까지 프레임을 넘긴다.
Future<void> playThrow(WidgetTester tester, {Duration total = const Duration(milliseconds: 5000)}) async {
  for (var t = Duration.zero; t < total; t += const Duration(milliseconds: 100)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [start]에서 [offset]만큼 [speed](px/s)로 밀고 뗀다. 6번 나눠 움직이며 시각을 붙여야 손을 뗄 때 빠르기가 남는다.
Future<void> swipeFrom(WidgetTester tester, Offset start, Offset offset, double speed) async {
  const steps = 6;
  final stepMs = offset.distance / speed * 1000 / steps;
  final g = await tester.startGesture(start);
  for (var k = 1; k <= steps; k++) {
    await g.moveBy(offset / steps.toDouble(), timeStamp: Duration(microseconds: (stepMs * k * 1000).round()));
  }
  await g.up(timeStamp: Duration(microseconds: (stepMs * steps * 1000).round()));
  await tester.pump();
}
