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
  props     [{key, style, far?}]  key = docs/design/webtoon-bg/<key>.png. 파일이 없으면 단색 블록 + '임시' 표시
  sprites   [{mon, evolved?, anim?, style}]  mon = 몬스터 그림 이름. evolved면 <mon>_2.png, 없으면 1.15배 + 빛
  bubbles   [{text, style, cls?}]  cls 예: 'pop tail-right' · 'small'
  narr?     내레이션 글 (\\n = 줄바꿈) 또는 {text, cls?, style?}
  sfx?      {text, style}
  glow?     {cls, style}
  hand?     {style}  돌봄이의 손
  lines?    {style, bars:[style...]}  속도선
  sweat?    [style...]  식은땀
  sparks?   [style...]  반짝
  todo_prop?  아직 없는 Ludo 소품 파일 이름(docs/기획/웹툰-대본, ludo-프롬프트.md와 같은 이름). 파일이 없으면 칸 구석에 '임시'
"""

EPISODES = [
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
]
