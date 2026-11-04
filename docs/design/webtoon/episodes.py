"""편 데이터. 컷 대본(docs/기획/웹툰-대본/*.md)을 build.py가 읽는 표로 옮긴 것.

EPISODES = [ 편, ... ]  — 편 하나:
  id        'monkey' 같은 종 이름(소문자) 또는 장이면 'village-hot'
  ep        1 ~ 3
  kind      'species' (종 화) | 'chapter' (마을 장)
  name      목록 묶음 이름 ('모닥이' / '따끈마을')
  label     표지 위 작은 글 ('모닥이 1화' / '따끈마을 1장')
  title     편 제목
  village   표지 마을 띠 ('따끈마을 · 운동')
  cover_prop  표지 그림 소품 키
  intro     표지 설명 (줄바꿈은 \\n)
  panels    컷 목록 (아래)
  end_card  {k,t,d}  + 선택: hearts(0~5, 하트 칸 수), hearts_label, next={k,t,d}(잠긴 다음 이야기 카드)

컷 하나 (모두 선택 항목은 ?):
  aria      칸 설명(스크린리더)
  sky       'morning' | 'high' | 'warm' | 'dusk'
  ground    땅 높이 % (0이면 땅 없음)
  wide      True면 1:1 칸
  clouds?   픽셀 구름 style 목록
  props     [{key, style, far?, ar?, fallback?}]  key = docs/design/webtoon-bg/<key>.png.
            파일이 없으면 fallback(있는 소품)으로 그리거나, 없으면 단색 블록(가로:세로 = ar) + 칸 구석 '임시'
  sprites   [{mon, evolved?, anim?, style}]  mon = 몬스터 그림 이름. evolved면 <mon>_2.png, 없으면 1.15배 + 빛
  bubbles   [{text, style, cls?}]  cls 예: 'pop tail-right' · 'small'
  narr?     내레이션 글 (\\n = 줄바꿈) 또는 {text, cls?, style?}
  sfx?      {text, style}
  glow?     {cls, style, behind?} 또는 그 목록. behind면 몬스터 뒤
  hand?     {style}  돌봄이의 손
  lines?    {style, bars:[style...]}  속도선
  sweat?    [style...]  식은땀
  sparks?   [style...]  반짝
  todo_prop?  아직 없는 Ludo 소품 파일 이름(ludo-프롬프트.md와 같은 이름). 파일이 없으면 칸 구석에 '임시'

아래 도우미(pos · PR · SP · BB · GL · HAND · LN · SPK)는 위 모양의 dict 를 짧게 쓰려는 것이다.
위치는 모두 칸 틀 기준 % — l(left) r(right) t(top) b(bottom) w(width).
"""


def pos(l=None, r=None, t=None, b=None, w=None):
    parts = [f'{k}: {v}%;' for k, v in (('left', l), ('right', r), ('top', t), ('bottom', b), ('width', w)) if v is not None]
    return ' '.join(parts)


def PR(key, l=None, r=None, b=None, w=None, far=False, ar=None, fb=None):
    """배경 소품. fb=(대신 쓸 소품 키, l, b, w) · ar=그림이 없을 때 임시 블록의 가로:세로 비."""
    d = {'key': key, 'style': pos(l=l, r=r, b=b, w=w)}
    if far:
        d['far'] = True
    if ar:
        d['ar'] = ar
    if fb:
        d['fallback'] = {'key': fb[0], 'style': pos(l=fb[1], b=fb[2], w=fb[3])}
    return d


def SP(mon, l, t, w, anim=None, evolved=False, final=False, rot=None, flip=False, extra=''):
    """몬스터. rot=기울임(도) · flip=좌우 반전 (CSS rotate · scale 속성이라 애니메이션과 안 겹친다).
    final=True 는 '이미 1.15배 반영한 값'으로 적은 대본 수치 — _2 그림이 없어 build.py가 다시 키우므로 미리 나눠 둔다."""
    if evolved and final:
        w0 = round(w / 1.15, 2)
        l = round(l + (w - w0) / 2, 2)
        w = w0
    style = pos(l=l, t=t, w=w)
    if rot is not None:
        style += f' rotate: {rot}deg;'
    if flip:
        style += ' scale: -1 1;'
    if extra:
        style += ' ' + extra
    d = {'mon': mon, 'style': style}
    if anim:
        d['anim'] = anim
    if evolved:
        d['evolved'] = True
    return d


def SIL(mon, l, t, w, anim=None):
    """실루엣(검은 윤곽) — 아직 만나지 않은 몬스터."""
    return SP(mon, l, t, w, anim=anim, extra='filter: brightness(0) opacity(.72);')


def BB(text, cls='', **p):
    d = {'text': text, 'style': pos(**p)}
    if cls:
        d['cls'] = cls
    return d


def GL(cls, l=None, r=None, t=None, b=None, w=None, behind=False):
    z = ' z-index: 0;' if behind else ''  # .glow 는 기본 z-index 1 이라 몬스터 위로 올라온다 — 뒤에 깔 때는 0
    return {'cls': cls, 'style': pos(l=l, r=r, t=t, b=b, w=w) + ' aspect-ratio: 1;' + z, 'behind': behind}


def HAND(l=None, r=None, b=None, w=None):
    return {'style': pos(l=l, r=r, b=b, w=w)}


def LN(l, t, w, h, rot=-40):
    """속도선 · 소리선 세 줄."""
    return {'style': pos(l=l, t=t, w=w) + f' height: {h}%;',
            'bars': [f'left: 0; top: 20%; height: 26px; transform: rotate({rot}deg);',
                     f'left: 32%; top: 0; height: 34px; transform: rotate({rot}deg);',
                     f'left: 64%; top: 26%; height: 22px; transform: rotate({rot}deg);']}


def SPK(*pts, delay=0.9):
    """반짝 — (left, top) 쌍마다 하나, 조금씩 늦게."""
    return [f'left: {x}%; top: {y}%; animation-delay: {delay + i * 0.15:.2f}s;' for i, (x, y) in enumerate(pts)]


def SFX(text, size=22, rot=-6, **p):
    return {'text': text, 'style': pos(**p) + f' font-size: {size}px; transform: rotate({rot}deg);'}


def CL(l, t, w):
    return f'left: {l}%; top: {t}%; width: {w}%;'


BOTTOM_L = {'cls': 'bottom', 'style': 'left: 10px; right: auto;'}  # 아래 왼쪽에 놓는 내레이션


def NB(text):
    return {'text': text, **BOTTOM_L}


