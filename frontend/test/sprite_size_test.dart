import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_monster/data/catalog.dart';
import 'package:habit_monster/data/models.dart';
import 'package:habit_monster/data/sprite_sizes.dart';

/// PNG 머리(IHDR)에서 가로 · 세로를 읽는다.
(int, int) pngSize(String path) {
  final b = ByteData.sublistView(File(path).readAsBytesSync());
  return (b.getUint32(16), b.getUint32(20));
}

void main() {
  test('모든 몬스터 그림(진화 포함)이 크기 표에 있고 실제 파일 크기와 같다 — 다르면 tool/sprite_sizes.py 다시 실행', () {
    for (final sp in Catalog.species) {
      for (final a in [sp.asset, if (sp.evolvedAsset != null) sp.evolvedAsset!]) {
        expect(spriteSizes[a], pngSize(a), reason: a);
      }
    }
  });

  test('홈 필드: 모든 종이 같은 넓이로 보이고, 가장 긴 변은 칸을 넘지 않는다 (D-61)', () {
    const area = MonsterSpecies.fieldArea * MonsterSpecies.fieldArea;
    for (final sp in Catalog.species) {
      for (final lv in [1, 99]) {
        final s = sp.fieldSizeAt(lv);
        expect(s.longestSide, lessThanOrEqualTo(MonsterSpecies.fieldBox + 0.001), reason: sp.id);
        // 길쭉해서 줄인 종(토끼 · 닭 등)만 넓이가 조금 작다
        expect(s.width * s.height, inInclusiveRange(area * 0.7, area + 0.01), reason: sp.id);
      }
    }
  });
}
