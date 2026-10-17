import 'package:flutter/material.dart';

import '../core/constants/app_assets.dart';
import 'models.dart';

/// 고정 데이터: 카테고리, 몬스터 도감, 상점 아이템, 기간 배수.
/// 나중에 백엔드에서 내려받도록 바꿔도 모델은 그대로 쓸 수 있다.
class Catalog {
  Catalog._();

  static const List<HabitCategory> categories = [
    HabitCategory(id: 'ex', name: '운동', short: '운동', type: '불꽃', color: Color(0xFFFF7A4D), measures: [
      Measure('운동 시간', '분', 30),
      Measure('운동 횟수', '회', 3),
      Measure('자가진단', '점', 4),
    ]),
    HabitCategory(id: 'st', name: '공부/학습', short: '공부', type: '번개', color: Color(0xFFFFD24D), measures: [
      Measure('공부 시간', '분', 60),
      Measure('학습량', 'p', 20),
      Measure('자가진단', '점', 4),
    ]),
    HabitCategory(id: 'fd', name: '식습관/건강', short: '식습관', type: '풀', color: Color(0xFF7FD36B), measures: [
      Measure('물 섭취량', 'L', 2),
      Measure('준수한 끼니', '끼', 3),
      Measure('영양제/약 섭취', 'OX', 1),
      Measure('야식 안 하기', 'OX', 1),
      Measure('자가진단', '점', 4),
    ]),
    HabitCategory(id: 'md', name: '명상/마음챙김', short: '명상', type: '물', color: Color(0xFF5FC9E8), measures: [
      Measure('명상 시간', '분', 10),
      Measure('일기 쓰기', 'OX', 1),
      Measure('독서', 'OX', 1),
      Measure('자가진단', '점', 4),
    ]),
    HabitCategory(id: 'sl', name: '수면', short: '수면', type: '달빛', color: Color(0xFFA99BF5), measures: [
      Measure('수면 시간', 'h', 7, range: 1),
      Measure('미라클 모닝', 'OX', 1),
    ]),
    HabitCategory(id: 'mn', name: '절약/재테크', short: '절약', type: '금속', color: Color(0xFFC9C6D8), measures: [
      Measure('불필요한 소비 안 하기', 'OX', 1),
      Measure('저축액', '원', 10000),
    ]),
  ];

  static HabitCategory category(String id) => categories.firstWhere((c) => c.id == id);