EPISODES = [
    # ───────────────────────── 모닥이 ─────────────────────────
    {
        'id': 'monkey', 'ep': 1, 'kind': 'species',
        'name': '모닥이', 'label': '모닥이 1화', 'title': '이마의 작은 불씨',
        'village': '따끈마을 · 운동', 'cover_prop': 'haru-tree',
        'intro': '모아땅 한가운데 하루나무 곁, 돌바닥이 따끈한 아침 마을.\n처음 만난 날의 이야기예요.',
        'panels': [
            {   # 1컷: 따끈마을 아침, 신나서 큰 나무 위로
                'aria': '1컷: 모닥이가 신나서 큰 나무 위로 뛰어오른다',
                'sky': 'morning', 'ground': 22,
                'clouds': ['left: 6%; top: 20%; width: 26%;', 'left: 44%; top: 9%; width: 20%;'],
                'props': [
                    {'key': 'village-square', 'style': 'left: -6%; bottom: 6%; width: 92%;'},
                    {'key': 'tree-big', 'style': 'right: -12%; bottom: 3%; width: 70%;'},
                ],
                'narr': '따끈마을의 아침.\n처음 보는 손님에 모닥이는 신이 났다.',
                'lines': {'style': 'left: 34%; top: 50%; width: 26%; height: 22%;',
                          'bars': ['left: 0; top: 20%; height: 26px; transform: rotate(-40deg);',
                                   'left: 32%; top: 0; height: 34px; transform: rotate(-40deg);',
                                   'left: 64%; top: 26%; height: 22px; transform: rotate(-40deg);']},
                'sprites': [{'mon': 'monkey', 'anim': 'jump', 'style': 'left: 54%; top: 23%; width: 25%;'}],
                'bubbles': [{'text': '끽끽! 손님이다끽!', 'cls': 'pop tail-right', 'style': 'right: 4%; top: 15%;'}],
                'sfx': {'text': '휘익—', 'style': 'left: 5%; top: 86%; font-size: 24px; transform: rotate(-8deg);'},
            },
            {   # 2컷: 나무 꼭대기, 아래가 까마득
                'aria': '2컷: 나무 꼭대기에서 내려가지 못하고 작게 운다',
                'sky': 'high',
                'clouds': ['left: 60%; top: 14%; width: 30%;', 'left: 4%; top: 30%; width: 18%;'],
                'props': [
                    {'key': 'village-path', 'far': True, 'style': 'left: 64%; bottom: 3%; width: 32%;'},
                    {'key': 'tree-crown', 'style': 'left: -34%; bottom: -36%; width: 100%;'},
                ],
                'sprites': [{'mon': 'monkey', 'anim': 'shiver', 'style': 'left: 8%; top: 33%; width: 30%;'}],
                'sweat': ['left: 35%; top: 34%;'],
                'bubbles': [{'text': '끽…', 'cls': 'small', 'style': 'left: 34%; top: 25%;'}],
                'narr': '올라가는 건 쉬웠는데,\n내려가는 길은 보이지 않았다.',
            },
            {   # 3컷: 나무 아래에서, 돌봄이의 손
                'aria': '3컷: 돌봄이가 손을 내밀자 모닥이가 내려다본다',
                'sky': 'warm',
                'props': [{'key': 'tree-big', 'style': 'left: -38%; top: -14%; width: 176%;'}],
                'narr': '돌봄이가 가만히 손을 내밀었다.',
                'sprites': [{'mon': 'monkey', 'style': 'left: 35%; top: 30%; width: 28%; transform: rotate(-6deg);'}],
                'bubbles': [{'text': '…잡아도 돼끽?', 'cls': 'small', 'style': 'left: 60%; top: 32%;'}],
                'glow': {'cls': 'warm', 'style': 'left: 15%; bottom: -26%; width: 72%; aspect-ratio: 1;'},
                'hand': {'style': 'left: 31%; bottom: -2%; width: 38%;'},
            },
            {   # 4컷: 따끈한 돌바닥 위, 불씨가 반짝
                'aria': '4컷: 돌바닥에 내려온 모닥이의 이마 불씨가 반짝 켜진다',
                'sky': 'morning', 'ground': 40, 'wide': True,
                'props': [{'key': 'stone-yard', 'style': 'left: 10%; bottom: -22%; width: 80%;'}],
                'glow': {'cls': 'flare', 'style': 'left: 31%; top: 26%; width: 38%; aspect-ratio: 1;'},
                'sprites': [{'mon': 'monkey', 'anim': 'hop', 'style': 'left: 30%; top: 34%; width: 40%;'}],
                'sparks': ['left: 30%; top: 32%; animation-delay: .9s;', 'left: 66%; top: 28%; animation-delay: 1.05s;',
                           'left: 22%; top: 52%; animation-delay: 1.2s;', 'left: 74%; top: 48%; animation-delay: 1.35s;'],
                'bubbles': [{'text': '고마워끽! 이제 친구다끽!', 'cls': 'pop tail-right', 'style': 'right: 4%; top: 4%;'}],
                'narr': {'text': '이마의 작은 불씨가, 반짝 켜졌다.', 'cls': 'bottom', 'style': 'left: 10px; right: auto;'},
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '모닥이와 친해진 사이가 됐어요',
            'd': '호감도 4 이상이면 1화가 열려요. 도감에서 언제든 다시 볼 수 있어요.',
            'hearts': 4, 'hearts_label': '호감도 친해진 사이',
            'next': {'k': '다음 이야기', 't': '2화 「일단 해보자끽」', 'd': '단짝(호감도 7)이 되면 열려요.'},
        },
    },
    {
        'id': 'monkey', 'ep': 2, 'kind': 'species',
        'name': '모닥이', 'label': '모닥이 2화', 'title': '일단 해보자끽',
        'village': '따끈마을 · 운동', 'cover_prop': 'stone-yard',
        'intro': '스트레칭 첫날, 모닥이는 너무 서둘렀어요.\n같은 속도로 천천히 해 본 날의 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 모닥이가 팔을 마구 휘두르며 스트레칭을 한다',
                'sky': 'morning', 'ground': 24, 'clouds': [CL(6, 28, 24)],
                'props': [PR('stone-yard', l=4, b=2, w=92)],
                'narr': '스트레칭 첫날.\n모닥이는 일단 몸부터 움직였다.',
                'lines': LN(10, 50, 24, 22),
                'sprites': [SP('monkey', 38, 34, 28, 'jump')],
                'bubbles': [BB('하나 둘 셋 넷! 다 했다끽!', 'pop tail-right', r=4, t=23)],
                'sfx': SFX('휙휙휙', 24, -8, l=5, t=86),
            },
            {
                'aria': '2컷: 발이 꼬여 혼자 넘어진다',
                'sky': 'morning', 'ground': 24,
                'props': [PR('stone-yard', l=4, b=2, w=92)],
                'narr': '너무 빨리 하다가,\n혼자 데구루루 넘어졌다.',
                'sprites': [SP('monkey', 30, 44, 30, 'shiver', rot=18)],
                'sparks': SPK((38, 38), (52, 34)),
                'bubbles': [BB('끽…?', 'small', l=58, t=46)],
                'sfx': SFX('털썩', 24, -8, l=8, t=84),
            },
            {
                'aria': '3컷: 돌봄이의 손 그림자와 같은 속도로 천천히 팔을 올린다',
                'sky': 'high', 'ground': 24,
                'props': [PR('stone-yard', l=4, b=2, w=92), PR('village-square', l=56, b=20, w=50, far=True)],
                'narr': '돌봄이는 같은 속도로\n천천히 팔을 올렸다.',
                'sprites': [SP('monkey', 22, 34, 28)],
                'glow': GL('warm', l=46, b=-14, w=58, behind=True),
                'hand': HAND(l=58, b=-2, w=30),
                'bubbles': [BB('…천천히, 이 속도끽?', 'small', l=40, t=27)],
            },
            {
                'aria': '4컷: 둘이 엉덩방아를 찧으며 웃는다',
                'sky': 'warm', 'ground': 40, 'wide': True,
                'props': [PR('stone-yard', l=10, b=-20, w=80)],
                'sprites': [SP('monkey', 30, 36, 36, 'hop')],
                'glow': GL('warm', r=6, b=10, w=22),
                'sparks': SPK((24, 34), (70, 30), (22, 56)),
                'bubbles': [BB('끽끽끽! 또 하자끽!', 'pop tail-right', r=4, t=6)],
                'narr': NB('같이 끝내고, 둘이 엉덩방아를 찧으며 웃었다.'),
                'sfx': SFX('쿵', 26, 6, r=8, t=60),
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '모닥이와 단짝이 됐어요',
            'd': '호감도 7 이상이면 2화가 열려요.',
            'hearts': 5, 'hearts_label': '호감도 단짝',
            'next': {'k': '다음 이야기', 't': '3화 「불씨가 모닥불이 되던 날」', 'd': 'Lv.10(1차 진화)이 되면 열려요.'},
        },
    },
    {
        'id': 'monkey', 'ep': 3, 'kind': 'species',
        'name': '모닥이', 'label': '모닥이 3화', 'title': '불씨가 모닥불이 되던 날',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-warm-rock',
        'intro': '이마의 불씨가 간질간질 커지던 날.\n모닥이가 한 뼘 자란 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 이마의 불씨가 간질간질 커지고 모닥이가 부르르 떤다',
                'sky': 'morning', 'ground': 22,
                'props': [PR('village-square', l=-4, b=6, w=90), PR('haru-tree', r=-6, b=18, w=36, far=True)],
                'narr': '이마의 불씨가\n간질간질 커지기 시작했다.',
                'sprites': [SP('monkey', 32, 34, 32, 'shiver')],
                'glow': GL('flare', l=39, t=32, w=18),
                'bubbles': [BB('이마가 간질간질하다끽…?', 'small', l=6, t=24)],
                'sfx': SFX('따끈따끈', 22, 6, r=6, t=84),
            },
            {
                'aria': '2컷: 놀란 모닥이가 콩지 뒤로 쏙 숨는다',
                'sky': 'morning', 'ground': 22,
                'props': [PR('village-square', l=-4, b=6, w=90)],
                'narr': '놀란 모닥이가\n콩지 뒤로 쏙 숨었다.',
                'sprites': [SP('monkey', 24, 40, 24, 'hop'), SP('rabbit', 42, 36, 30)],
                'glow': GL('flare', l=29, t=42, w=13),
                'bubbles': [BB('끽! 불, 불이 커졌다끽!', 'pop', l=4, t=22), BB('…콩, 콩. 따뜻해.', 'small', r=4, t=30)],
                'sfx': SFX('쏙', 26, -6, l=8, t=84),
            },
            {
                'aria': '3컷: 모닥이의 모닥불 빛 곁에 친구들이 둥글게 앉는다',
                'sky': 'warm', 'ground': 30, 'wide': True,
                'props': [PR('hot-warm-rock', l=30, b=22, w=44, ar=1.6, fb=('stone-yard', 30, 18, 44))],
                'glow': GL('warm', l=26, t=22, w=48, behind=True),
                'sprites': [SP('monkey', 38, 34, 28, evolved=True), SP('rabbit', 8, 46, 22), SP('chicken', 70, 46, 22)],
                'bubbles': [BB('…콩, 콩. 포근해.', 'small', l=4, t=30), BB('꼬오— 따뜻하다… 하아암.', 'small', r=3, t=30)],
                'narr': NB('따뜻해진 걸 안 친구들이 하나둘 둘러앉았다.'),
            },
            {
                'aria': '4컷: 한 뼘 자란 모닥이가 신나게 끽 한다',
                'sky': 'high', 'ground': 40,
                'props': [PR('stone-yard', l=10, b=-18, w=80)],
                'glow': GL('flare', l=32, t=22, w=36, behind=True),
                'sprites': [SP('monkey', 28, 26, 42, 'hop', evolved=True)],
                'sparks': SPK((22, 28), (74, 24), (18, 52), (78, 50)),
                'bubbles': [BB('끽! 나 조금 컸다끽!', 'pop tail-right', r=4, t=22)],
                'narr': '몸이 한 뼘 자란 모닥이가\n신나게 "끽!" 했다.',
                'sfx': SFX('와아—', 26, -6, l=6, t=86),
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '모닥이가 1차 진화했어요',
            'd': 'Lv.10이 되면 3화가 열려요. 모닥이 이야기는 여기까지예요.',
            'next': {'k': '다음 이야기', 't': '콩지 1화 「구석의 줄넘기」', 'd': '콩지와 친해진 사이(호감도 4)가 되면 열려요.'},
        },
    },
    # ───────────────────────── 콩지 ─────────────────────────
    {
        'id': 'rabbit', 'ep': 1, 'kind': 'species',
        'name': '콩지', 'label': '콩지 1화', 'title': '구석의 줄넘기',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-jumprope-post',
        'intro': '아무도 없을 때만 시작되는 줄넘기 소리.\n콩지가 처음으로 소리 내어 센 날의 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 운동장 구석에서 콩지가 혼자 줄넘기를 한다',
                'sky': 'morning', 'ground': 22, 'clouds': [CL(52, 26, 22)],
                'props': [PR('hot-jumprope-post', l=4, b=18, w=34, ar=0.8),
                          PR('village-square', l=40, b=8, w=70, far=True)],
                'narr': '따끈마을 운동장 구석.\n아무도 없을 때만 콩지의 줄넘기가 시작된다.',
                'sprites': [SP('rabbit', 14, 44, 26, 'hop')],
                'glow': GL('warm', l=12, t=62, w=30, behind=True),
                'bubbles': [BB('…콩, 콩. 열둘.', 'small', l=42, t=48)],
                'sfx': SFX('탁, 탁', 22, 6, r=6, t=84),
            },
            {
                'aria': '2컷: 누가 오는 소리에 콩지가 줄을 등 뒤로 숨긴다',
                'sky': 'morning', 'ground': 22,
                'props': [PR('hot-jumprope-post', l=4, b=18, w=34, ar=0.8), PR('village-path', l=52, b=4, w=52)],
                'narr': '누가 오는 소리에,\n콩지는 줄을 얼른 등 뒤로 숨겼다.',
                'sprites': [SP('rabbit', 18, 42, 28, 'shiver')],
                'hand': HAND(r=4, b=-8, w=26),
                'bubbles': [BB('…콩?!', 'pop small', l=48, t=38)],
                'sfx': SFX('휙', 26, -8, l=8, t=84),
            },
            {
                'aria': '3컷: 돌봄이가 옆에 앉아 손가락으로 세어 준다',
                'sky': 'high', 'ground': 24,
                'props': [PR('hot-jumprope-post', l=2, b=18, w=30, ar=0.8), PR('stone-yard', l=20, b=-4, w=84)],
                'narr': '돌봄이는 아무 말 없이 옆에 앉아,\n손가락으로 셈만 해 주었다.',
                'sprites': [SP('rabbit', 22, 40, 28)],
                'glow': GL('warm', l=54, b=2, w=42, behind=True),
                'hand': HAND(l=60, b=-2, w=30),
            },
            {
                'aria': '4컷: 콩지가 처음으로 소리 내어 하나, 하고 센다',
                'sky': 'warm', 'ground': 40, 'wide': True,
                'props': [PR('stone-yard', l=10, b=-20, w=80), PR('hot-jumprope-post', l=-4, b=30, w=26, ar=0.8)],
                'glow': GL('flare', l=35, t=58, w=28),
                'sprites': [SP('rabbit', 32, 30, 34, 'hop')],
                'sparks': SPK((26, 30), (70, 28), (24, 54)),
                'bubbles': [BB('…콩, 하나.', 'pop tail-right', r=6, t=10)],
                'narr': NB('콩지의 목소리가, 처음으로 운동장에 퍼졌다.'),
                'sfx': SFX('탁!', 28, 6, r=8, t=62),
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '콩지와 친해진 사이가 됐어요',
            'd': '호감도 4 이상이면 1화가 열려요.',
            'hearts': 4, 'hearts_label': '호감도 친해진 사이',
            'next': {'k': '다음 이야기', 't': '2화 「셋까지 세는 용기」', 'd': '단짝(호감도 7)이 되면 열려요.'},
        },
    },
    {
        'id': 'rabbit', 'ep': 2, 'kind': 'species',
        'name': '콩지', 'label': '콩지 2화', 'title': '셋까지 세는 용기',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-jumprope-post',
        'intro': '모닥이가 같이 넘자고 달려온 날.\n콩지가 셋까지만 세어 본 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 모닥이가 줄 한쪽을 들고 같이 넘자고 한다',
                'sky': 'morning', 'ground': 22,
                'props': [PR('hot-jumprope-post', l=2, b=18, w=32, ar=0.8), PR('village-square', l=36, b=8, w=72, far=True)],
                'narr': '줄넘기 소리가 나자,\n모닥이가 달려왔다.',
                'sprites': [SP('monkey', 58, 36, 26, 'jump'), SP('rabbit', 14, 46, 24)],
                'bubbles': [BB('같이 넘자끽! 일단 해보자끽!', 'pop tail-right', r=4, t=22)],
                'sfx': SFX('타다닥', 22, -6, l=6, t=84),
            },
            {
                'aria': '2컷: 콩지가 귀를 접고 발끝을 꼼지락거린다',
                'sky': 'high', 'ground': 22,
                'props': [PR('hot-jumprope-post', l=2, b=18, w=32, ar=0.8)],
                'narr': '콩지의 귀가 슬금슬금 접혔다.',
                'sprites': [SP('rabbit', 30, 38, 34, 'shiver')],
                'sweat': ['left: 62%; top: 40%;'],
                'bubbles': [BB('…콩, 콩. 틀리면… 어떡해.', 'small', r=4, t=22)],
                'sfx': SFX('꼼지락', 22, 6, l=8, t=84),
            },
            {
                'aria': '3컷: 돌봄이가 손가락 셋을 펴 보인다',
                'sky': 'warm', 'ground': 24,
                'props': [PR('stone-yard', l=6, b=0, w=88), PR('hot-jumprope-post', l=-4, b=20, w=26, ar=0.8)],
                'narr': '돌봄이가 손가락 세 개를 가만히 펴 보였다.\n셋까지만, 이라고.',
                'sprites': [SP('rabbit', 20, 40, 28), SP('monkey', 66, 46, 20)],
                'glow': GL('warm', l=28, b=-14, w=46, behind=True),
                'hand': HAND(l=34, b=-2, w=34),
                'bubbles': [BB('…셋, 까지만?', 'small', l=4, t=28)],
            },
            {
                'aria': '4컷: 콩지가 셋을 넘고 발끝이 따끈해진다',
                'sky': 'warm', 'ground': 40, 'wide': True,
                'props': [PR('stone-yard', l=10, b=-20, w=80)],
                'glow': GL('flare', l=35, t=48, w=28),
                'sprites': [SP('rabbit', 34, 26, 32, 'hop'), SP('monkey', 4, 44, 20)],
                'sparks': SPK((26, 26), (70, 24), (74, 46)),
                'bubbles': [BB('…콩, 콩, 셋!', 'pop tail-right', r=6, t=8), BB('넘었다끽!', 'small', l=4, t=30)],
                'narr': NB('하나, 둘, 셋. 콩지의 발끝이 따끈해졌다.'),
                'sfx': SFX('탁, 탁, 탁!', 22, 6, r=5, t=58),
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '콩지와 단짝이 됐어요',
            'd': '호감도 7 이상이면 2화가 열려요.',
            'hearts': 5, 'hearts_label': '호감도 단짝',
            'next': {'k': '다음 이야기', 't': '3화 「발이 가벼워진 날」', 'd': 'Lv.10(1차 진화)이 되면 열려요.'},
        },
    },
    {
        'id': 'rabbit', 'ep': 3, 'kind': 'species',
        'name': '콩지', 'label': '콩지 3화', 'title': '발이 가벼워진 날',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-jumprope-post',
        'intro': '줄이 없어도 폴짝 뛸 수 있게 된 날.\n귀가 한 뼘 길어진 콩지의 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 줄 없이도 콩지가 폴짝 뛴다',
                'sky': 'morning', 'ground': 22, 'clouds': [CL(60, 28, 22)],
                'props': [PR('stone-yard', l=4, b=-2, w=92), PR('hot-jumprope-post', l=-4, b=22, w=26, ar=0.8)],
                'narr': '오늘은 발이 이상하게 가벼웠다.\n줄이 없어도 폴짝 뛸 수 있을 만큼.',
                'sprites': [SP('rabbit', 32, 24, 33, 'hop', evolved=True, final=True)],
                'bubbles': [BB('…콩? 줄이 없는데… 콩, 콩!', 'small', l=4, t=72)],
                'sfx': SFX('폴짝', 24, 6, r=6, t=84),
            },
            {
                'aria': '2컷: 놀란 콩지의 귀가 쫑긋 선다',
                'sky': 'high', 'ground': 22,
                'props': [PR('stone-yard', l=4, b=-2, w=92)],
                'narr': '놀란 귀가 쫑긋,\n하늘을 향해 섰다.',
                'sprites': [SP('rabbit', 30, 36, 36, 'pop', evolved=True, final=True)],
                'sparks': SPK((24, 32), (68, 30)),
                'bubbles': [BB('…콩?! 나, 나 뛰었어?', 'pop tail-right', r=4, t=22)],
                'sfx': SFX('쫑긋', 24, -6, l=8, t=84),
            },
            {
                'aria': '3컷: 친구들이 짝짝짝 박수를 친다',
                'sky': 'warm', 'ground': 30, 'wide': True,
                'props': [PR('village-square', l=-6, b=14, w=92)],
                'sprites': [SP('rabbit', 36, 34, 28, 'shiver', evolved=True, final=True),
                            SP('monkey', 6, 46, 22, 'hop'), SP('chicken', 72, 46, 22)],
                'glow': GL('warm', r=4, b=-8, w=30),
                'bubbles': [BB('대단하다끽!', 'pop', l=3, t=26), BB('꼬오— 멋지다… 하아암.', 'small', r=3, t=26)],
                'narr': NB('지켜보던 친구들이 짝짝짝, 박수를 쳤다.'),
                'sfx': SFX('짝짝짝', 24, -4, l=34, t=16),
            },
            {
                'aria': '4컷: 귀가 한 뼘 길어진 콩지가 수줍게 인사한다',
                'sky': 'warm', 'ground': 40,
                'props': [PR('hot-sunrise-hill', l=0, b=24, w=100, ar=3.2, fb=('stone-yard', 10, 14, 80))],
                'glow': GL('flare', l=36, t=22, w=28),
                'sprites': [SP('rabbit', 30, 30, 40, 'hop', evolved=True, final=True)],
                'sparks': SPK((22, 30), (74, 28), (20, 54)),
                'bubbles': [BB('…콩, 콩. 안녕… 이제, 같이 넘자.', 'pop tail-right', r=4, t=20)],
                'narr': '귀가 한 뼘 길어진 콩지가,\n수줍게 인사했다.',
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '콩지가 1차 진화했어요',
            'd': 'Lv.10이 되면 3화가 열려요. 콩지 이야기는 여기까지예요.',
            'next': {'k': '다음 이야기', 't': '홰치 1화 「졸린 새벽 알람」', 'd': '홰치와 친해진 사이(호감도 4)가 되면 열려요.'},
        },
    },
    # ───────────────────────── 홰치 ─────────────────────────
    {
        'id': 'chicken', 'ep': 1, 'kind': 'species',
        'name': '홰치', 'label': '홰치 1화', 'title': '졸린 새벽 알람',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-roost-perch',
        'intro': '해 뜨기 전, 마을에서 제일 먼저 일어나는 홰치.\n아무도 안 일어난 새벽의 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 해 뜨기 전에 홰치가 횃대 위에서 크게 외친다',
                'sky': 'dusk', 'ground': 22, 'clouds': [CL(10, 30, 22)],
                'props': [PR('hot-roost-perch', l=28, b=14, w=44, ar=1.4),
                          PR('village-square', l=-8, b=6, w=80, far=True)],
                'narr': '아직 해도 뜨기 전.\n홰치는 마을에서 제일 먼저 일어났다.',
                'lines': LN(62, 30, 22, 18, 30),
                'sprites': [SP('chicken', 34, 24, 30, 'pop')],
                'bubbles': [BB('꼬오—! 아침이다—!', 'pop tail-right', r=4, t=30)],
                'sfx': SFX('꼬오오—!', 24, 6, l=6, t=84),
            },
            {
                'aria': '2컷: 마을은 조용한데 홰치만 하품을 한다',
                'sky': 'dusk', 'ground': 22,
                'props': [PR('village-square', l=-6, b=6, w=92), PR('village-path', l=60, b=4, w=36, far=True)],
                'narr': '마을은 쿨쿨 조용한데,\n깨운 홰치만 하품이 나왔다.',
                'sprites': [SP('chicken', 30, 36, 32, 'shiver')],
                'bubbles': [BB('하아암… 아무도 안 일어났네…', 'small', r=4, t=24)],
                'sfx': SFX('하아암', 24, -6, l=6, t=84),
            },
            {
                'aria': '3컷: 돌봄이가 손짓으로 조용히 인사한다',
                'sky': 'dusk', 'ground': 22,
                'props': [PR('hot-roost-perch', l=4, b=14, w=36, ar=1.4), PR('stone-yard', l=20, b=-6, w=84)],
                'narr': '돌봄이가 작은 손짓으로\n조용히 인사해 주었다.',
                'sprites': [SP('chicken', 18, 38, 30)],
                'glow': GL('warm', l=46, b=-14, w=52, behind=True),
                'hand': HAND(l=56, b=-2, w=30),
                'bubbles': [BB('…꼬? 오…', 'small', l=46, t=30)],
            },
            {
                'aria': '4컷: 첫 해가 올라오고 둘이 같이 본다',
                'sky': 'warm', 'ground': 30, 'wide': True,
                'props': [PR('hot-sunrise-hill', l=0, b=24, w=100, ar=3.2, fb=('stone-yard', 10, 14, 80))],
                'glow': [GL('flare', l=40, t=8, w=26, behind=True), GL('warm', r=10, b=14, w=22)],
                'sprites': [SP('chicken', 26, 40, 28)],
                'sparks': SPK((22, 36), (62, 34), (64, 56)),
                'bubbles': [BB('꼬오… 같이 보니까 더 예쁘다.', 'pop tail-right', r=4, t=44)],
                'narr': '그제야 첫 해가 올라왔다.\n둘은 가만히 같이 보았다.',
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '홰치와 친해진 사이가 됐어요',
            'd': '호감도 4 이상이면 1화가 열려요.',
            'hearts': 4, 'hearts_label': '호감도 친해진 사이',
            'next': {'k': '다음 이야기', 't': '2화 「깨워 주는 쪽」', 'd': '단짝(호감도 7)이 되면 열려요.'},
        },
    },
    {
        'id': 'chicken', 'ep': 2, 'kind': 'species',
        'name': '홰치', 'label': '홰치 2화', 'title': '깨워 주는 쪽',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-roost-perch',
        'intro': '오늘은 알람이 울리지 않았어요.\n깨워 주는 쪽이 깨워진 아침의 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 해가 중천인데 홰치가 늦잠을 잔다',
                'sky': 'high', 'ground': 22, 'clouds': [CL(8, 14, 24), CL(58, 24, 20)],
                'props': [PR('hot-roost-perch', l=26, b=14, w=46, ar=1.4),
                          PR('village-square', l=-8, b=6, w=80, far=True)],
                'narr': '해가 높이 떠도,\n오늘은 알람이 울리지 않았다.',
                'sprites': [SP('chicken', 34, 40, 30, 'warm', rot=-70)],
                'bubbles': [BB('꼬… 오… 쿨…', 'small', r=4, t=36)],
                'sfx': SFX('zZ…', 26, -6, l=58, t=30),
            },
            {
                'aria': '2컷: 돌봄이가 살그머니 깃털을 두드려 깨운다',
                'sky': 'high', 'ground': 22,
                'props': [PR('hot-roost-perch', l=8, b=14, w=40, ar=1.4), PR('stone-yard', l=24, b=-6, w=80)],
                'narr': '돌봄이가 살그머니,\n깃털을 톡톡 두드려 깨웠다.',
                'sprites': [SP('chicken', 18, 42, 28, rot=-40)],
                'glow': GL('warm', l=42, b=-14, w=56, behind=True),
                'hand': HAND(l=52, b=-2, w=32),
                'bubbles': [BB('꼬…? 하아암…', 'small', l=48, t=32)],
                'sfx': SFX('톡톡', 22, 6, l=6, t=84),
            },
            {
                'aria': '3컷: 벌떡 일어난 홰치가 날개로 얼굴을 가린다',
                'sky': 'warm', 'ground': 22,
                'props': [PR('hot-roost-perch', l=30, b=14, w=42, ar=1.4)],
                'narr': '깨워 주는 쪽이 깨워졌다.\n홰치는 얼굴이 빨개졌다.',
                'sprites': [SP('chicken', 32, 30, 34, 'pop')],
                'glow': GL('warm', l=26, t=24, w=48, behind=True),
                'bubbles': [BB('내가 깨워야 하는데… 꼬, 꼬오… 하아암.', 'pop tail-right', r=4, t=20)],
                'sfx': SFX('파닥', 24, -6, l=6, t=84),
            },
            {
                'aria': '4컷: 둘이 같이 꼬오— 하고 아침을 부른다',
                'sky': 'warm', 'ground': 30, 'wide': True,
                'props': [PR('hot-sunrise-hill', l=0, b=24, w=100, ar=3.2, fb=('stone-yard', 10, 14, 80))],
                'glow': GL('warm', r=8, b=14, w=24),
                'lines': LN(60, 30, 22, 18, 30),
                'sprites': [SP('chicken', 32, 34, 32, 'hop')],
                'sparks': SPK((24, 32), (70, 30), (26, 56)),
                'bubbles': [BB('꼬오—! 같이 하니까 졸리지 않다!', 'pop tail-right', r=4, t=6)],
                'narr': NB('이번에는 둘이 함께, 아침을 불렀다.'),
                'sfx': SFX('꼬오오—!', 22, 6, r=6, t=58),
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '홰치와 단짝이 됐어요',
            'd': '호감도 7 이상이면 2화가 열려요.',
            'hearts': 5, 'hearts_label': '호감도 단짝',
            'next': {'k': '다음 이야기', 't': '3화 「깃털이 따뜻해진 날」', 'd': 'Lv.10(1차 진화)이 되면 열려요.'},
        },
    },
    {
        'id': 'chicken', 'ep': 3, 'kind': 'species',
        'name': '홰치', 'label': '홰치 3화', 'title': '깃털이 따뜻해진 날',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-sunrise-hill',
        'intro': '오늘도 제일 먼저 외치던 아침, 목이 간질간질했어요.\n홰치의 깃털이 노을처럼 달아오른 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 외치다 목이 간지러운 홰치',
                'sky': 'dusk', 'ground': 22,
                'props': [PR('hot-roost-perch', l=26, b=14, w=46, ar=1.4),
                          PR('village-square', l=-8, b=6, w=80, far=True)],
                'narr': '오늘도 제일 먼저 외치는데,\n목이 간질간질했다.',
                'sprites': [SP('chicken', 34, 26, 30, 'shiver')],
                'bubbles': [BB('꼬오— 꼬, 콜록… 목이 간질간질…', 'pop tail-right', r=4, t=36)],
                'sfx': SFX('간질간질', 22, -6, l=6, t=84),
            },
            {
                'aria': '2컷: 홰치의 깃털 끝이 붉게 달아오른다',
                'sky': 'morning', 'ground': 22,
                'props': [PR('hot-roost-perch', l=26, b=14, w=46, ar=1.4)],
                'narr': '깃털 끝이\n노을처럼 붉게 달아올랐다.',
                'sprites': [SP('chicken', 30, 28, 36, evolved=True)],
                'glow': [GL('warm', l=24, t=18, w=52, behind=True), GL('flare', l=60, t=36, w=18)],
                'sparks': SPK((24, 30), (72, 28), (22, 58)),
                'bubbles': [BB('꼬…? 깃털이 따뜻해… 하아암.', 'small', r=4, t=22)],
                'sfx': SFX('후끈', 24, 6, l=8, t=84),
            },
            {
                'aria': '3컷: 양옆의 문이 열리고 모닥이와 콩지가 나온다',
                'sky': 'morning', 'ground': 30, 'wide': True,
                'props': [PR('village-square', l=-6, b=14, w=92), PR('village-path', l=60, b=6, w=40)],
                'glow': GL('warm', l=22, t=16, w=56, behind=True),
                'sprites': [SP('chicken', 36, 40, 26, 'hop', evolved=True),
                            SP('monkey', 4, 48, 20), SP('rabbit', 74, 48, 20)],
                'bubbles': [BB('일어났다끽!', 'small', l=3, t=32), BB('…콩, 콩. 포근한 소리.', 'small', r=3, t=32)],
                'narr': NB('따뜻한 빛에 하나둘, 마을의 문이 열렸다.'),
                'sfx': SFX('끼익', 22, -6, l=40, t=18),
            },
            {
                'aria': '4컷: 더 크고 맑은 꼬오—가 마을에 퍼진다',
                'sky': 'warm', 'ground': 30,
                'props': [PR('hot-sunrise-hill', l=0, b=24, w=100, ar=3.2, fb=('stone-yard', 10, 14, 80))],
                'glow': [GL('flare', l=60, t=26, w=26, behind=True)],
                'lines': LN(66, 30, 24, 18, 30),
                'sprites': [SP('chicken', 28, 30, 40, 'pop', evolved=True)],
                'bubbles': [BB('꼬오오—! 오늘도 좋은 아침이다—! 하아암.', 'pop tail-right', r=4, t=18)],
                'narr': '더 크고 맑은 꼬오—가,\n마을 끝까지 퍼졌다.',
                'sfx': SFX('꼬오오오—!', 22, 6, l=6, t=86),
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '홰치가 1차 진화했어요',
            'd': 'Lv.10이 되면 3화가 열려요. 홰치 이야기는 여기까지예요.',
            'next': {'k': '다음 이야기', 't': '길쭉 1화 「쭈우우욱」', 'd': '길쭉과 친해진 사이(호감도 4)가 되면 열려요.'},
        },
    },
    # ───────────────────────── 길쭉 ─────────────────────────
    {
        'id': 'anaconda', 'ep': 1, 'kind': 'species',
        'name': '길쭉', 'label': '길쭉 1화', 'title': '쭈우우욱',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-warm-rock',
        'intro': '따뜻한 바위 위에 길게 늘어진 길쭉.\n서두를 일이 없는 아침의 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 따뜻한 바위 위에 길쭉이 길게 늘어져 있다',
                'sky': 'morning', 'ground': 24, 'wide': True, 'clouds': [CL(6, 18, 22), CL(60, 10, 18)],
                'props': [PR('hot-warm-rock', l=12, b=10, w=76, ar=1.6, fb=('stone-yard', 12, 6, 76)),
                          PR('village-path', l=-8, b=4, w=50, far=True)],
                'narr': '따끈마을의 따뜻한 바위 위.\n길쭉은 오늘도 길게 늘어져 있었다.',
                'sprites': [SP('anaconda', 20, 32, 56)],
                'glow': GL('warm', l=36, t=6, w=30, behind=True),
                'bubbles': [BB('쭈우우욱… 아직 아침이네…', 'small', r=4, t=62)],
                'sfx': SFX('모락모락', 22, 6, r=6, t=22),
            },
            {
                'aria': '2컷: 돌봄이가 바위 옆에서 몸을 쭉 편다',
                'sky': 'morning', 'ground': 24,
                'props': [PR('hot-warm-rock', l=-4, b=12, w=80, ar=1.6, fb=('stone-yard', -4, 8, 80))],
                'narr': '돌봄이가 바위 옆에서\n두 팔을 위로 쭉 폈다.',
                'sprites': [SP('anaconda', 24, 36, 52)],
                'glow': GL('warm', l=54, b=-6, w=50, behind=True),
                'hand': HAND(l=62, b=4, w=30),
                'bubbles': [BB('…뭐 하는 거야?', 'small', l=6, t=26)],
                'sfx': SFX('쭈욱', 24, -6, r=6, t=84),
            },
            {
                'aria': '3컷: 길쭉이 아주 천천히 같은 모양으로 몸을 편다',
                'sky': 'high', 'ground': 24,
                'props': [PR('hot-warm-rock', l=-4, b=12, w=80, ar=1.6, fb=('stone-yard', -4, 8, 80))],
                'narr': '길쭉은 아주 천천히,\n같은 모양으로 몸을 폈다.',
                'sprites': [SP('anaconda', 24, 14, 52, 'reach')],
                'sparks': SPK((26, 40), (50, 32), (70, 44)),
                'hand': HAND(l=70, b=4, w=24),
                'bubbles': [BB('쭈우우욱… 이렇게…?', 'pop small', l=4, t=62)],
                'sfx': SFX('쭈우우욱…', 22, -6, r=4, t=84),
            },
            {
                'aria': '4컷: 눈을 가늘게 뜬 길쭉이 천천히 해도 돼, 하고 말한다',
                'sky': 'warm', 'ground': 30,
                'props': [PR('hot-warm-rock', l=8, b=10, w=84, ar=1.6, fb=('stone-yard', 8, 6, 84))],
                'glow': GL('warm', l=14, t=22, w=72, behind=True),
                'sprites': [SP('anaconda', 26, 36, 48)],
                'hand': HAND(r=4, b=-4, w=22),
                'bubbles': [BB('…천천히 해도 돼. 같이 쭈우우욱.', 'pop tail-right', l=22, t=22)],
                'narr': '길쭉이 눈을 가늘게 뜨고 웃었다.\n서두를 일이 없는 아침이었다.',
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '길쭉과 친해진 사이가 됐어요',
            'd': '호감도 4 이상이면 1화가 열려요.',
            'hearts': 4, 'hearts_label': '호감도 친해진 사이',
            'next': {'k': '다음 이야기', 't': '2화 「매듭 풀기」', 'd': '단짝(호감도 7)이 되면 열려요.'},
        },
    },
    {
        'id': 'anaconda', 'ep': 2, 'kind': 'species',
        'name': '길쭉', 'label': '길쭉 2화', 'title': '매듭 풀기',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-stretch-mat',
        'intro': '욕심내서 한 뼘 더 길게 펴 보던 날.\n꼬여 버린 몸을 풀어 준 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 길쭉이 몸을 크게 꼬아 펴 본다',
                'sky': 'morning', 'ground': 28, 'wide': True,
                'props': [PR('hot-stretch-mat', l=10, b=8, w=80, ar=2.5, fb=('stone-yard', 10, 4, 80)),
                          PR('stone-yard', l=-10, b=2, w=50, far=True)],
                'narr': '오늘은 평소보다\n한 뼘 더 길게 펴 보기로 했다.',
                'sprites': [SP('anaconda', 18, 30, 58, 'reach')],
                'bubbles': [BB('쭈우우욱… 오늘은 더 길게…!', 'pop tail-right', r=4, t=62)],
                'sfx': SFX('쭈욱쭈욱', 22, -6, r=6, t=20),
            },
            {
                'aria': '2컷: 길쭉의 몸이 매듭처럼 엉켜 버린다',
                'sky': 'morning', 'ground': 28,
                'props': [PR('hot-stretch-mat', l=4, b=8, w=90, ar=2.5, fb=('stone-yard', 4, 4, 90))],
                'narr': '그런데 몸이\n매듭처럼 엉켜 버렸다.',
                'sprites': [SP('anaconda', 20, 34, 56, 'shiver')],
                'sweat': ['left: 72%; top: 38%;'],
                'bubbles': [BB('쭈…쭈우…? 어…', 'small', l=6, t=26)],
                'sfx': SFX('꼬옥', 24, 6, r=6, t=84),
            },
            {
                'aria': '3컷: 길쭉이 얼굴이 빨개져 눈을 질끈 감고 돌봄이가 손을 내민다',
                'sky': 'high', 'ground': 28,
                'props': [PR('hot-stretch-mat', l=4, b=8, w=90, ar=2.5, fb=('stone-yard', 4, 4, 90))],
                'narr': '길쭉은 눈을 질끈 감았다.\n돌봄이는 가만히 손을 내밀었다.',
                'sprites': [SP('anaconda', 24, 36, 50)],
                'glow': GL('warm', l=54, b=-8, w=50, behind=True),
                'hand': HAND(l=62, b=2, w=30),
                'bubbles': [BB('…보지 마. 부끄러워…', 'small', l=6, t=26)],
            },
            {
                'aria': '4컷: 매듭이 풀리고 둘이 같이 쭈우욱 편다',
                'sky': 'warm', 'ground': 30, 'wide': True,
                'props': [PR('hot-stretch-mat', l=10, b=8, w=80, ar=2.5, fb=('stone-yard', 10, 4, 80))],
                'sprites': [SP('anaconda', 16, 28, 60, 'reach')],
                'sparks': SPK((22, 30), (46, 22), (70, 30), (84, 44)),
                'hand': HAND(r=8, b=-2, w=22),
                'bubbles': [BB('쭈우욱… 풀렸다. 고마워. 천천히 해도 되는 거였네.', 'pop tail-right', r=4, t=62)],
                'narr': '한쪽씩 살살 풀자,\n둘이 같이 웃으며 쭈우욱 폈다.',
                'sfx': SFX('후르륵', 22, -6, r=6, t=40),
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '길쭉과 단짝이 됐어요',
            'd': '호감도 7 이상이면 2화가 열려요.',
            'hearts': 5, 'hearts_label': '호감도 단짝',
            'next': {'k': '다음 이야기', 't': '3화 「더 길고 따뜻하게」', 'd': 'Lv.10(1차 진화)이 되면 열려요.'},
        },
    },
    {
        'id': 'anaconda', 'ep': 3, 'kind': 'species',
        'name': '길쭉', 'label': '길쭉 3화', 'title': '더 길고 따뜻하게',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-warm-rock',
        'intro': '어느 날 아침, 몸속이 근질근질했어요.\n길쭉이 더 길어진 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 몸이 근질근질해 부르르 떠는 길쭉',
                'sky': 'morning', 'ground': 24,
                'props': [PR('hot-warm-rock', l=8, b=10, w=84, ar=1.6, fb=('stone-yard', 8, 6, 84))],
                'narr': '어느 날 아침,\n몸속이 근질근질했다.',
                'sprites': [SP('anaconda', 22, 30, 52, 'shiver')],
                'sparks': SPK((30, 40), (50, 34), (68, 42)),
                'bubbles': [BB('쭈…? 몸이 근질근질해…', 'small', r=4, t=64)],
                'sfx': SFX('근질근질', 22, -6, l=6, t=84),
            },
            {
                'aria': '2컷: 한 뼘 더 길어져 놀라 똬리를 튼 길쭉',
                'sky': 'high', 'ground': 28, 'wide': True,
                'props': [PR('hot-warm-rock', l=10, b=8, w=80, ar=1.6, fb=('stone-yard', 10, 4, 80))],
                'sprites': [SP('anaconda', 16, 22, 62, 'pop', evolved=True, final=True)],
                'glow': GL('flare', l=50, t=24, w=28),
                'bubbles': [BB('쭈우욱…?! 더 길어졌어…!', 'pop tail-right', r=4, t=6)],
                'narr': NB('몸이 한 뼘 더 길어져서,\n길쭉도 깜짝 놀랐다.'),
                'sfx': SFX('쭈우욱!', 24, 6, r=6, t=60),
            },
            {
                'aria': '3컷: 모닥이와 콩지가 길쭉의 몸 위에 올라 앉는다',
                'sky': 'warm', 'ground': 30, 'wide': True,
                'props': [PR('stone-yard', l=6, b=4, w=88)],
                'sprites': [SP('anaconda', 14, 36, 62, evolved=True, final=True),
                            SP('monkey', 30, 18, 16, 'hop'), SP('rabbit', 52, 22, 16)],
                'bubbles': [BB('넓다끽! 포근하다끽!', 'small', l=3, t=4), BB('…콩, 콩. 따뜻해.', 'small', r=3, t=12)],
                'narr': NB('마을 친구들이 하나둘,\n길쭉의 넓은 몸에 올라 앉았다.'),
                'sfx': SFX('폴짝', 22, -6, l=10, t=44),
            },
            {
                'aria': '4컷: 길쭉이 모두를 태우고 천천히 한 바퀴 돈다',
                'sky': 'warm', 'ground': 30, 'wide': True,
                'props': [PR('stone-yard', l=6, b=4, w=88), PR('village-square', l=52, b=10, w=46, far=True)],
                'glow': GL('warm', l=10, t=40, w=66, behind=True),
                'sprites': [SP('anaconda', 12, 38, 64, evolved=True, final=True),
                            SP('monkey', 28, 22, 14), SP('rabbit', 48, 26, 14)],
                'bubbles': [BB('쭈우우욱… 천천히 한 바퀴. 같이 가자.', 'pop tail-right', r=4, t=4)],
                'narr': NB('길쭉은 넓은 몸으로 모두를 태우고,\n천천히 한 바퀴 돌았다.'),
                'sfx': SFX('스르르', 22, -6, r=6, t=62),
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '길쭉이 1차 진화했어요',
            'd': 'Lv.10이 되면 3화가 열려요. 길쭉 이야기는 여기까지예요.',
            'next': {'k': '다음 이야기', 't': '놀빛 1화 「접힌 깃털」', 'd': '놀빛과 친해진 사이(호감도 4)가 되면 열려요.'},
        },
    },
    # ───────────────────────── 놀빛 ─────────────────────────
    {
        'id': 'peacock', 'ep': 1, 'kind': 'species',
        'name': '놀빛', 'label': '놀빛 1화', 'title': '접힌 깃털',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-sunset-ridge',
        'intro': '노을이 지는 따끈마을, 깃을 꼭 접고 돌아선 놀빛.\n깃을 딱 한 줄 펴 본 저녁의 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 놀빛이 깃을 꼭 접고 돌아서 있다',
                'sky': 'dusk', 'ground': 24, 'clouds': [CL(8, 14, 24), CL(58, 26, 20)],
                'props': [PR('hot-sunset-ridge', l=-6, b=14, w=112, ar=3.2)],
                'narr': '노을이 지는 따끈마을.\n놀빛은 깃을 꼭 접은 채 돌아서 있었다.',
                'sprites': [SP('peacock', 14, 38, 28, 'shiver', flip=True)],
                'bubbles': [BB('…', 'small', l=46, t=44)],
            },
            {
                'aria': '2컷: 돌봄이의 손 그림자가 놀빛 곁에서 같이 노을을 본다',
                'sky': 'dusk', 'ground': 24, 'wide': True,
                'props': [PR('hot-sunset-ridge', l=0, b=12, w=100, ar=3.2)],
                'narr': '돌봄이는 아무 말 없이\n곁에서 같이 노을을 보았다.',
                'sprites': [SP('peacock', 22, 40, 26)],
                'glow': GL('warm', l=50, b=0, w=44, behind=True),
                'hand': HAND(l=60, b=-2, w=28),
                'bubbles': [BB('…저기, 뭘 보는 거야?', 'small', r=3, t=30)],
            },
            {
                'aria': '3컷: 놀빛이 깃을 딱 한 줄만 펴 보인다',
                'sky': 'dusk', 'ground': 24,
                'props': [PR('hot-sunset-ridge', l=-6, b=14, w=112, ar=3.2)],
                'narr': '놀빛이 용기를 내어\n깃을 딱 한 줄만 펴 보였다.',
                'sprites': [SP('peacock', 30, 36, 34, 'reach')],
                'sparks': SPK((60, 34)),
                'bubbles': [BB('…조금만 봐도 돼.', 'pop small', r=4, t=24)],
                'sfx': SFX('사락', 22, -6, l=6, t=84),
            },
            {
                'aria': '4컷: 펴진 깃에서 노을색이 몸 전체로 번진다',
                'sky': 'warm', 'ground': 24, 'wide': True,
                'props': [PR('hot-sunset-ridge', l=0, b=12, w=100, ar=3.2)],
                'glow': GL('flare', l=26, t=24, w=42, behind=True),
                'sprites': [SP('peacock', 28, 36, 36)],
                'bubbles': [BB('…예쁘다고 해 줘서 고마워. 조금만 더 봐도 돼.', 'pop tail-right', r=3, t=4)],
                'narr': NB('노을색이 깃을 따라, 천천히 번졌다.'),
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '놀빛과 친해진 사이가 됐어요',
            'd': '호감도 4 이상이면 1화가 열려요.',
            'hearts': 4, 'hearts_label': '호감도 친해진 사이',
            'next': {'k': '다음 이야기', 't': '2화 「칭찬 한마디」', 'd': '단짝(호감도 7)이 되면 열려요.'},
        },
    },
    {
        'id': 'peacock', 'ep': 2, 'kind': 'species',
        'name': '놀빛', 'label': '놀빛 2화', 'title': '칭찬 한마디',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-sunset-ridge',
        'intro': '아무도 없을 때 몰래 깃 펴는 연습을 하던 놀빛.\n돌봄이의 한마디가 깃을 활짝 열어 준 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 놀빛이 혼자 깃 펴는 연습을 한다',
                'sky': 'warm', 'ground': 26,
                'props': [PR('hot-sunset-ridge', l=-10, b=20, w=70, far=True, ar=3.2), PR('stone-yard', l=8, b=4, w=84)],
                'narr': '놀빛은 아무도 없을 때\n몰래 깃 펴는 연습을 했다.',
                'sprites': [SP('peacock', 30, 34, 36, 'reach')],
                'bubbles': [BB('…하나, 둘. 이번엔 잘 펴질 거야.', 'small', r=3, t=26)],
                'sfx': SFX('사락사락', 22, -6, l=6, t=86),
            },
            {
                'aria': '2컷: 깃이 꼬여 속상한 놀빛',
                'sky': 'warm', 'ground': 26,
                'props': [PR('stone-yard', l=8, b=4, w=84)],
                'narr': '깃이 그만 꼬여 버렸다.\n놀빛은 속상했다.',
                'sprites': [SP('peacock', 30, 36, 36, 'shiver')],
                'sweat': ['left: 62%; top: 40%;'],
                'bubbles': [BB('…또 꼬였어. 역시 안 되나 봐.', 'small', r=3, t=26)],
                'sfx': SFX('후우…', 24, -6, l=6, t=84),
            },
            {
                'aria': '3컷: 돌봄이가 엄지를 세우고 하트 빛이 떠오른다',
                'sky': 'dusk', 'ground': 26,
                'props': [PR('hot-sunset-ridge', l=-6, b=14, w=112, ar=3.2)],
                'narr': '돌봄이가 엄지를 들며 말해 주었다.\n"정말 예쁘다."',
                'sprites': [SP('peacock', 26, 36, 38)],
                'glow': GL('warm', l=58, b=14, w=34),
                'hand': HAND(l=62, b=2, w=30),
                'bubbles': [BB('…!', 'pop small', l=6, t=26)],
            },
            {
                'aria': '4컷: 얼굴이 빨개진 놀빛이 깃을 활짝 펴고 둘이 웃는다',
                'sky': 'warm', 'ground': 30, 'wide': True,
                'props': [PR('hot-sunset-ridge', l=0, b=12, w=100, ar=3.2)],
                'glow': GL('flare', l=22, t=14, w=50, behind=True),
                'sprites': [SP('peacock', 20, 24, 52, 'pop')],
                'sparks': SPK((20, 20), (36, 12), (52, 8), (68, 14), (80, 24)),
                'hand': HAND(r=4, b=-4, w=22),
                'bubbles': [BB('앗…! 펴 버렸다…! …봐도 돼. 조금만.', 'pop tail-right', r=3, t=62),
                            BB('깔깔!', 'small', l=4, t=48)],
                'narr': {'text': '놀라서 둘 다 깔깔 웃었다.\n노을이 둘의 웃음을 비췄다.', 'style': 'left: 10px; top: 10px;'},
                'sfx': SFX('와락!', 24, 6, r=8, t=44),
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '놀빛과 단짝이 됐어요',
            'd': '호감도 7 이상이면 2화가 열려요.',
            'hearts': 5, 'hearts_label': '호감도 단짝',
            'next': {'k': '다음 이야기', 't': '3화 「노을 깃」', 'd': 'Lv.10(1차 진화)이 되면 열려요.'},
        },
    },
    {
        'id': 'peacock', 'ep': 3, 'kind': 'species',
        'name': '놀빛', 'label': '놀빛 3화', 'title': '노을 깃',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-sunset-ridge',
        'intro': '깃 끝이 노을색으로 물든 저녁.\n친구들 앞에 선 놀빛의 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 접힌 깃 끝이 노을색으로 물든다',
                'sky': 'dusk', 'ground': 26,
                'props': [PR('hot-sunset-ridge', l=-6, b=14, w=112, ar=3.2)],
                'narr': '어느 저녁,\n깃 끝이 노을색으로 물들었다.',
                'sprites': [SP('peacock', 28, 34, 38)],
                'glow': GL('flare', l=56, t=40, w=20),
                'bubbles': [BB('…어? 깃 끝이 따뜻해…', 'small', r=3, t=24)],
                'sfx': SFX('후끈', 24, 6, l=6, t=84),
            },
            {
                'aria': '2컷: 친구들이 기다리지만 놀빛은 한 걸음 물러선다',
                'sky': 'dusk', 'ground': 28, 'wide': True,
                'props': [PR('village-square', l=-6, b=8, w=92)],
                'sprites': [SP('peacock', 60, 36, 28, 'shiver', evolved=True, final=True),
                            SP('monkey', 6, 46, 14), SP('rabbit', 26, 48, 14)],
                'bubbles': [BB('…다들 보고 있어… 못 하겠어.', 'small', r=3, t=18)],
                'narr': NB('모두가 기다리고 있었지만,\n놀빛은 한 걸음 물러섰다.'),
                'sfx': SFX('사박', 22, -6, l=34, t=62),
            },
            {
                'aria': '3컷: 돌봄이의 손 그림자가 놀빛의 등을 받쳐 준다',
                'sky': 'dusk', 'ground': 26,
                'props': [PR('hot-sunset-ridge', l=-6, b=14, w=112, ar=3.2)],
                'narr': '돌봄이의 손 그림자가\n놀빛의 등을 가만히 받쳐 주었다.',
                'sprites': [SP('peacock', 24, 34, 40, evolved=True, final=True, flip=True)],
                'glow': GL('warm', l=4, b=-10, w=50, behind=True),
                'hand': HAND(l=12, b=2, w=34),
                'bubbles': [BB('…', 'small', r=8, t=44)],
            },
            {
                'aria': '4컷: 놀빛이 천천히 깃을 펴자 마을이 노을빛으로 환해진다',
                'sky': 'warm', 'ground': 30, 'wide': True,
                'props': [PR('village-square', l=-6, b=8, w=92),
                          PR('hot-sunset-ridge', l=40, b=24, w=58, far=True, ar=3.2)],
                'glow': GL('flare', l=18, t=12, w=64, behind=True),
                'sprites': [SP('peacock', 24, 20, 52, evolved=True, final=True),
                            SP('monkey', 4, 56, 14, 'hop'), SP('rabbit', 80, 56, 14)],
                'bubbles': [BB('…봐도 돼. 이번엔 오래 봐도 돼.', 'pop tail-right', r=3, t=3),
                            BB('멋있다끽!', 'small', l=3, t=44)],
                'narr': NB('놀빛이 천천히 깃을 펴자,\n마을이 노을빛으로 환해졌다.'),
                'sfx': SFX('사아아—', 22, -6, r=6, t=66),
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '놀빛이 1차 진화했어요',
            'd': 'Lv.10이 되면 3화가 열려요. 놀빛 이야기는 여기까지예요.',
            'next': {'k': '마을 이야기', 't': '따끈마을 1장 「식어 가는 운동장」', 'd': '따끈마을 친구를 1종 만나면 열려요.'},
        },
    },
    # ───────────────────────── 따끈마을 장 ─────────────────────────
    {
        'id': 'village-hot', 'ep': 1, 'kind': 'chapter',
        'name': '따끈마을', 'label': '따끈마을 1장', 'title': '식어 가는 운동장',
        'village': '따끈마을 · 운동', 'cover_prop': 'stone-yard',
        'intro': '오늘은 돌바닥이 따뜻하지 않아서\n모두 이불에서 나오지 못한 아침의 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 차가운 돌바닥, 이불 속의 주민들이 실루엣으로 보인다',
                'sky': 'morning', 'ground': 30, 'wide': True,
                'props': [PR('village-square', l=-8, b=22, w=60, far=True), PR('stone-yard', l=6, b=4, w=88)],
                'glow': {'cls': '', 'behind': True,
                         'style': 'left: 0; top: 46%; width: 100%; height: 54%; border-radius: 0; z-index: 0; '
                                  'background: linear-gradient(rgba(120,170,255,0), rgba(120,170,255,.38));'},
                'sprites': [SIL('monkey', 8, 14, 14, 'shiver'), SIL('rabbit', 24, 14, 14), SIL('chicken', 40, 14, 14, 'shiver'),
                            SIL('anaconda', 58, 14, 14), SIL('peacock', 76, 14, 14, 'shiver')],
                'bubbles': [BB('으… 추워… 조금만 더…', 'small', l=4, t=40)],
                'narr': NB('따끈마을의 돌바닥이 오늘은 따뜻하지 않았다.\n모두 이불에서 나오지 못했다.'),
                'sfx': SFX('으슬으슬', 22, 6, r=6, t=48),
            },
            {
                'aria': '2컷: 돌봄이의 손 그림자가 운동장 한가운데서 첫 스트레칭을 한다',
                'sky': 'morning', 'ground': 30,
                'props': [PR('stone-yard', l=4, b=4, w=92)],
                'narr': '돌봄이가 운동장 한가운데에서,\n첫 스트레칭을 했다.',
                'glow': GL('warm', l=26, b=-8, w=50, behind=True),
                'hand': HAND(l=32, b=0, w=38),
                'sfx': SFX('쭈욱', 26, -6, r=8, t=60),
            },
            {
                'aria': '3컷: 발밑의 돌바닥 한 칸이 붉게 달아오르며 김이 난다',
                'sky': 'warm', 'ground': 36,
                'props': [PR('stone-yard', l=0, b=-10, w=100)],
                'narr': '발밑의 돌이\n조금씩 데워지기 시작했다.',
                'glow': GL('flare', l=32, t=46, w=36),
                'sparks': SPK((28, 50), (66, 46), (24, 68), (72, 66)),
                'hand': HAND(r=2, b=-6, w=22),
                'sfx': SFX('모락모락', 24, 6, l=8, t=84),
            },
            {
                'aria': '4컷: 문이 열리고 주민들이 한 마리씩 얼굴을 내민다',
                'sky': 'morning', 'ground': 30, 'wide': True,
                'props': [PR('village-square', l=-6, b=8, w=92), PR('stone-yard', l=20, b=0, w=60)],
                'sprites': [SP('monkey', 8, 38, 16, 'pop'), SP('rabbit', 30, 42, 14, 'pop'),
                            SP('chicken', 52, 40, 14, 'pop'), SP('anaconda', 70, 50, 24, 'pop'),
                            SIL('peacock', 90, 24, 8)],
                'bubbles': [BB('따뜻하다끽…?', 'small', l=3, t=22), BB('…콩, 콩. 누구세요.', 'small', l=34, t=26)],
                'narr': NB('따뜻한 기운에,\n한 마리씩 얼굴을 내밀었다.'),
                'sfx': SFX('끼익', 22, -6, r=4, t=60),
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '따끈마을의 첫 이야기가 열렸어요',
            'd': '따끈마을 종을 1종 잡으면 1장이 열려요.',
            'next': {'k': '다음 이야기', 't': '2장 「줄넘기 소리」', 'd': '따끈마을 종을 3종 잡으면 열려요.'},
        },
    },
    {
        'id': 'village-hot', 'ep': 2, 'kind': 'chapter',
        'name': '따끈마을', 'label': '따끈마을 2장', 'title': '줄넘기 소리',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-jumprope-post',
        'intro': '줄넘기가 하고 싶지만 부끄러웠던 콩지.\n셋이 함께 한 번 넘은 아침의 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 콩지가 운동장 구석에서 혼자 센다',
                'sky': 'morning', 'ground': 28,
                'props': [PR('stone-yard', l=-12, b=2, w=60, far=True),
                          PR('hot-jumprope-post', l=40, b=12, w=50, ar=0.8)],
                'narr': '콩지는 줄넘기가 하고 싶었다.\n하지만 부끄러워 구석에서 혼자 세었다.',
                'sprites': [SP('rabbit', 10, 46, 24, 'hop')],
                'bubbles': [BB('…하나, 둘, 셋… 콩, 콩.', 'small', l=6, t=34)],
                'sfx': SFX('콩콩', 22, 6, r=8, t=84),
            },
            {
                'aria': '2컷: 모닥이가 달려와 줄 한쪽을 잡아 준다',
                'sky': 'high', 'ground': 28, 'wide': True,
                'props': [PR('stone-yard', l=6, b=2, w=70), PR('hot-jumprope-post', l=62, b=12, w=36, ar=0.8)],
                'sprites': [SP('monkey', 30, 34, 22, 'jump'), SP('rabbit', 8, 46, 20)],
                'bubbles': [BB('일단 해보자끽!', 'pop tail-right', r=4, t=6), BB('…콩?', 'small', l=4, t=32)],
                'narr': NB('모닥이가 줄 한쪽을 대신 잡아 주었다.'),
                'sfx': SFX('휘익—', 24, -6, r=8, t=60),
            },
            {
                'aria': '3컷: 홰치가 졸린 눈으로 박자를 세어 준다',
                'sky': 'high', 'ground': 28, 'wide': True,
                'props': [PR('stone-yard', l=6, b=2, w=70), PR('hot-jumprope-post', l=62, b=12, w=36, ar=0.8)],
                'sprites': [SP('chicken', 70, 20, 16), SP('monkey', 38, 38, 18), SP('rabbit', 14, 46, 18, 'hop')],
                'bubbles': [BB('꼬오— 하나, 둘… 하아암. 셋에 넘어.', 'small', l=3, t=4)],
                'narr': NB('홰치도 졸린 눈으로\n박자를 세어 주었다.'),
                'sfx': SFX('휙, 휙', 22, -6, l=38, t=26),
            },
            {
                'aria': '4컷: 콩지가 줄을 넘자 돌바닥에서 온기가 퍼진다',
                'sky': 'warm', 'ground': 34, 'wide': True,
                'props': [PR('stone-yard', l=6, b=-2, w=88), PR('hot-jumprope-post', l=78, b=18, w=22, ar=0.8)],
                'glow': GL('flare', l=33, t=44, w=30),
                'sprites': [SP('rabbit', 36, 14, 22, 'jump'), SP('monkey', 8, 46, 18), SP('chicken', 74, 44, 16)],
                'sparks': SPK((26, 18), (66, 16), (20, 56), (80, 60)),
                'bubbles': [BB('넘었다…콩, 콩! 셋이서 넘었어!', 'pop tail-right', r=4, t=4)],
                'narr': NB('셋이 함께 한 번 넘자,\n운동장 돌바닥이 따뜻해졌다.'),
                'sfx': SFX('탁!', 28, 6, l=64, t=62),
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '따끈마을 두 번째 이야기가 열렸어요',
            'd': '따끈마을 종을 3종 잡으면 2장이 열려요.',
            'next': {'k': '다음 이야기', 't': '3장 「함께 데운 아침」', 'd': '따끈마을 종을 5종 모두 잡으면 열려요.'},
        },
    },
    {
        'id': 'village-hot', 'ep': 3, 'kind': 'chapter',
        'name': '따끈마을', 'label': '따끈마을 3장', 'title': '함께 데운 아침',
        'village': '따끈마을 · 운동', 'cover_prop': 'hot-sunrise-hill',
        'intro': '다섯 친구가 나란히 선 운동장.\n함께 데운 아침의 첫 해를 본 이야기예요.',
        'panels': [
            {
                'aria': '1컷: 길쭉이 이끄는 마을 스트레칭',
                'sky': 'morning', 'ground': 30, 'wide': True,
                'props': [PR('stone-yard', l=6, b=2, w=88), PR('hot-stretch-mat', l=40, b=8, w=50, ar=2.5)],
                'sprites': [SP('anaconda', 30, 14, 44, 'reach'), SP('monkey', 6, 48, 16),
                            SP('rabbit', 24, 52, 15), SP('chicken', 76, 48, 15)],
                'bubbles': [BB('쭈우우욱… 천천히 해도 돼. 다 같이.', 'pop tail-right', r=3, t=3)],
                'narr': NB('길쭉이 온 마을 스트레칭을 이끌었다.'),
                'sfx': SFX('쭈우욱', 22, -6, l=4, t=28),
            },
            {
                'aria': '2컷: 떨면서도 맨 앞에 선 놀빛',
                'sky': 'morning', 'ground': 30,
                'props': [PR('stone-yard', l=4, b=2, w=92)],
                'narr': '놀빛은 떨면서도 맨 앞에 서서\n몸을 움직였다.',
                'sprites': [SP('anaconda', 6, 18, 12), SP('monkey', 24, 18, 12), SP('rabbit', 66, 18, 12),
                            SP('chicken', 82, 18, 12), SP('peacock', 32, 36, 34, 'shiver')],
                'bubbles': [BB('…봐도 돼. 조금만…', 'small', r=4, t=62)],
                'sfx': SFX('파르르', 22, 6, l=6, t=84),
            },
            {
                'aria': '3컷: 서툰 몸짓에도 모두가 박수를 친다',
                'sky': 'high', 'ground': 30, 'wide': True,
                'props': [PR('stone-yard', l=6, b=2, w=88)],
                'sprites': [SP('peacock', 38, 36, 24), SP('monkey', 6, 42, 16, 'hop'), SP('rabbit', 22, 46, 14),
                            SP('chicken', 66, 44, 14, 'hop'), SP('anaconda', 78, 50, 20)],
                'sparks': SPK((44, 28), (56, 24), (30, 34), (72, 32)),
                'bubbles': [BB('최고다끽!', 'small', l=3, t=24), BB('…콩, 콩!', 'small', l=26, t=34)],
                'narr': NB('서툰 몸짓에도, 모두가 박수를 쳤다.'),
                'sfx': SFX('짝짝짝', 24, -4, r=6, t=12),
            },
            {
                'aria': '4컷: 다섯 친구가 나란히 서서 첫 해를 본다',
                'sky': 'warm', 'ground': 36, 'wide': True,
                'props': [PR('hot-sunrise-hill', l=0, b=22, w=100, ar=3.2, fb=('stone-yard', 10, 14, 80)),
                          PR('haru-tree', l=62, b=10, w=34)],
                'glow': [GL('flare', l=38, t=2, w=24, behind=True), GL('flare', l=76, t=26, w=14)],
                'sprites': [SP('monkey', 8, 46, 15), SP('rabbit', 24, 48, 14), SP('chicken', 40, 46, 14),
                            SP('anaconda', 54, 52, 20), SP('peacock', 76, 44, 15)],
                'hand': HAND(l=40, b=-8, w=16),
                'bubbles': [BB('따뜻하다끽…', 'small', l=2, t=34), BB('…콩.', 'small', l=24, t=38),
                            BB('꼬오— 하아암.', 'small', l=36, t=30), BB('쭈우욱… 좋다.', 'small', l=50, t=40),
                            BB('…봐도 돼. 같이.', 'small', r=2, t=30)],
                'narr': {'text': '다섯이 나란히 서서,\n함께 데운 아침의 첫 해를 보았다.', 'style': 'left: 10px; top: 10px;'},
            },
        ],
        'end_card': {
            'k': '이야기가 열린 때', 't': '따끈마을 이야기가 모두 열렸어요',
            'd': '따끈마을 종을 5종 모두 잡으면 3장이 열려요. 다음 마을 이야기도 기다려요.',
        },
    },
]


# 다섯 마을(반짝 · 냠냠 · 잔잔 · 소곤 · 알뜰) 불러오기 고리
import importlib
from pathlib import Path
import sys

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

for _code in ('bright', 'yum', 'calm', 'whisper', 'coin'):
    try:
        _mod = importlib.import_module(f'episodes_{_code}')
        EPISODES.extend(_mod.EPISODES)
    except ModuleNotFoundError as _e:
        if _e.name == f'episodes_{_code}':
            continue
        raise
