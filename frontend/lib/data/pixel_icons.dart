import 'package:flutter/material.dart';

import '../core/widgets/pixel_icon.dart';

/// 시안(prototype-source.dc.html)의 픽셀 SVG 아이콘 path. 16×16 격자.
class PixelIcons {
  PixelIcons._();

  /// 카테고리 아이콘 (a=본색, b=그늘/속, c=하이라이트). 시안의 `CI`.
  static const Map<String, List<PixelLayer>> category = {
    'ex': [
      PixelLayer('M7 1h2v2h1v1h1V3h1v2h1v2h1v5h-1v2h-1v1H4v-1H3v-2H2V7h1V5h1v1h1V4h1V2h1z', Color(0xFFFF7A4D)),
      PixelLayer('M7 7h2v1h1v1h1v3h-1v1H6v-1H5V9h1V8h1z', Color(0xFFFFD24D)),
      PixelLayer('M7 10h2v2H7z', Color(0xFFFFF6C8)),
    ],
    'st': [
      PixelLayer(
          'M7 1h6v1H7z M6 2h6v1H6z M6 3h5v1H6z M5 4h5v1H5z M4 5h9v1H4z M6 6h6v1H6z M7 7h4v1H7z M7 8h3v1H7z M6 9h3v1H6z M6 10h2v1H6z M5 11h2v1H5z M5 12h1v2H5z',
          Color(0xFFFFD24D)),
      PixelLayer('M10 5h3v1h-3z M9 6h3v1H9z M8 8h2v1H8z', Color(0xFFE09A1A)),
      PixelLayer('M7 2h2v1H7z M6 4h2v1H6z', Color(0xFFFFF6C8)),
    ],
    'fd': [
      PixelLayer(
          'M9 2h5v1H9z M7 3h7v1H7z M5 4h9v2H5z M4 6h9v2H4z M4 8h8v1H4z M4 9h7v1H4z M5 10h5v1H5z M3 11h2v1H3z M2 12h2v1H2z M1 13h2v1H1z',
          Color(0xFF7FD36B)),
      PixelLayer('M12 4h1v1h-1z M11 5h1v1h-1z M10 6h1v1h-1z M9 7h1v1H9z M8 8h1v1H8z M7 9h1v1H7z M6 10h1v1H6z',
          Color(0xFF3F8F3A)),
      PixelLayer('M6 5h2v1H6z M5 6h1v2H5z', Color(0xFFD4F5B8)),
    ],
    'md': [
      PixelLayer('M7 1h2v2h1v2h1v1h1v2h1v4h-1v2h-1v1H5v-1H4v-2H3V8h1V6h1V5h1V3h1z', Color(0xFF5FC9E8)),
      PixelLayer('M11 10h1v2h-1z M9 13h2v1H9z', Color(0xFF2F8FB0)),
      PixelLayer('M5 8h2v1H5z M5 9h1v2H5z', Color(0xFFE0F8FF)),
    ],
    'sl': [
      PixelLayer('M5 1h5v1H5z M3 2h5v1H3z M2 3h4v1H2z M1 4h4v2H1z M1 6h3v4H1z M1 10h4v2H1z M2 12h4v1H2z M3 13h5v1H3z M5 14h5v1H5z',
          Color(0xFFA99BF5)),
      PixelLayer('M12 5h1v1h-1z M11 6h3v1h-3z M12 7h1v1h-1z', Color(0xFFFFE58A)),
      PixelLayer('M3 4h1v2H3z M2 6h1v3H2z', Color(0xFFE8E2FF)),
    ],
    'mn': [
      PixelLayer('M5 1h6v1h2v2h1v8h-1v2h-2v1H5v-1H3v-2H2V4h1V2h2z', Color(0xFFF0B23C)),
      PixelLayer('M6 4h4v1h1v6h-1v1H6v-1H5V5h1z', Color(0xFFB27A14)),
      PixelLayer('M7 6h2v4H7z M4 3h2v1H4z', Color(0xFFFFE7A8)),
    ],
  };

