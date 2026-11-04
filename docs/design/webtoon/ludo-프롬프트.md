# 루틴몬 웹툰 — Ludo 배경 소품 프롬프트 시트 (여섯 마을)

이미지는 사용자가 Ludo 웹에서 직접 만든다. 이 문서는 **무엇을 · 어떤 이름으로 · 어디에 · 어떤 프롬프트로** 만들지 적은 목록이다.
따끈마을 파일 이름은 컷 대본(`docs/기획/웹툰-대본/README.md`의 임시 소품 6개)과 같다.

## 공통 규칙 (모든 프롬프트 끝에 붙인다)

> single prop on a plain white background, 16-bit pixel art, bold dark outline, soft pastel colors, no creatures, no text

- 소품 하나만, 흰 바탕(나중에 흰색을 지워 투명 PNG로 쓴다). 그림자 · 바닥 판 없이 소품만.
- 생물(사람 · 동물 · 몬스터) 없음, 글자 · 숫자 · 로고 없음.
- 저장 위치는 전부 `docs/design/webtoon-bg/`. 파일 이름은 `<village>-<item>.png`.
- 마을 코드: `hot`(따끈) · `bright`(반짝) · `yum`(냠냠) · `calm`(잔잔) · `whisper`(소곤) · `coin`(알뜰).

## 이미 있는 소품 6장 (프롬프트를 다시 씀)

지금 파일의 모양을 보고 같은 느낌이 나오도록 다시 적었다. 이미지를 새로 만들 필요는 없고, 나중에 같은 화풍으로 맞출 때 쓴다.

| 파일 (`docs/design/webtoon-bg/`) | 모양 | 다시 쓴 프롬프트 |
| --- | --- | --- |
| `haru-tree.png` | 작은 풀 섬 한가운데 큰 나무, 둘레에 붉은 지붕 집 6채 | `a small floating grass island with one big round-leafed tree in the center and six small red-roofed cottages around it, 16-bit pixel art, bold dark outline, pastel, ...공통 규칙` |
| `tree-big.png` | 둥근 잎 세 덩이의 큰 나무와 풀 바닥 한 줄 | `a big round leafy tree with a thick brown trunk on a thin strip of grass, 16-bit pixel art, ...공통 규칙` |
| `tree-crown.png` | 층층이 겹친 둥근 나무 윗부분과 뿌리 쪽 줄기 | `a layered round tree crown with a short trunk base, 16-bit pixel art, ...공통 규칙` |
| `village-square.png` | 둘레에 집과 나무가 선 둥근 흙바닥 광장 | `a round cream-colored dirt village square surrounded by red-roofed cottages and one tree, 16-bit pixel art, ...공통 규칙` |
| `village-path.png` | 양쪽에 집이 늘어선 풀밭 사이 흙길 | `a winding cream dirt path between grass with red-roofed cottages on both sides, 16-bit pixel art, ...공통 규칙` |
| `stone-yard.png` | 둥근 돌을 깐 돌바닥 마당 (이끼 조금) | `a flat cobblestone yard with round cream and pink stones and a little moss, top-down, 16-bit pixel art, ...공통 규칙` |

## 1. 따끈마을 (운동 · 불꽃) — 6개 (대본이 이미 6개 이름을 씀)

