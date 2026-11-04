"""웹툰 만들기: 편 데이터(episodes.py)로 편마다 한 파일 HTML을 만든다.

    python docs/design/webtoon/build.py          (저장소 맨 위에서)

- 틀(episode.template.html)의 {{이름}} 자리에 표지 · 컷 · 끝 카드 · 그림 · 글꼴을 base64로 넣는다.
- 글꼴은 그 편에 쓰인 글자만 남겨(서브셋) 넣는다 — Galmuri11 원본은 5MB라 그대로 넣으면 무겁다.
- 결과: docs/design/webtoon/out/<id>-<화>.html 과 out/index.html (편 목록)
- 모닥이 1화는 예전 시안 경로 docs/design/웹툰-시안-모닥이-1화.html 에도 같이 만든다 (claude.ai 아티팩트로 올리는 파일).
- Ludo 그림이 아직 없는 소품은 단색 블록 + 칸 구석 '임시' 표시로 그린다 (ludo-프롬프트.md 의 파일 이름).
"""
import base64, html, io, re, sys
from functools import lru_cache
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from episodes import EPISODES  # noqa: E402

ROOT = HERE.parents[2]
FONTS = ROOT / 'frontend/assets/fonts'
BG = ROOT / 'docs/design/webtoon-bg'
MON = ROOT / 'frontend/assets/images/monsters'
OUT = HERE / 'out'
LEGACY = {('monkey', 1): ROOT / 'docs/design/웹툰-시안-모닥이-1화.html'}  # 예전 시안 경로
EVOLVE_SCALE = 1.15  # _2 그림이 없는 진화 화: 기본 그림을 키우고 빛을 더한다
SKIES = {'morning', 'high', 'warm', 'dusk'}
MISSING = set()  # 그림이 없어 임시로 그린 소품 이름 (끝에 알려 준다)


@lru_cache(maxsize=None)
def b64(p):
    return base64.b64encode(Path(p).read_bytes()).decode()


def font(path, text):
    f = TTFont(path)
    o = subset.Options(); o.layout_features = []; o.name_IDs = ['*']; o.notdef_outline = True
    s = subset.Subsetter(o); s.populate(text=text); s.subset(f)
    out = io.BytesIO(); f.save(out)
    return base64.b64encode(out.getvalue()).decode()


def esc(s):
    return html.escape(s, quote=False).replace('\n', '<br>')


def attr(s):
    return html.escape(s, quote=True)


def img(cls, path, style):
    return f'<img class="{cls}" src="data:image/png;base64,{b64(path)}" alt="" style="{style}">'


def pct(style, prop):
    m = re.search(rf'(?<![-\w]){prop}:\s*(-?[\d.]+)%', style)
    return float(m.group(1)) if m else None


def num(v):
    return f'{v:.2f}'.rstrip('0').rstrip('.')


def sprite_html(s, wide):
    """몬스터 한 마리. 진화 화는 <mon>_2.png, 없으면 1.15배 + 뒤에 빛."""
    mon, style, anim = s['mon'], s['style'], s.get('anim', '')
    base = MON / f'{mon}.png'
    assert base.exists(), f'몬스터 그림이 없다: {base}'
    parts = []
    path = base
    if s.get('evolved'):
        evo = MON / f'{mon}_2.png'
        if evo.exists():
            path = evo
        else:
            w, left, top = pct(style, 'width'), pct(style, 'left'), pct(style, 'top')
            assert w is not None and left is not None, f'{mon}: 진화 화 sprite style 에 left · width 가 필요하다'
            nw = w * EVOLVE_SCALE
            nleft = left - (nw - w) / 2
            style = re.sub(r'(?<![-\w])width:\s*[\d.]+%', f'width: {num(nw)}%', style, count=1)
            style = re.sub(r'(?<![-\w])left:\s*-?[\d.]+%', f'left: {num(nleft)}%', style, count=1)
            if top is not None:  # 빛: 몬스터 가운데에 (그림은 거의 정사각이라고 보고 계산)
                gw = nw * 1.8
                k = 1.0 if wide else 0.8  # 칸 폭 1%는 4:5 칸에서 높이 0.8%
                parts.append(f'<div class="glow warm" style="left: {num(nleft + nw / 2 - gw / 2)}%; '
                             f'top: {num(top + (nw / 2 - gw / 2) * k)}%; width: {num(gw)}%; aspect-ratio: 1; z-index: 0;"></div>')
    parts.append(img(f'sprite {anim}'.strip(), path, style))
    return '\n    '.join(parts)


