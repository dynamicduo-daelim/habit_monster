"""몬스터 그림의 원래 크기(가로 · 세로 px) 표를 만든다 → lib/data/sprite_sizes.dart (2026-11-02, 결정 D-61).
홈 필드는 이 비율로 "보이는 넓이"를 맞춰 그린다. 몬스터 그림을 추가 · 교체하면 다시 실행한다:
frontend/ 에서 `python tool/sprite_sizes.py` (Pillow 필요). 빠뜨리면 test/sprite_size_test.dart가 실패한다.
"""
import glob
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
rows = []
for p in sorted(glob.glob(os.path.join(ROOT, 'assets', 'images', 'monsters', '*.png'))):
    w, h = Image.open(p).size
    rows.append(f"  'assets/images/monsters/{os.path.basename(p)}': ({w}, {h}),")
out = os.path.join(ROOT, 'lib', 'data', 'sprite_sizes.dart')
with open(out, 'w', encoding='utf-8', newline='\n') as f:
    f.write('// 자동 생성 — tool/sprite_sizes.py. 손으로 고치지 않는다.\n\n')
    f.write('/// 몬스터 그림 경로 → 원래 크기 (가로, 세로 px). 홈 필드에서 보이는 넓이를 맞출 때 쓴다 (D-61).\n')
    f.write('const Map<String, (int, int)> spriteSizes = {\n' + '\n'.join(rows) + '\n};\n')
print(len(rows), 'sprites')
