/// 이미지 경로 모음. 새 이미지는 여기에 등록하고 pubspec.yaml의 폴더 안에 넣으면 된다.
class AppAssets {
  AppAssets._();

  static const String _monsters = 'assets/images/monsters';
  static const String _characters = 'assets/images/characters';
  static const String _items = 'assets/images/items';
  static const String _bg = 'assets/images/backgrounds';
  static const String _brand = 'assets/images/brand';

  // 몬스터 (카테고리 순: 운동 불꽃 · 공부 번개 · 식습관 풀 · 명상 물 · 수면 달빛 · 절약 금속). `_2` = 1차 진화 그림
  static const String monkey = '$_monsters/monkey.png';
  static const String monkey2 = '$_monsters/monkey_2.png';
  static const String rabbit = '$_monsters/rabbit.png';
  static const String chicken = '$_monsters/chicken.png';
  static const String chicken2 = '$_monsters/chicken_2.png';
  static const String anaconda = '$_monsters/anaconda.png';
  static const String peacock = '$_monsters/peacock.png';
  static const String mouse = '$_monsters/mouse.png';
  static const String deer = '$_monsters/deer.png';
  static const String swan = '$_monsters/swan.png';
  static const String swan2 = '$_monsters/swan_2.png';
  static const String lion = '$_monsters/lion.png';
  static const String turtle = '$_monsters/turtle.png';
  static const String hedgehog = '$_monsters/hedgehog.png';
  static const String badger = '$_monsters/badger.png';
  static const String platypus = '$_monsters/platypus.png';
  static const String owl = '$_monsters/owl.png';
  static const String koala = '$_monsters/koala.png';
  static const String koala2 = '$_monsters/koala_2.png';
  static const String crocodile = '$_monsters/crocodile.png';
  static const String bat = '$_monsters/bat.png';
  static const String wolf = '$_monsters/wolf.png';
  static const String squirrel = '$_monsters/squirrel.png';
  static const String axolotl = '$_monsters/axolotl.png';
  static const String orangutan = '$_monsters/orangutan.png';
  static const String manta = '$_monsters/manta.png';
  static const String redPanda = '$_monsters/redpanda.png';
  static const String hippo = '$_monsters/hippo.png';
  static const String chameleon = '$_monsters/chameleon.png';
  static const String octopus = '$_monsters/octopus.png';
  static const String shark = '$_monsters/shark.png';
  static const String jaguar = '$_monsters/jaguar.png';

  // 캐릭터
  /// 대림대 박사 스프라이트 시트: 6열 × 6행 = 36프레임, 프레임 208×380px.
  static const String professorSheet = '$_characters/professor_sheet.png';
  static const int professorCols = 6;
  static const int professorRows = 6;
  static const double professorFrameW = 208;
  static const double professorFrameH = 380;

  static const String shopkeeper = '$_characters/shopkeeper.png';

  // 아이템
  static const String potionSmall = '$_items/potion_small.png';
  static const String potionMedium = '$_items/potion_medium.png';
  static const String potionLarge = '$_items/potion_large.png';
  static const String seongsilBall = '$_items/seongsil_ball.png';

  // 브랜드 (로그인 화면 로고 = 앱 아이콘)
  static const String logo = '$_brand/logo.png';

  // 배경
  static const String homeField = '$_bg/home_field.png';
}