  /// 기간 보상 상자 색 (뚜껑, 몸통, 띠). 7일 · 30일 · 100일. 시안의 `CHESTS`.
  static const List<(Color, Color, Color)> chestColors = [
    (Color(0xFFA8673A), Color(0xFFC98A4B), Color(0xFF8A5226)),
    (Color(0xFF8F8BA8), Color(0xFFC9C6D8), Color(0xFF6B6890)),
    (Color(0xFFE2574C), Color(0xFFFF8A6A), Color(0xFFFFD24D)),
  ];

  /// 자물쇠 달린 보상 상자.
  static List<PixelLayer> chest(Color lid, Color body, Color band, {bool highlight = true}) => [
        PixelLayer('M3 3h10v1h1v3H2V4h1z', lid),
        PixelLayer('M2 7h12v7H2z', body),
        PixelLayer('M2 7h12v1H2z M7 4h2v6H7z M2 12h12v1H2z', band),
        const PixelLayer('M7 8h2v2H7z', Color(0xFF2B1A1A)),
        if (highlight) const PixelLayer('M4 4h3v1H4z', Color(0x88FFFFFF)),
      ];

  /// 목표 보상표의 작은 주간 상자 (자물쇠 · 아래 띠 없음).
  static const List<PixelLayer> weeklyChest = [
    PixelLayer('M3 3h10v1h1v3H2V4h1z', Color(0xFFA8673A)),
    PixelLayer('M2 7h12v7H2z', Color(0xFFC98A4B)),
    PixelLayer('M2 7h12v1H2z M7 4h2v6H7z', Color(0xFFFFD24D)),
  ];

  /// 아직 길을 안 고른 파트너 자리의 몬스터볼. [top]은 윗부분 색.
  static List<PixelLayer> ball(Color top) => [
        const PixelLayer('M5 1h6v1h2v2h1v8h-1v2h-2v1H5v-1H3v-2H2V4h1V2h2z', Color(0xFFFFFAF0)),
        PixelLayer('M5 1h6v1h2v2h1v3H2V4h1V2h2z', top),
        const PixelLayer('M2 7h12v2H2z M6 6h4v4H6z', Color(0xFF2B1A1A)),
        const PixelLayer('M7 7h2v2H7z', Color(0xFFFFD479)),
      ];

  static const List<PixelLayer> pencil = [
    PixelLayer('M11 1h2v1h1v2h-1v1h-1v1h-1v1h-1v1H9v1H8v1H7v1H6v1H3v-3h1v-1h1V9h1V8h1V7h1V6h1V5h1V4h1V3h1V2h-1z',
        Color(0xFFD94A3D)),
    PixelLayer('M3 12h3v3H2v-2h1z', Color(0xFF2B1A1A)),
  ];

  /// 선으로 그리는 아이콘 (strokeWidth 3.5).
  static const String checkStroke = 'M2 8l4 4 8-8';
  static const String crossStroke = 'M3 3l10 10M13 3L3 13';

  // ---------- 홈 ----------
  /// 필드 오른쪽 위 상점 노점 아이콘.
  static const List<PixelLayer> shopStall = [
    PixelLayer('M2 1h12v2H2z', Color(0xFF6B3F1D)),
    PixelLayer('M3 7h10v4H3z', Color(0xFF241A3D)),
    PixelLayer('M1 3h14v3H1z M1 6h2v1H1z M5 6h2v1H5z M9 6h2v1H9z M13 6h2v1h-2z', Color(0xFFE2574C)),
    PixelLayer('M3 3h2v3H3z M7 3h2v3H7z M11 3h2v3h-2z', Color(0xFFF4EAD2)),
    PixelLayer('M2 7h1v4H2z M13 7h1v4h-1z', Color(0xFF6B3F1D)),
    PixelLayer('M4 9h2v2H4z', Color(0xFF7FD36B)),
    PixelLayer('M7 8h2v3H7z', Color(0xFF5FC9E8)),
    PixelLayer('M10 9h2v2h-2z', Color(0xFFF0B23C)),
    PixelLayer('M1 11h14v3H1z', Color(0xFFC98A4B)),
    PixelLayer('M1 11h14v1H1z', Color(0xFFE8B070)),
    PixelLayer('M1 13h14v1H1z', Color(0xFF8A5A2B)),
  ];