def prop_html(p, ep_key):
    path = BG / f'{p["key"]}.png'
    cls = 'prop far' if p.get('far') else 'prop'
    if path.exists():
        return img(cls, path, p['style']), False
    MISSING.add(p['key'])
    fb = p.get('fallback')  # 있는 소품으로 대신 그린다 (예: 해돋이 언덕 → 돌바닥)
    if fb:
        return img(cls, BG / f'{fb["key"]}.png', fb['style']), True
    return f'<div class="{cls} tmp-block" aria-hidden="true" style="{p["style"]} aspect-ratio: {p.get("ar", 1)};"></div>', True


def glow_html(g):
    return f'<div class="glow {g.get("cls", "")}" style="{g["style"]}"></div>'


def panel_html(n, p, ep_key):
    assert p['sky'] in SKIES, f'{ep_key} {n}컷: 모르는 하늘 {p["sky"]}'
    tmp = False
    L = []
    L.append(f'  <section class="panel scene{" wide" if p.get("wide") else ""}" aria-label="{attr(p["aria"])}">')
    L.append(f'    <div class="sky {p["sky"]}"></div>')
    for c in p.get('clouds', []):
        L.append(f'    <svg class="cloud" data-cloud style="{c}" viewBox="0 0 13 5" aria-hidden="true"></svg>')
    if p.get('ground'):
        L.append(f'    <div class="ground" style="height: {p["ground"]}%;"></div>')
    for pr in p.get('props', []):
        h, t = prop_html(pr, ep_key)
        tmp = tmp or t
        L.append('    ' + h)
    gl = p.get('glow') or []
    gl = [gl] if isinstance(gl, dict) else gl  # 빛은 하나 또는 여러 개. behind:True 는 몬스터 뒤에 깐다
    for g in gl:
        if g.get('behind'):
            L.append('    ' + glow_html(g))
    todo = p.get('todo_prop')
    if todo and not (BG / f'{todo}.png').exists():
        MISSING.add(todo)
        tmp = True
    nr = p.get('narr')
    if nr:
        nr = {'text': nr} if isinstance(nr, str) else nr
        cls = ('narr ' + nr.get('cls', '')).strip()
        sty = f' style="{nr["style"]}"' if nr.get('style') else ''
        L.append(f'    <div class="{cls}"{sty}>{esc(nr["text"])}</div>')
    ln = p.get('lines')
    if ln:
        L.append(f'    <div class="lines" style="{ln["style"]}">')
        L += [f'      <i style="{b}"></i>' for b in ln['bars']]
        L.append('    </div>')
    for s in p.get('sprites', []):
        L.append('    ' + sprite_html(s, p.get('wide')))
    for s in p.get('sweat', []):
        L.append(f'    <div class="sweat drop" style="{s}"></div>')
    for b in p.get('bubbles', []):
        cls = ('bubble ' + b.get('cls', '')).strip()
        L.append(f'    <div class="{cls}" style="{b["style"]}">{esc(b["text"])}</div>')
    for g in gl:
        if not g.get('behind'):
            L.append('    ' + glow_html(g))
    if p.get('hand'):
        L.append(f'    <svg class="hand reach" data-hand style="{p["hand"]["style"]}" viewBox="0 0 16 14" aria-hidden="true"></svg>')
    for s in p.get('sparks', []):
        L.append(f'    <span class="spark twinkle" style="{s}"></span>')
    if p.get('sfx'):
        L.append(f'    <div class="sfx" style="{p["sfx"]["style"]}">{esc(p["sfx"]["text"])}</div>')
    if tmp:
        L.append('    <span class="tmp-badge">임시</span>')
    L.append('  </section>')
    return '\n'.join(L)


def cover_html(e):
    art = BG / f'{e["cover_prop"]}.png'
    if art.exists():
        a = f'<img class="cover-art" src="data:image/png;base64,{b64(art)}" alt="">'
    else:
        MISSING.add(e['cover_prop'])
        # 표지 소품이 아직 없으면 하루나무 섬으로 (빈 상자보다 낫다). 소품이 오면 저절로 바뀐다.
        a = f'<img class="cover-art" src="data:image/png;base64,{b64(BG / "haru-tree.png")}" alt="">'
    return f'''  <header class="cover">
    {a}
    <span class="village">{esc(e["village"])}</span>
    <h1><small>{esc(e["label"])}</small>{esc(e["title"])}</h1>
    <p>{esc(e["intro"])}</p>
  </header>'''