| 파일 | 영어 프롬프트 | 쓰는 편 |
| --- | --- | --- |
| `hot-jumprope-post.png` | `a wooden jump-rope post, a short pole with a pastel rope looped and hanging from it, warm peach and brown colors, ` + 공통 규칙 | 콩지 1 · 2 · 3화, 따끈마을 2장, 모닥이 · 콩지 표지 |
| `hot-sunrise-hill.png` | `a small grassy hill with a half sunrise glowing on its horizon, soft orange and pink sky band behind it, ` + 공통 규칙 | 홰치 1 · 2 · 3화, 콩지 3화, 따끈마을 3장 |
| `hot-warm-rock.png` | `a big warm smooth boulder with little steam puffs rising from it, pastel peach and gray stone, ` + 공통 규칙 | 모닥이 3화, 길쭉 1 · 3화 |
| `hot-roost-perch.png` | `a wooden chicken roost perch, a horizontal log bar on two short posts, light brown wood, ` + 공통 규칙 | 홰치 1 · 2 · 3화 |
| `hot-sunset-ridge.png` | `a low rolling ridge of hills with a sunset glowing behind it, pastel orange pink and lavender sky band, ` + 공통 규칙 | 놀빛 1 · 2 · 3화 |
| `hot-stretch-mat.png` | `a long rolled-out exercise stretching mat, flat pastel mint green with rounded corners and a thin lighter edge, ` + 공통 규칙 | 길쭉 2화, 따끈마을 3장 |

## 2. 반짝마을 (공부 · 번개) — 4개

| 파일 | 영어 프롬프트 | 쓰는 편 |
| --- | --- | --- |
| `bright-bookshelf.png` | `a tall wooden bookshelf filled with colorful closed books with blank spines, pastel colors, ` + 공통 규칙 | 1장 「불이 꺼진 도서관」, 토독 · 번득이 · 둥실 · 끈기 화 |
| `bright-open-book.png` | `a big open book lying flat on a small wooden stand, pages blank with tiny pastel yellow sparkles, ` + 공통 규칙 | 1장, 3장 「끝까지 읽은 날」, 끈기 화 |
| `bright-lantern.png` | `a small hanging glass lantern with a soft yellow glow, thin dark metal frame, ` + 공통 규칙 | 1 · 2장, 번득이 화 |
| `bright-reading-table.png` | `a round wooden reading table with a stack of blank notebooks and a pencil cup, ` + 공통 규칙 | 2장 「모르는 건 부끄럽지 않아」, 토독 · 둥실 화 |

## 3. 냠냠마을 (식습관 · 풀숲) — 4개

| 파일 | 영어 프롬프트 | 쓰는 편 |
| --- | --- | --- |
| `yum-long-table.png` | `a long wooden dining table with empty round plates and wooden spoons, pastel cloth runner, ` + 공통 규칙 | 1장 「텅 빈 식탁」, 3장 「오늘은 다 같이 한 상」 |
| `yum-rice-bowl.png` | `a warm bowl of white rice with steam puffs rising, pastel blue ceramic bowl, ` + 공통 규칙 | 1장, 밤톨 · 오물 화 |
| `yum-berry-bush.png` | `a small leafy bush full of round red and purple berries, ` + 공통 규칙 | 2장 「편식 탐정 다래」, 다래 · 푸릇이 화 |
| `yum-water-pitcher.png` | `a glass water pitcher with a few clear cups next to it, pastel blue water, ` + 공통 규칙 | 3장, 쪼르 화 |

## 4. 잔잔마을 (명상 · 물가) — 4개

| 파일 | 영어 프롬프트 | 쓰는 편 |
| --- | --- | --- |
| `calm-stream.png` | `a short gentle stream of water with smooth ripples and a few round pebbles on its banks, pastel blue, ` + 공통 규칙 | 1 · 2 · 3장, 퐁글 · 물멍 · 보슬 · 나울 화 |
| `calm-flat-stone.png` | `a big flat sitting stone with a little moss, pale gray-blue, ` + 공통 규칙 | 2장 「멍 때리는 오후」, 물멍 화 |
| `calm-lily-pond.png` | `a small round pond with big pastel green lily pads and pink lotus flowers, ` + 공통 규칙 | 퐁글 · 나울 화 |
| `calm-mist-bank.png` | `a soft low bank of white pastel mist clouds floating over reeds, ` + 공통 규칙 | 3장 「흔들려도 돌아오는 길」, 보슬 화 |

## 5. 소곤마을 (수면 · 달밤) — 4개