  // 카테고리마다 [첫 파트너(흔함 · Lv.1), 흔함 · Lv.1, 보통, …, 희귀] 순서. 탐색은 이 순서대로 후보를 모은다.
  static const List<MonsterSpecies> species = [
    // ── 운동 · 불꽃 ──
    MonsterSpecies(
      id: 'monkey', categoryId: 'ex', name: '불씨 원숭이', rarity: '흔함', unlockLevel: 1, asset: AppAssets.monkey, evolvedAsset: AppAssets.monkey2, fieldHeight: 72,
      description: '이마의 불씨는 몸을 움직인 만큼 자란다. 진화하면 꼬리 끝에도 불이 붙는다.',
      lines: {
        AffectionTier.low: ['끽…? 누구야?', '가만히 있으면 불씨가 작아져.', '(이마의 불씨가 깜빡인다)'],
        AffectionTier.mid: ['오늘도 몸 풀었어? 끽끽!', '같이 뛰면 불씨가 따뜻해져.', '스트레칭은 나한테 배워!'],
        AffectionTier.high: ['네 덕분에 불씨가 활활!', '오늘도 같이 땀 흘리자!', '너랑 있으면 몸이 근질근질해!'],
      },
    ),
    MonsterSpecies(
      id: 'rabbit', categoryId: 'ex', name: '깡총 불토끼', rarity: '흔함', unlockLevel: 3, asset: AppAssets.rabbit, fieldHeight: 72,
      description: '줄넘기 소리가 나면 어디선가 깡총 나타난다. 뛸 때마다 발끝이 따끈해진다.',
      lines: {
        AffectionTier.low: ['…깡총?', '(귀를 쫑긋 세운다)', '낯선 사람은 싫어.'],
        AffectionTier.mid: ['깡총깡총! 오늘 몇 번 뛰었어?', '발끝이 따끈따끈해.', '같이 뛸래?'],
        AffectionTier.high: ['너랑 뛰는 게 제일 좋아!', '오늘은 백 번 뛰자!', '깡총! 최고야!'],
      },
    ),
    MonsterSpecies(
      id: 'chicken', categoryId: 'ex', name: '횃불 닭', rarity: '보통', unlockLevel: 6, asset: AppAssets.chicken, evolvedAsset: AppAssets.chicken2, fieldHeight: 68,
      description: '해 뜨기 전에 일어나 운동하는 사람을 좋아한다. 진화하면 볏이 횃불처럼 솟는다.',
      lines: {
        AffectionTier.low: ['꼬…?', '(고개를 갸웃한다)', '아직 아침 운동 안 했지?'],
        AffectionTier.mid: ['꼬끼오! 일어날 시간!', '아침 운동은 상쾌해.', '볏이 조금 따뜻해졌어.'],
        AffectionTier.high: ['네 덕분에 볏이 활활 타!', '내일 아침도 같이 깨우자!', '꼬끼오~ 넌 최고야!'],
      },
    ),
    MonsterSpecies(
      id: 'anaconda', categoryId: 'ex', name: '용암 아나콘다', rarity: '보통', unlockLevel: 9, asset: AppAssets.anaconda, fieldHeight: 66,
      description: '몸을 길게 늘이는 스트레칭의 달인. 근육이 풀릴수록 비늘이 붉게 빛난다.',
      lines: {
        AffectionTier.low: ['스으…', '(똬리를 더 단단히 튼다)', '…뭘 보는 거야.'],
        AffectionTier.mid: ['스트레칭은 했어? 스으.', '몸이 풀리면 비늘이 따뜻해.', '천천히, 길게 늘여 봐.'],
        AffectionTier.high: ['너 덕분에 비늘이 반짝여!', '같이 쭉— 늘여 보자!', '…네 옆은 따뜻해서 좋아.'],
      },
    ),
    MonsterSpecies(
      id: 'peacock', categoryId: 'ex', name: '노을 공작', rarity: '희귀', unlockLevel: 12, asset: AppAssets.peacock, fieldHeight: 72,
      description: '꾸준히 운동한 사람 앞에서만 깃을 편다. 펼친 깃은 노을빛 불꽃으로 물든다.',
      lines: {
        AffectionTier.low: ['…흥.', '깃은 아무 앞에서나 안 펴.', '(고개를 돌린다)'],
        AffectionTier.mid: ['조금은 인정해 줄게.', '오늘도 움직였구나.', '깃 끝이 조금 따뜻해졌어.'],
        AffectionTier.high: ['자, 봐! 너를 위한 깃이야!', '네가 자랑스러워.', '노을보다 네가 더 빛나.'],
      },
    ),
    // ── 공부 · 번개 ──
    MonsterSpecies(
      id: 'mouse', categoryId: 'st', name: '찌릿 쥐', rarity: '흔함', unlockLevel: 1, asset: AppAssets.mouse, fieldHeight: 70,
      description: '책장 넘기는 소리를 좋아한다. 집중할수록 배의 번개 무늬가 톡톡 빛난다.',
      lines: {
        AffectionTier.low: ['찌릿…? 누구세요?', '책은… 펴긴 했어?', '(배의 무늬가 희미하게 깜빡인다)'],
        AffectionTier.mid: ['찌릿! 오늘 공부했어?', '책장 넘기는 소리 좋아.', '집중하면 무늬가 찌릿찌릿해져!'],
        AffectionTier.high: ['집중하는 네 옆이 제일 좋아!', '우리 오늘도 찌릿하게 해보자!', '너 오면 볼이 저절로 빵빵해져!'],
      },
    ),
    MonsterSpecies(
      id: 'deer', categoryId: 'st', name: '번개뿔 사슴', rarity: '흔함', unlockLevel: 3, asset: AppAssets.deer, fieldHeight: 74,
      description: '뿔 끝으로 번뜩이는 생각을 모은다. 문제를 하나 풀 때마다 등의 무늬가 늘어난다.',
      lines: {
        AffectionTier.low: ['…(귀를 쫑긋)', '조용히 해 줄래? 생각 중이야.', '뿔은 만지지 마.'],
        AffectionTier.mid: ['오늘은 몇 문제 풀었어?', '뿔 끝이 번뜩였어!', '모르는 건 천천히 다시 보자.'],
        AffectionTier.high: ['네 생각이 번개처럼 빨라졌어!', '같이 끝까지 풀어 보자!', '넌 정말 똑똑해.'],
      },
    ),
    MonsterSpecies(
      id: 'swan', categoryId: 'st', name: '천둥 백조', rarity: '보통', unlockLevel: 6, asset: AppAssets.swan, evolvedAsset: AppAssets.swan2, fieldHeight: 74,
      description: '오래 앉아 공부하는 사람 곁에 조용히 내려앉는다. 진화하면 날개에 번개 깃이 돋는다.',
      lines: {
        AffectionTier.low: ['…', '(깃을 정리하며 모른 척한다)', '시끄러운 건 싫어.'],
        AffectionTier.mid: ['오늘도 책상 앞에 앉았구나.', '집중하는 모습, 멋져.', '날개 끝이 찌릿했어.'],
        AffectionTier.high: ['네 집중력이 내 날개를 키워!', '같이 높이 날아오르자.', '넌 내 자랑이야.'],
      },
    ),
    MonsterSpecies(
      id: 'lion', categoryId: 'st', name: '벼락 사자', rarity: '희귀', unlockLevel: 9, asset: AppAssets.lion, fieldHeight: 76,
      description: '끝까지 해내는 사람만 알아본다. 갈기 속에는 작은 벼락이 잠들어 있다.',
      lines: {
        AffectionTier.low: ['…크릉.', '쉽게 곁을 내주진 않아.', '(갈기가 지직거린다)'],
        AffectionTier.mid: ['오늘 목표는 채웠어?', '포기하지 않는 건 좋아.', '갈기가 조금 찌릿해졌어.'],
        AffectionTier.high: ['넌 진짜 끝까지 하는구나!', '같이라면 어떤 시험도 거뜬해!', '크릉~ 네가 최고야.'],
      },
    ),
    // ── 식습관 · 풀 ──
    MonsterSpecies(
      id: 'turtle', categoryId: 'fd', name: '이끼 거북', rarity: '흔함', unlockLevel: 1, asset: AppAssets.turtle, fieldHeight: 64,
      description: '천천히 꼭꼭 씹어 먹는 사람을 좋아한다. 등딱지의 이끼는 채소를 먹을수록 푸르러진다.',
      lines: {
        AffectionTier.low: ['…(등딱지에 숨는다)', '천천히… 먹어…', '물… 마셨어…?'],
        AffectionTier.mid: ['꼭꼭 씹어 먹었어?', '이끼가 촉촉해졌어.', '채소도 먹었지?'],
        AffectionTier.high: ['너 덕분에 이끼가 반짝반짝!', '천천히 같이 오래 가자.', '네 옆이 제일 편해.'],
      },
    ),
    MonsterSpecies(
      id: 'hedgehog', categoryId: 'fd', name: '잎새 고슴도치', rarity: '흔함', unlockLevel: 3, asset: AppAssets.hedgehog, fieldHeight: 70,
      description: '가시 대신 부드러운 잎이 돋아 있다. 야식 냄새가 나면 잎을 바짝 세운다.',
      lines: {
        AffectionTier.low: ['(잎을 바짝 세운다)', '야식 냄새… 나는데?', '가까이 오지 마.'],
        AffectionTier.mid: ['야식 참았지? 기특해.', '잎이 보들보들해졌어.', '오늘 물 몇 잔 마셨어?'],
        AffectionTier.high: ['건강한 네가 좋아!', '이제 안아도 안 따가워!', '오늘도 같이 잘 먹자~'],
      },
    ),
    MonsterSpecies(
      id: 'badger', categoryId: 'fd', name: '덤불 오소리', rarity: '보통', unlockLevel: 6, asset: AppAssets.badger, fieldHeight: 70,
      description: '제철 채소와 열매를 귀신같이 찾아낸다. 편식하는 사람 앞에선 덤불 속에 숨어 버린다.',
      lines: {
        AffectionTier.low: ['킁킁… 뭐 먹었어?', '(덤불 뒤에서 지켜본다)', '편식은 싫어.'],
        AffectionTier.mid: ['오늘은 초록색도 먹었어?', '킁킁, 좋은 냄새.', '열매 하나 나눠 줄까?'],
        AffectionTier.high: ['네 식탁이 제일 맛있어 보여!', '같이 텃밭 가꿀래?', '킁킁~ 넌 최고야.'],
      },
    ),
    MonsterSpecies(
      id: 'platypus', categoryId: 'fd', name: '새순 오리너구리', rarity: '보통', unlockLevel: 9, asset: AppAssets.platypus, fieldHeight: 70,
      description: '하루 물 여덟 잔을 꼭 챙겨 마신다. 부리 끝의 새순은 물을 마실수록 자란다.',
      lines: {
        AffectionTier.low: ['꽉…?', '물은 마셨어?', '(부리를 꾹 다문다)'],
        AffectionTier.mid: ['한 잔 더 마시자, 꽉!', '새순이 자랐어!', '오늘 끼니 거르지 않았지?'],
        AffectionTier.high: ['네 덕분에 새순이 쑥쑥!', '꽉꽉! 건강 최고!', '같이 물 마시러 가자!'],
      },
    ),
    MonsterSpecies(
      id: 'owl', categoryId: 'fd', name: '숲지기 부엉이', rarity: '희귀', unlockLevel: 12, asset: AppAssets.owl, fieldHeight: 72,
      description: '숲의 열매를 지키는 부엉이. 규칙적으로 먹는 사람의 식탁을 밤새 지켜본다.',
      lines: {
        AffectionTier.low: ['부엉…', '(큰 눈으로 빤히 본다)', '아직 너를 몰라.'],
        AffectionTier.mid: ['오늘 세 끼 다 먹었어?', '규칙적인 건 좋은 거야.', '부엉, 잘하고 있어.'],
        AffectionTier.high: ['네 식탁은 내가 지킬게.', '너만큼 꾸준한 사람은 처음이야.', '부엉~ 고마워.'],
      },
    ),
    // ── 명상 · 물 ──
    MonsterSpecies(
      id: 'koala', categoryId: 'md', name: '물방울 코알라', rarity: '흔함', unlockLevel: 1, asset: AppAssets.koala, evolvedAsset: AppAssets.koala2, fieldHeight: 70,
      description: '숨을 천천히 쉬면 귀에 맺힌 물방울이 고요해진다. 진화하면 몸빛이 깊은 바다색이 된다.',
      lines: {
        AffectionTier.low: ['…(꾸벅)', '천천히… 숨 쉬어…', '서두르지 마.'],
        AffectionTier.mid: ['오늘 몇 분 앉아 있었어?', '들이쉬고… 내쉬고…', '물방울이 잔잔해졌어.'],
        AffectionTier.high: ['네 옆에선 마음이 고요해.', '오늘도 같이 숨 고르자.', '넌 참 차분해졌어.'],
      },
    ),
    MonsterSpecies(
      id: 'crocodile', categoryId: 'md', name: '개울 악어', rarity: '흔함', unlockLevel: 3, asset: AppAssets.crocodile, fieldHeight: 72,
      description: '개울에 반쯤 잠겨 하루 종일 멍하니 있는다. 무서워 보여도 화를 내는 법이 없다.',
      lines: {
        AffectionTier.low: ['…(눈만 꿈뻑)', '물속이 편해.', '화난 거 아니야. 원래 이래.'],
        AffectionTier.mid: ['잠깐 멍 때려 볼래?', '물소리 들려?', '오늘은 마음 편했어?'],
        AffectionTier.high: ['너랑 멍 때리는 게 제일 좋아.', '천천히 가도 괜찮아.', '…같이 있자.'],
      },
    ),
    MonsterSpecies(
      id: 'bat', categoryId: 'md', name: '안개 박쥐', rarity: '보통', unlockLevel: 6, asset: AppAssets.bat, fieldHeight: 60,
      description: '물안개 속에서 소리 없이 날아다닌다. 조용히 눈을 감은 사람 곁에 내려앉는다.',
      lines: {
        AffectionTier.low: ['…쉿.', '(안개 속으로 숨는다)', '시끄러우면 날아갈 거야.'],
        AffectionTier.mid: ['눈 감고 소리 들어 볼래?', '안개가 포근하지?', '오늘은 조용했네.'],
        AffectionTier.high: ['네 옆은 조용해서 좋아.', '같이 안개 속을 날자.', '…고마워.'],
      },
    ),
    MonsterSpecies(
      id: 'wolf', categoryId: 'md', name: '파도 늑대', rarity: '희귀', unlockLevel: 9, asset: AppAssets.wolf, fieldHeight: 74,
      description: '거친 파도 앞에서도 흔들리지 않는다. 마음을 다스리는 사람만 등에 태워 준다.',
      lines: {
        AffectionTier.low: ['…흥.', '아직 마음이 시끄럽네.', '(꼬리로 물을 친다)'],
        AffectionTier.mid: ['오늘은 파도가 잔잔해.', '숨 고르는 법, 좀 늘었네.', '같이 바다 볼래?'],
        AffectionTier.high: ['네 마음은 이제 고요한 바다야.', '등에 타. 특별히.', '…쓰다듬어 줘도 돼.'],
      },
    ),
    // ── 수면 · 달빛 ──
    MonsterSpecies(
      id: 'squirrel', categoryId: 'sl', name: '달밤 다람쥐', rarity: '흔함', unlockLevel: 1, asset: AppAssets.squirrel, fieldHeight: 70,
      description: '꼬리를 이불 삼아 일찍 잠든다. 볼주머니에는 꿈을 하나씩 모아 둔다.',
      lines: {
        AffectionTier.low: ['…졸려.', '(꼬리로 몸을 감싼다)', '(하품)'],
        AffectionTier.mid: ['일찍 자면 꿈을 모을 수 있어.', '어젯밤 푹 잤어?', '오늘은 몇 시에 잘 거야?'],
        AffectionTier.high: ['네 꿈도 하나 모아 둘게.', '오늘 밤도 같이 자자.', '내 꼬리, 같이 덮을래?'],
      },
    ),
    MonsterSpecies(
      id: 'axolotl', categoryId: 'sl', name: '별빛 우파루파', rarity: '흔함', unlockLevel: 3, asset: AppAssets.axolotl, fieldHeight: 62,
      description: '밤이 되면 아가미가 별빛처럼 은은하게 빛난다. 휴대폰 불빛을 아주 싫어한다.',
      lines: {
        AffectionTier.low: ['…눈부셔.', '휴대폰… 아직 보는 거야?', '(아가미를 접는다)'],
        AffectionTier.mid: ['불 끄면 내가 빛나 줄게.', '어제는 몇 시간 잤어?', '자기 전엔 화면 끄자.'],
        AffectionTier.high: ['네 밤은 내가 밝혀 줄게.', '오늘도 푹 자, 꼭.', '네 옆이 제일 포근해.'],
      },
    ),
    MonsterSpecies(
      id: 'orangutan', categoryId: 'sl', name: '꿈결 오랑우탄', rarity: '보통', unlockLevel: 6, asset: AppAssets.orangutan, fieldHeight: 74,
      description: '해가 지면 나뭇잎 침대를 정성껏 만든다. 같은 시간에 자는 사람을 좋아한다.',
      lines: {
        AffectionTier.low: ['…우우.', '(나뭇잎 침대를 고친다)', '늦게 자는 건 싫어.'],
        AffectionTier.mid: ['오늘도 같은 시간에 자자.', '침대 정리는 했어?', '규칙적인 잠이 최고야.'],
        AffectionTier.high: ['네 침대도 만들어 줄게!', '우우~ 오늘도 같이 자자.', '넌 이제 잠의 달인이야.'],
      },
    ),
    MonsterSpecies(
      id: 'manta', categoryId: 'sl', name: '은하 가오리', rarity: '희귀', unlockLevel: 9, asset: AppAssets.manta, fieldHeight: 58,
      description: '꿈과 꿈 사이를 헤엄쳐 다닌다. 깊이 잠든 사람의 꿈에만 나타난다.',
      lines: {
        AffectionTier.low: ['…', '(조용히 떠다닌다)', '아직 꿈이 얕아.'],
        AffectionTier.mid: ['어젯밤 꿈에서 봤어.', '깊이 자면 더 멀리 갈 수 있어.', '오늘 밤도 만나.'],
        AffectionTier.high: ['네 꿈속 바다가 제일 넓어.', '같이 은하를 헤엄치자.', '잘 자, 내 친구.'],
      },
    ),
    // ── 절약 · 금속 ──
    MonsterSpecies(
      id: 'redpanda', categoryId: 'mn', name: '동전 레서판다', rarity: '흔함', unlockLevel: 1, asset: AppAssets.redPanda, fieldHeight: 70,
      description: '반짝이는 동전을 꼬리에 모아 둔다. 충동구매를 참을 때마다 털이 은빛으로 빛난다.',
      lines: {
        AffectionTier.low: ['…(꼬리를 감춘다)', '내 동전은 안 줘.', '오늘 뭐 샀어?'],
        AffectionTier.mid: ['오늘은 안 샀지? 잘했어.', '동전이 하나 늘었어!', '가계부는 썼어?'],
        AffectionTier.high: ['네 덕분에 꼬리가 반짝반짝!', '같이 모으면 금방이야!', '넌 절약왕이야!'],
      },
    ),
    MonsterSpecies(
      id: 'hippo', categoryId: 'mn', name: '철갑 하마', rarity: '흔함', unlockLevel: 3, asset: AppAssets.hippo, fieldHeight: 70,
      description: '입을 꽉 다문 채 지갑을 지킨다. 등의 철갑은 아낀 만큼 두꺼워진다.',
      lines: {
        AffectionTier.low: ['…(입을 꽉 다문다)', '지갑은 닫아 둬.', '흥.'],
        AffectionTier.mid: ['오늘은 지갑 잘 지켰어?', '철갑이 조금 두꺼워졌어.', '작은 돈도 모이면 커.'],
        AffectionTier.high: ['네 지갑은 내가 지킬게!', '우리 철갑, 튼튼하지?', '넌 정말 든든해.'],
      },
    ),
    MonsterSpecies(
      id: 'chameleon', categoryId: 'mn', name: '나사 카멜레온', rarity: '보통', unlockLevel: 6, asset: AppAssets.chameleon, fieldHeight: 72,
      description: '광고를 보면 몸 색을 바꿔 숨어 버린다. 사고 싶은 마음을 하루 미루는 게 특기다.',
      lines: {
        AffectionTier.low: ['…(벽 색으로 변한다)', '나 여기 없어.', '광고는 보지 마.'],
        AffectionTier.mid: ['사고 싶으면 하루만 참아 봐.', '오늘은 무슨 색이 좋아?', '장바구니, 비웠어?'],
        AffectionTier.high: ['너 앞에선 숨지 않을게.', '참는 거, 진짜 잘해!', '오늘은 반짝이 색이야!'],
      },
    ),
    MonsterSpecies(
      id: 'octopus', categoryId: 'mn', name: '무쇠 문어', rarity: '보통', unlockLevel: 9, asset: AppAssets.octopus, fieldHeight: 72,
      description: '여덟 다리로 수입과 지출을 따로따로 챙긴다. 계산이 맞아떨어지면 먹물 대신 은가루를 뿜는다.',
      lines: {
        AffectionTier.low: ['…(다리를 꼰다)', '계산 중이야. 방해하지 마.', '흐음.'],
        AffectionTier.mid: ['오늘 쓴 돈, 적어 뒀어?', '여덟 칸에 나눠 담자.', '계산이 딱 맞았어!'],
        AffectionTier.high: ['네 가계부는 완벽해!', '은가루 뿜어 줄게! 퓨!', '같이 부자 되자!'],
      },
    ),
    MonsterSpecies(
      id: 'shark', categoryId: 'mn', name: '강철 상어', rarity: '보통', unlockLevel: 12, asset: AppAssets.shark, fieldHeight: 70,
      description: '새는 돈 냄새를 멀리서도 맡는다. 강철 지느러미로 쓸데없는 지출을 싹둑 잘라 낸다.',
      lines: {
        AffectionTier.low: ['…킁.', '새는 돈 냄새가 나.', '(지느러미를 세운다)'],
        AffectionTier.mid: ['구독, 안 쓰는 거 있지?', '쓸데없는 건 싹둑!', '오늘은 냄새 안 나네.'],
        AffectionTier.high: ['네 지갑엔 구멍이 없어!', '같이 바다를 지키자!', '든든한 짝꿍이야.'],
      },
    ),
    MonsterSpecies(
      id: 'jaguar', categoryId: 'mn', name: '은빛 재규어', rarity: '희귀', unlockLevel: 15, asset: AppAssets.jaguar, fieldHeight: 72,
      description: '오래 모은 사람 앞에만 모습을 드러낸다. 은빛 무늬는 쌓인 저축만큼 선명해진다.',
      lines: {
        AffectionTier.low: ['…', '아직 모은 게 적네.', '(꼬리만 살랑인다)'],
        AffectionTier.mid: ['꾸준히 모으는구나.', '무늬가 조금 선명해졌어.', '서두르지 않는 게 좋아.'],
        AffectionTier.high: ['네 저축이 내 무늬를 빛나게 해.', '이제 너를 인정해.', '…곁에 있어 줄게.'],
      },
    ),
  ];