  /// 필드 오른쪽 위 가방 아이콘.
  static const List<PixelLayer> fieldBag = [
    PixelLayer('M6 1h4v1h1v2h-1V2H6v2H5V2h1z', Color(0xFF5C3415)),
    PixelLayer('M4 4h8v1h1v9h-1v1H4v-1H3V5h1z', Color(0xFFB0703A)),
    PixelLayer('M3 5h10v3H3z', Color(0xFF8A5226)),
    PixelLayer('M4 4h2v1H4z M4 9h1v3H4z', Color(0xFFE0A060)),
    PixelLayer('M5 10h6v3H5z', Color(0xFFC98A4B)),
    PixelLayer('M5 10h6v1H5z', Color(0xFF8A5226)),
    PixelLayer('M7 7h2v2H7z', Color(0xFFFFD479)),
  ];

  /// 필드 오른쪽 위 출석부(달력) 아이콘.
  static const List<PixelLayer> fieldCalendar = [
    PixelLayer('M2 3h12v12H2z', Color(0xFFFFFAF0)),
    PixelLayer('M2 3h12v4H2z', Color(0xFFE2574C)),
    PixelLayer('M2 14h12v1H2z', Color(0xFFC9B89A)),
    PixelLayer('M4 1h2v4H4z M10 1h2v4h-2z', Color(0xFF5C3415)),
    PixelLayer('M4 8h2v2H4z M7 8h2v2H7z M4 11h2v2H4z', Color(0xFFC9B89A)),
    PixelLayer('M10 8h2v2h-2z M7 11h2v2H7z M10 11h2v2h-2z', Color(0xFFF0B23C)),
  ];

  /// 필드 오른쪽 위 습관(퀘스트 두루마리 + 추가) 아이콘.
  static const List<PixelLayer> fieldQuest = [
    PixelLayer('M3 2h10v12H3z', Color(0xFFF4EAD2)),
    PixelLayer('M2 1h12v2H2z M2 13h12v2H2z', Color(0xFFC98A4B)),
    PixelLayer('M2 2h12v1H2z M2 14h12v1H2z', Color(0xFF8A5A2B)),
    PixelLayer('M5 5h6v1H5z M5 7h4v1H5z', Color(0xFF8A5A2B)),
    PixelLayer('M9 8h3v2h2v3h-2v2H9v-2H7v-3h2z', Color(0xFF3F8F3A)),
    PixelLayer('M10 9h1v2h2v1h-2v2h-1v-2H8v-1h2z', Color(0xFFFFFAF0)),
  ];

  /// 골드 칩 안의 + (골드 얻는 법).
  static const String plus = 'M6 2h4v4h4v4h-4v4H6v-4H2V6h4z';

  /// 가방 창 머리 아이콘.
  static const List<PixelLayer> bagHeader = [
    PixelLayer('M6 1h4v1h1v2h-1V2H6v2H5V2h1z', Color(0xFF5C3415)),
    PixelLayer('M4 4h8v1h1v9h-1v1H4v-1H3V5h1z', Color(0xFFD89058)),
    PixelLayer('M3 5h10v3H3z', Color(0xFF8A5226)),
    PixelLayer('M5 10h6v3H5z', Color(0xFFE8B070)),
    PixelLayer('M7 7h2v2H7z', Color(0xFFFFD479)),
  ];

  static const String heart = 'M2 3h4v1h4V3h4v1h1v5h-1v1h-1v1h-1v1h-1v1h-1v1H6v-1H5v-1H4v-1H3v-1H2V9H1V4h1z';
  static const String star = 'M7 0h2v4h5v2h-2v2h1v6h-2v-2H5v2H3V8h1V6H2V4h5z';
  static const String coin = 'M5 1h6v1h2v2h1v8h-1v2h-2v1H5v-1H3v-2H2V4h1V2h2z';
  static const String coinBand = 'M7 4h2v8H7z';

  /// 교감 감정 말풍선 · 기분 아이콘. 시안의 `EMO`.
  static const Map<String, PixelLayer> emotes = {
    'heart': PixelLayer(heart, Color(0xFFFF6B8A)),
    'note': PixelLayer('M8 2h5v2h-3v8H9v1H6v-1H5v-2h1V9h2V2z', Color(0xFF6D5EC4)),
    'sweat': PixelLayer('M7 1h2v2h1v2h1v1h1v2h1v4h-1v2h-1v1H5v-1H4v-2H3V8h1V6h1V5h1V3h1z', Color(0xFF5FC9E8)),
    'spark': PixelLayer('M7 1h2v4h2v2h4v2h-4v2H9v4H7v-4H5V9H1V7h4V5h2z', Color(0xFFF0B23C)),
    'dots': PixelLayer('M2 7h3v3H2z M7 7h3v3H7z M12 7h3v3h-3z', Color(0xFF7A6A60)),
  };

