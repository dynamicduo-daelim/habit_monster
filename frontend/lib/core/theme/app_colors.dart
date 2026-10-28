import 'package:flutter/material.dart';

/// 디자인 시안(docs/design/habit-monster-prototype.html)에서 쓰던 색 토큰.
class AppColors {
  AppColors._();

  // 어두운 앱 프레임 (상단 바 · 하단 탭 · 챗봇/통계/목표 배경)
  static const Color night = Color(0xFF12101F);
  static const Color nightDeep = Color(0xFF0F0D1C);
  static const Color nightPanel = Color(0xFF141026);
  static const Color nightRaised = Color(0xFF191533);
  static const Color nightLine = Color(0xFF2B2545);
  static const Color nightLine2 = Color(0xFF3A3358);
  static const Color purple = Color(0xFF6D5EC4);
  static const Color purpleSoft = Color(0xFFC9B6FF);
  static const Color text = Color(0xFFE8E4F5);
  static const Color textMuted = Color(0xFF9B91C4);
  static const Color lockedMuted = Color(0xFF6B6390); // 통계: 열지 않은 카테고리 테두리 · 글자
  static const Color barShine = Color(0x33FFFFFF); // 통계: 막대 윗면 밝은 줄

  // 밝은 게임 UI (상점 · 가방 · 몬스터 정보 · 온보딩 카드)
  static const Color ink = Color(0xFF0D0B16);
  static const Color inkBrown = Color(0xFF3A1F1A);
  static const Color cream = Color(0xFFFFFAF0);
  static const Color parchment = Color(0xFFF4EAD2);
  static const Color wood = Color(0xFFC98A4B);
  static const Color woodDark = Color(0xFF8A5A2B);
  static const Color brownText = Color(0xFF2B1A1A);
  static const Color brownMuted = Color(0xFF7A6A60);

  // 포인트
  static const Color gold = Color(0xFFF0B23C);
  static const Color goldLight = Color(0xFFFFD479);
  static const Color goldDeep = Color(0xFFB85A00);
  static const Color yellowButton = Color(0xFFFFD24D);
  static const Color red = Color(0xFFD94A3D);
  static const Color redSoft = Color(0xFFE2574C);
  static const Color green = Color(0xFF7FD36B);
  static const Color heart = Color(0xFFFF6B8A);
  static const Color sky = Color(0xFF8FD3F4);

  // 온보딩 (보라 밤하늘 + 크림 카드)
  static const Color introSky = Color(0xFF1B1438);
  static const Color introFloor = Color(0xFF241A3D);
  static const Color introFloorDark = Color(0xFF2A1F48); // 인트로 바닥 체크무늬
  static const Color kakao = Color(0xFFFEE500); // 카카오 로그인 버튼 (브랜드 색)
  static const Color purpleDeep = Color(0xFF2F2456);
  static const Color purpleCard = Color(0xFF3D2F6E);
  static const Color skyDot = Color(0x1FFFFFFF);
  static const Color butter = Color(0xFFFFE58A);
  static const Color butterText = Color(0xFF7A5A1A);
  static const Color skyCard = Color(0xFFCFE8FF);
  static const Color skyCardShadow = Color(0xFF7AA6C9);
  static const Color skyCardSelShadow = Color(0xFF5A8FC0);
  static const Color skyCardText = Color(0xFF3F5F7A);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color divider = Color(0xFFEADFC6);
  static const Color redShadow = Color(0xFF7A1F17);

  // 블록 버튼 그림자 · 비활성
  static const Color goldShadow = Color(0xFF8A5A1A); // 금색 큰 버튼
  static const Color yellowShadow = Color(0xFFB27A14); // 노란 버튼
  static const Color parchmentShadow = Color(0xFF8A7A6A);
  static const Color chipShadow = Color(0xFFC9B89A);
  static const Color tanShadow = Color(0xFFB08A5A);
  static const Color disabled = Color(0xFFE0D6BF);
  static const Color disabledShadow = Color(0xFFB8AB90);
  static const Color disabledText = Color(0xFF8A7A6A);