  static MonsterSpecies speciesById(String id) => species.firstWhere((s) => s.id == id);

  /// 카테고리별 첫 파트너 후보 (그림이 없는 카테고리는 null).
  static const Map<String, String?> starters = {
    'ex': 'monkey', 'st': 'mouse', 'fd': 'turtle', 'md': 'koala', 'sl': 'squirrel', 'mn': 'redpanda',
  };

  static const List<ShopItem> items = [
    ShopItem(id: 's', name: '하급 경험치 물약', short: '하급', price: 20, exp: 20, asset: AppAssets.potionSmall),
    ShopItem(id: 'm', name: '중급 경험치 물약', short: '중급', price: 90, exp: 100, asset: AppAssets.potionMedium),
    ShopItem(id: 'l', name: '상급 경험치 물약', short: '상급', price: 400, exp: 500, asset: AppAssets.potionLarge),
  ];

  static const ShopItem seongsilBall =
      ShopItem(id: 'ball', name: '성실볼', short: '성실볼', price: 50, exp: 0, asset: AppAssets.seongsilBall);

  // ---------- 서버 코드 ↔ 앱 id (결정 D2) ----------
  // 카테고리(ex · st …) · 몬스터 종(wolf · spark …)은 앱 id가 DB 코드와 같다 (seed.sql).
  // 측정 항목은 카테고리 안 순서(measureIndex)가 DB `measure_type.sort_order − 1`과 같다.
  // 상점 아이템만 이름이 달라서 여기서 잇는다.