  /// 쓰다듬는 손 (교감 창 커서 · 액션 버튼).
  static const String handPath = 'M4 2h2v6H4z M6 1h2v7H6z M8 2h2v6H8z M10 3h2v6h-2z M3 7h10v5h-1v2H5v-1H4v-1H3z M1 6h2v1h1v3H3V9H2V8H1z';
  static const List<PixelLayer> hand = [
    PixelLayer(handPath, Color(0xFFFFE0C2)),
    PixelLayer('M5 11h7v1H5z M5 13h7v1H5z', Color(0xFFE0A878)),
  ];
  static const List<PixelLayer> actionPet = [
    ...hand,
    PixelLayer('M6 2h1v1H6z', Color(0xFFFFFFFF)),
  ];
  static const List<PixelLayer> actionSnack = [
    PixelLayer('M6 1h4v2h-1v2h3v1h1v8h-1v1H4v-1H3V6h1V5h3V3H6z', Color(0xFF7FD36B)),
    PixelLayer('M6 1h4v2H6z', Color(0xFF8A5A2B)),
    PixelLayer('M5 8h2v4H5z', Color(0xAAFFFFFF)),
  ];
  static const List<PixelLayer> actionPlay = [
    PixelLayer(coin, Color(0xFFFFFFFF)),
    PixelLayer('M5 1h6v1h2v2h1v3H2V4h1V2h2z', Color(0xFFFF8A4C)),
    PixelLayer('M2 7h12v2H2z', Color(0xFF3A1F1A)),
  ];
  static const List<PixelLayer> actionTalk = [
    PixelLayer('M1 2h14v9H8v1H7v1H6v1H4v-3H1z', Color(0xFFFFFAF0)),
    PixelLayer('M4 6h2v2H4z M7 6h2v2H7z M10 6h2v2h-2z', Color(0xFF3A1F1A)),
    PixelLayer('M2 3h3v1H2z', Color(0xFFFFFFFF)),
  ];

  /// 하단 탭 아이콘. 시안의 `ICON`.
  static const List<String> nav = [
    'M7 1h2v1h1v1h1v1h1v1h1v1h1v2h-1v6H9v-4H7v4H3V8H2V6h1V5h1V4h1V3h1V2h1z',
    'M1 2h14v9H8v1H7v1H6v1H4v-3H1z',
    'M1 13h14v2H1z M2 8h3v4H2z M7 4h3v8H7z M12 1h3v11h-3z',
    'M1 2h6v1h2V2h6v12H9v1H7v-1H1z M3 4v8h4V4z M9 4v8h4V4z',
    'M1 2h3v3H1z M6 2h9v2H6z M1 7h3v3H1z M6 7h9v2H6z M1 12h3v3H1z M6 12h9v2H6z',
  ];

  /// 배경음악 버튼: 스피커 몸통 + 소리 물결 / 음소거 X.
  static const String speaker = 'M1 6h3v4H1z M4 5h1v6H4z M5 4h1v8H5z M6 3h2v10H6z';
  static const String speakerWaves = 'M10 6h1v4h-1z M12 4h1v8h-1z M14 2h1v12h-1z';
  static const String speakerMute = 'M10 5h2v2h-2z M14 5h2v2h-2z M12 7h2v2h-2z M10 9h2v2h-2z M14 9h2v2h-2z';

  /// 설정 톱니바퀴 (구멍은 배경색으로 한 겹 더).
  static const String gear =
      'M7 1h2v2h2V2h1v1h1v1h-1v2h2v2h-2v2h1v1h-1v1h-1v-1h-2v2H7v-2H5v1H4v-1H3v-1h1V9H2V7h2V5H3V4h1V3h1v1h2z';
  static const String gearHole = 'M7 6h2v1h1v2H9v1H7V9H6V7h1z';
}