  // 홈 필드 · 슬라이드 시트
  static const Color fieldSky = Color(0xFF3A8FD6);
  static const Color sheetHandle = Color(0xFF4B4380);
  static const Color lavender = Color(0xFF8C7FC0);
  static const Color orange = Color(0xFFFF7A4D);
  static const Color notifyDot = Color(0xFFFF5A5A);
  static const Color scrim = Color(0xB30D0B16);

  // 호감도 단계 (서먹한 · 친해진 · 단짝)
  static const Color tierLow = Color(0xFF8C7FC0);
  static const Color tierMid = Color(0xFF5FC9E8);
  static const Color tierHigh = Color(0xFFFF6B8A);
  static const Color tierMidText = Color(0xFF2F7FA0);
  static const Color tierHighText = Color(0xFFD94A6A);
  static const Color heartHalf = Color(0xFFFFB3C4);

  // 상점 · 가방 · 몬스터 정보 (나무/가죽 톤)
  static const Color shopCloth = Color(0xFFF4E2C0);
  static const Color shopClothLine = Color(0xFFE6CF9F);
  static const Color paper = Color(0xFFFFF3DC);
  static const Color woodDeep = Color(0xFF5C3415);
  static const Color woodLight = Color(0xFFE8B070);
  static const Color leather = Color(0xFFB0703A);
  static const Color stitch = Color(0xFFF4D9B0);
  static const Color tabOff = Color(0xFFE0B884);
  static const Color slotInset = Color(0xFFE0C79A);
  static const Color slotEmpty = Color(0xFFEFDCB4);
  static const Color brownShadow = Color(0xFFC9A46A);
  static const Color offWhite = Color(0xFFF4F1E6);
  static const Color checker = Color(0xFFEBE4D2);
  static const Color grassCard = Color(0xFFCFEEC0);
  static const Color grassCardDark = Color(0xFFC2E6B2);
  static const Color footnoteBrown = Color(0xFF7A5A3A);
  static const Color expBlue = Color(0xFF5FC9E8);
  static const Color fieldGreen = Color(0xFF3F8F3A);
  static const Color feedEmpty = Color(0xFFEFE6D2);
  static const Color bagCard = Color(0xFFF6ECD6);
  static const Color mutedOnBrown = Color(0xFFD8CDB5);

  // 교감 무대
  static const Color horizon = Color(0xFFB9E7F6);
  static const Color grass = Color(0xFF86D06A);
  static const Color grassDark = Color(0xFF7CC560);
  static const Color grassLine = Color(0xFF5FB158);

  // 도감
  static const Color dexLens = Color(0xFF7FE3FF);
  static const Color dexLensDark = Color(0xFF3FB0D6);
  static const Color dexLensLight = Color(0xFFE6FBFF);
  static const Color dexLightRed = Color(0xFFFF8A8A);
  static const Color dexUnknown = Color(0xFFA8997F);
  static const Color dexSlotQ = Color(0xFFCBBD9F);
  static const Color dexPortraitQ = Color(0xFF9FC79A);
  static const Color dexRowAlt = Color(0xFFF6EEDB);
  static const Color dexFootnote = Color(0xFF4A3A30);

  // 목표
  static const Color goalDoneCard = Color(0xFFE9E2CF);
  static const Color goalTagBorder = Color(0xFFCDBF9F);

  // 챗봇 · 탐색
  static const Color chatMeBubble = Color(0xFF2A2140);
  static const Color chatSoftText = Color(0xFFC9C3E3);
  static const Color chatChip = Color(0xFF171331);
  static const Color bushDark = Color(0xFF3D8A3C);
  static const Color platformInset = Color(0xFF4F9E4A);
  static const Color ballOfferBg = Color(0xFFE9E2FF);

  // 구매 팝업 · 카테고리 슬롯
  static const Color scrimLight = Color(0xA60D0B16);
  static const Color slotStepOff = Color(0xFF9A8A7A);
}