  /// DB `shop.shop_item.code` → 앱 아이템 id.
  static const Map<String, String> itemIdByServerCode = {'POTION_S': 's', 'POTION_M': 'm', 'POTION_L': 'l', 'BALL': 'ball'};

  /// 서버에 보낼 아이템 코드 (예: 하급 물약 → POTION_S).
  static String serverCodeOf(ShopItem item) =>
      itemIdByServerCode.entries.firstWhere((e) => e.value == item.id).key;

  /// 서버 아이템 코드 → 앱 아이템. 모르는 코드면 null.
  static ShopItem? itemByServerCode(String code) {
    final id = itemIdByServerCode[code];
    if (id == null) return null;
    return id == seongsilBall.id ? seongsilBall : items.where((i) => i.id == id).firstOrNull;
  }

  /// 습관 기간과 끝까지 지켰을 때의 보상 배수.
  // DB v1.4: 7일/30일/100일 (period_code D7/D30/D100, 배수는 config.period_multiplier)
  static const List<(String, double)> periods = [('7일', 1.2), ('30일', 1.5), ('100일', 2.0)];

  /// 기간 배수 표시 (예: ×1.2).
  static String periodMult(int i) => '×${periods[i].$2.toStringAsFixed(1)}';

  /// 온보딩 습관 추천: (이름, 측정 방식 index, 하루 목표).
  static const Map<String, List<(String, int, double)>> habitPresets = {
    'ex': [('아침 러닝', 0, 30), ('스쿼트', 1, 30), ('홈트 한 판', 0, 20)],
    'st': [('전공 공부', 0, 60), ('문제집 풀기', 1, 20), ('오늘 복습', 2, 4)],
    'fd': [('물 2L 마시기', 0, 2), ('세 끼 챙겨 먹기', 1, 3), ('영양제 먹기', 2, 1), ('야식 참기', 3, 1)],
    'md': [('10분 명상', 0, 10), ('감사 일기', 1, 1), ('자기 전 독서', 2, 1)],
    'sl': [('7시간 자기', 0, 7), ('6시 기상', 1, 1)],
    'mn': [('충동구매 안 하기', 0, 1), ('하루 저축', 1, 10000)],
  };

  /// 하루 목표 −/+ 버튼 한 번에 바뀌는 양 (단위별).
  static const Map<String, double> targetSteps = {
    '분': 5, '회': 1, '점': 1, 'L': 0.5, 'p': 5, '끼': 1, 'h': 0.5, '원': 5000,
  };

  /// 첫 파트너를 안 고르고 넘어갔을 때 쓰는 기본 길.
  static const List<String> defaultCategories = ['ex', 'st', 'fd'];

  static const List<String> professorIntro = [
    '어서 오게! 나는 몬스터의 습성을 연구하는 대림대 박사라네.',
    "이 세계의 몬스터들은 사람의 '성실함'에 반응해서 모습을 드러낸다네.",
    '매일 습관을 지키면 성실도가 쌓이고, 골드와 새로운 몬스터를 만날 수 있지.',
    '자, 먼저 어떤 길을 걸을지, 어떤 습관을 지킬지 정해보겠나?',
  ];
}
