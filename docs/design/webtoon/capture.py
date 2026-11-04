"""웹툰 검사 + 대표 캡처: out/ 의 HTML 을 하나씩 폭 390 으로 열어 확인한다.

    python docs/design/webtoon/capture.py          (저장소 맨 위에서, build.py 를 먼저 돌린 뒤)

- 편마다 한 줄 출력: 콘솔 오류 수 · 가로 넘침(scrollWidth > 390) · 칸 수 · 칸 밖으로 잘린 말풍선 수
- 대표 4장을 docs/스크린샷/2026-11-04/ 에 저장 (목록 · 모닥이 3화 · 콩지 2화 · 따끈마을 3장)
- 인터넷이 없어도 돌도록 구글 글꼴 요청은 막는다 (Galmuri11 · Pretendard 는 파일 안에 들어 있다).
- 문제가 있으면 종료 코드 1.
"""
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = HERE / 'out'
SHOTS = ROOT / 'docs/스크린샷/2026-11-04'
WIDTH = 390
FEATURED = {
    'index': '01-웹툰-목록.png',
    'monkey-3': '02-웹툰-모닥이-3화.png',
    'rabbit-2': '03-웹툰-콩지-2화.png',
    'village-hot-3': '04-웹툰-따끈마을-3장.png',
}

# 말풍선이 칸 틀 밖으로 나갔는지: 칸(.panel) 안쪽에서 벗어난 .bubble · .narr · .sfx 를 센다
CLIPPED = """() => {
  let n = 0;
  document.querySelectorAll('.panel').forEach(p => {
    const r = p.getBoundingClientRect();
    p.querySelectorAll('.bubble, .narr, .sfx').forEach(e => {
      const b = e.getBoundingClientRect();
      if (b.left < r.left - 1 || b.right > r.right + 1 || b.top < r.top - 1 || b.bottom > r.bottom + 1) n++;
    });
  });
  return n;
}"""


def check(browser, page_path, shot=None):
    errors = []
    ctx = browser.new_context(viewport={'width': WIDTH, 'height': 844}, device_scale_factor=1)
    page = ctx.new_page()
    page.route('**/fonts.googleapis.com/**', lambda r: r.abort())
    page.route('**/fonts.gstatic.com/**', lambda r: r.abort())
    page.on('console', lambda m: errors.append(m.text) if m.type == 'error' else None)
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.goto(page_path.as_uri())
    page.wait_for_timeout(300)
    # 칸 애니메이션을 모두 끝난 모습으로 (재생 클래스를 붙이고 잠깐 기다린다)
    page.evaluate("document.querySelectorAll('.panel').forEach(p => p.classList.add('play'))")
    page.wait_for_timeout(1900)
    sw = page.evaluate('document.documentElement.scrollWidth')
    panels = page.evaluate("document.querySelectorAll('.panel').length")
    clipped = page.evaluate(CLIPPED)
    if shot:
        SHOTS.mkdir(parents=True, exist_ok=True)
        page.screenshot(path=str(SHOTS / shot), full_page=True)
    ctx.close()
    return errors, sw, panels, clipped


def main():
    pages = sorted(OUT.glob('*.html'), key=lambda p: (p.stem == 'index', p.stem))
    bad = 0
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        for p in pages:
            errors, sw, panels, clipped = check(browser, p, FEATURED.get(p.stem))
            flags = []
            if errors:
                flags.append(f'콘솔 오류 {len(errors)}')
            if sw > WIDTH:
                flags.append(f'가로 넘침 {sw}>{WIDTH}')
            if clipped:
                flags.append(f'칸 밖으로 나간 글 {clipped}')
            bad += bool(flags)
            print(f'{p.name:22} 칸 {panels} · 폭 {sw} · ' + ('문제: ' + ', '.join(flags) if flags else 'OK'))
            for e in errors[:3]:
                print('    ', e[:160])
        browser.close()
    print(f'확인 {len(pages)}개, 문제 있는 쪽 {bad}개')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
