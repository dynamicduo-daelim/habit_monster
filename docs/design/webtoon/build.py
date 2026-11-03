"""웹툰 시안 만들기: 틀(*.template.html)의 {{이름}} 자리에 그림 · 글꼴을 base64로 넣어 한 파일 HTML로 만든다.

    python docs/design/webtoon/build.py          (저장소 맨 위에서)

- 글꼴은 페이지에 쓰인 글자만 남겨(서브셋) 넣는다 — Galmuri11 원본은 5MB라 그대로 넣으면 무겁다.
- 결과: docs/design/웹툰-시안-모닥이-1화.html (claude.ai 아티팩트로 올리는 파일)
"""
import base64, io, re
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
FONTS = ROOT / 'frontend/assets/fonts'
BG = ROOT / 'docs/design/webtoon-bg'
MON = ROOT / 'frontend/assets/images/monsters'


def b64(p):
    return base64.b64encode(Path(p).read_bytes()).decode()


def font(path, text):
    f = TTFont(path)
    o = subset.Options(); o.layout_features = []; o.name_IDs = ['*']; o.notdef_outline = True
    s = subset.Subsetter(o); s.populate(text=text); s.subset(f)
    out = io.BytesIO(); f.save(out)
    return base64.b64encode(out.getvalue()).decode()


t = (HERE / '모닥이-1화.template.html').read_text(encoding='utf-8')
text = ''.join(sorted(set(re.sub(r'<[^>]+>', '', t)))) + '…—!?·「」'
rep = {
    'GALMURI': font(FONTS / 'Galmuri11.ttf', text),
    'GALMURI_BOLD': font(FONTS / 'Galmuri11-Bold.ttf', text),
    'PRETENDARD_BOLD': font(FONTS / 'Pretendard-Bold.otf', text),
    'MONKEY': b64(MON / 'monkey.png'),
    'HARU': b64(BG / 'haru-tree.png'), 'TREE_BIG': b64(BG / 'tree-big.png'), 'TREE_CROWN': b64(BG / 'tree-crown.png'),
    'VILLAGE_SQ': b64(BG / 'village-square.png'), 'VILLAGE_PATH': b64(BG / 'village-path.png'), 'STONE': b64(BG / 'stone-yard.png'),
}
for k, v in rep.items():
    t = t.replace('{{' + k + '}}', v)
assert '{{' not in t, '채우지 못한 자리가 있다'
out = ROOT / 'docs/design/웹툰-시안-모닥이-1화.html'
out.write_text(t, encoding='utf-8')
print(out, out.stat().st_size, 'bytes')