def end_html(e):
    c = e['end_card']
    hearts = f'<div class="hearts" id="hearts" data-n="{c["hearts"]}" aria-label="{attr(c.get("hearts_label", ""))}"></div>\n      ' if 'hearts' in c else ''
    nx = c.get('next')
    nxt = f'''
    <div class="card locked">
      <svg class="lock" id="lock" viewBox="0 0 12 12" aria-hidden="true"></svg>
      <div>
        <div class="k">{esc(nx["k"])}</div>
        <div class="t">{esc(nx["t"])}</div>
        <div class="d">{esc(nx["d"])}</div>
      </div>
    </div>''' if nx else ''
    return f'''  <footer class="end">
    <div class="card">
      {hearts}<div>
        <div class="k">{esc(c["k"])}</div>
        <div class="t">{esc(c["t"])}</div>
        <div class="d">{esc(c.get("d", ""))}</div>
      </div>
    </div>{nxt}
    <button class="replay" id="replay" type="button">처음부터 다시 보기</button>
    <a class="to-list" href="index.html">← 편 목록으로</a>
    <p class="foot">모아루틴 스토리 시안 · 몬스터는 앱 그림, 배경 소품은 Ludo.ai로 만든 픽셀 그림</p>
  </footer>'''


def fill(t):
    """글꼴 자리를 채운다 (서브셋은 이 문서에 쓰인 글자로)."""
    text = ''.join(sorted(set(re.sub(r'<[^>]+>', '', t)))) + '…—!?·「」'
    rep = {
        'GALMURI': font(FONTS / 'Galmuri11.ttf', text),
        'GALMURI_BOLD': font(FONTS / 'Galmuri11-Bold.ttf', text),
        'PRETENDARD_BOLD': font(FONTS / 'Pretendard-Bold.otf', text),
    }
    for k, v in rep.items():
        t = t.replace('{{' + k + '}}', v)
    assert '{{' not in t, '채우지 못한 자리가 있다'
    return t


def build_episode(e, tpl):
    key = f'{e["id"]}-{e["ep"]}'
    assert 3 <= len(e['panels']) <= 4, f'{key}: 컷은 3 ~ 4개'
    t = tpl
    t = t.replace('{{TITLE}}', attr(f'{e["label"]} · {e["title"]}'))
    t = t.replace('{{COVER}}', cover_html(e))
    t = t.replace('{{PANELS}}', '\n\n'.join(panel_html(i + 1, p, key) for i, p in enumerate(e['panels'])))
    t = t.replace('{{END}}', end_html(e))
    return fill(t)


def index_html(tpl_index, style):
    groups = {}  # (이름) -> [편]; 마을 장은 '따끈마을 장' 묶음
    for e in EPISODES:
        g = f'{e["name"]} 장' if e['kind'] == 'chapter' else e['name']
        groups.setdefault((e['village'], g), []).append(e)
    rows = []
    for (village, g), eps in groups.items():
        rows.append(f'  <section class="group">\n    <h2>{esc(g)}<small>{esc(village)}</small></h2>')
        for e in sorted(eps, key=lambda x: x['ep']):
            no = f'{e["ep"]}장' if e['kind'] == 'chapter' else f'{e["ep"]}화'
            rows.append(f'    <a class="ep" href="{e["id"]}-{e["ep"]}.html"><span class="no">{no}</span>'
                        f'<div><div class="t">{esc(e["title"])}</div><div class="d">{esc(e["end_card"]["t"])}</div></div></a>')
        rows.append('  </section>')
    t = tpl_index.replace('{{STYLE}}', style).replace('{{LIST}}', '\n'.join(rows))
    return fill(t)


# 아티팩트 서버는 <!DOCTYPE html>로 시작하는 문서만 받는다 (11-04) — 틀 앞에 문서 머리를 붙인다.
HEAD = '<!DOCTYPE html>\n<html lang="ko">\n'


def doc(page):
    return page if page.lstrip().lower().startswith('<!doctype') else HEAD + page


def main():
    tpl = (HERE / 'episode.template.html').read_text(encoding='utf-8')
    tpl_index = (HERE / 'index.template.html').read_text(encoding='utf-8')
    style = re.search(r'<style>.*?</style>', tpl, re.S).group(0)
    OUT.mkdir(exist_ok=True)
    seen = set()
    for e in EPISODES:
        key = (e['id'], e['ep'])
        assert key not in seen, f'편이 두 번 있다: {key}'
        seen.add(key)
        page = build_episode(e, tpl)
        out = OUT / f'{e["id"]}-{e["ep"]}.html'
        page = doc(page)
        out.write_text(page, encoding='utf-8')
        print(out, out.stat().st_size, 'bytes')
        if key in LEGACY:
            LEGACY[key].write_text(page, encoding='utf-8')
            print(LEGACY[key], '(예전 시안 경로)')
    idx = OUT / 'index.html'
    idx.write_text(doc(index_html(tpl_index, style)), encoding='utf-8')
    print(idx, idx.stat().st_size, 'bytes')
    if MISSING:
        print('임시로 그린 소품(Ludo 그림 없음):', ', '.join(sorted(MISSING)))


if __name__ == '__main__':
    main()