| 파일 | 영어 프롬프트 | 쓰는 편 |
| --- | --- | --- |
| `whisper-leaf-bed.png` | `a cozy bed made of big soft green leaves with a small pastel pillow, ` + 공통 규칙 | 2장 「잎사귀 침대」, 포근이 · 새근이 화 |
| `whisper-star-lamp.png` | `a street lamp post with a glowing pastel yellow star-shaped lantern, ` + 공통 규칙 | 1장 「불 켜진 밤」, 초롱 화 |
| `whisper-crescent-moon.png` | `a big pastel yellow crescent moon with a few small sparkle stars around it, ` + 공통 규칙 | 3장 「꿈 사이로」, 아라 화 |
| `whisper-cloud-quilt.png` | `a fluffy white and lavender cloud-shaped quilt blanket, ` + 공통 규칙 | 포근이 3화, 3장 |

## 6. 알뜰마을 (절약 · 동전) — 4개

| 파일 | 영어 프롬프트 | 쓰는 편 |
| --- | --- | --- |
| `coin-tower.png` | `a neat tower of stacked gold round coins with blank faces, pastel yellow, ` + 공통 규칙 | 1장 「동전이 굴러간 자리」, 차곡 화 |
| `coin-ledger-desk.png` | `a small wooden desk with an open blank ledger book and a pen cup, ` + 공통 규칙 | 3장 「가계부 잔치」, 꼼꼼 화 |
| `coin-piggy-jar.png` | `a big glass jar half full of gold coins with a cork lid, ` + 공통 규칙 | 2장 「사고 싶은 마음」, 든든 · 미루 화 |
| `coin-market-stall.png` | `a small village market stall with a striped pastel awning and empty wooden shelves, ` + 공통 규칙 | 1 · 2장, 짤랑 화 |

> 3~5개 규칙보다 따끈마을만 6개인 이유: 컷 대본이 이미 6개 이름을 써서, 대본과 이름을 맞추려고 그대로 두었다.
> 다른 다섯 마을의 소품은 아직 대본이 없어서 설정서(`2026-11-03-캐릭터-이름-스토리.md`)의 장 줄거리를 보고 정한 **가정**이다. 대본이 생기면 이름이 바뀔 수 있다.

## 사용자가 Ludo 웹에서 직접 만들 것 (체크리스트)

우선순위: 따끈마을 6개 먼저 (이미 18편 대본이 이 이름을 쓴다).

- [ ] 따끈마을 6개: `hot-jumprope-post` · `hot-sunrise-hill` · `hot-warm-rock` · `hot-roost-perch` · `hot-sunset-ridge` · `hot-stretch-mat`
- [ ] 반짝마을 4개: `bright-bookshelf` · `bright-open-book` · `bright-lantern` · `bright-reading-table`
- [ ] 냠냠마을 4개: `yum-long-table` · `yum-rice-bowl` · `yum-berry-bush` · `yum-water-pitcher`
- [ ] 잔잔마을 4개: `calm-stream` · `calm-flat-stone` · `calm-lily-pond` · `calm-mist-bank`
- [ ] 소곤마을 4개: `whisper-leaf-bed` · `whisper-star-lamp` · `whisper-crescent-moon` · `whisper-cloud-quilt`
- [ ] 알뜰마을 4개: `coin-tower` · `coin-ledger-desk` · `coin-piggy-jar` · `coin-market-stall`
- [ ] 만들 때마다: 프롬프트 끝에 공통 규칙 문장을 붙였는지, 흰 바탕에 소품 하나뿐인지, 생물 · 글자가 없는지 확인
- [ ] 흰 바탕을 지운 투명 PNG로 저장하고 `docs/design/webtoon-bg/<파일 이름>.png`에 넣기 (기존 6장과 같은 방식)
- [ ] 이미지가 없는 동안 따끈마을 편은 `stone-yard` 등 기존 소품이나 단색으로 그려지고 컷 구석에 '임시' 표시가 붙는다. 넣은 뒤 `build.py`를 다시 돌려야 '임시'가 사라진다
