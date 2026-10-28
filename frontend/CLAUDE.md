# 습관 몬스터 — Claude Code 작업 안내

> **먼저 `frontend/서버연동-메모.md`를 읽는다.** 서버는 이미 바뀌었지만 앱은 아직 따라가지 않은 일(API · 화면)이 모여 있다.

## 목표
`docs/design/` 의 디자인 프로토타입을 **그대로** Flutter 앱(`frontend/`)으로 옮긴다.

## 디자인 기준 파일
- `docs/design/prototype-source.dc.html` — **이 파일을 기준으로 구현한다.** 화면 마크업(색·크기·여백·문구)과
  동작 로직(state, 메서드, renderVals)이 모두 들어 있다. 이미지 경로는 `frontend/` 기준.
- `docs/design/habit-monster-prototype.html` — 같은 내용을 브라우저에서 바로 실행하는 버전 (6MB, 코드 읽기용 아님).
- `docs/economy-v1.md` — 골드·EXP·호감도 수치 근거. 코드는 `lib/core/constants/economy.dart`.
- `docs/habit-monster-기획서-v2.md` — 기획서.

## 이미 있는 것 (frontend/lib)
- `core/theme/app_colors.dart` 색 토큰, `core/constants/app_assets.dart` 이미지 경로, `economy.dart` 수치
- `core/widgets/pixel_widgets.dart` PixelPanel · PixelButton · CoinChip · BallChip · PixelImage
- `core/widgets/sprite_sheet.dart` 박사 스프라이트 재생 (6×6 시트, 프레임 208×380)
- `core/state/game_state.dart` GameState(ChangeNotifier) + GameScope
- `data/models.dart`, `data/catalog.dart` 카테고리 · 도감 · 상점 · 대사
- `core/widgets/pixel_icon.dart` 시안의 픽셀 SVG path를 그리는 PixelIcon (path 데이터는 `data/pixel_icons.dart`)
- `features/` onboarding(인트로 + 1~3단계) · shell(상단 바 + 탭 5개 + `MainShell.of(context)`로 탭 이동/토스트)
  · home(필드 · 말풍선 · 슬라이드 시트 · 상점/가방/교감 창) · dex(도감) · goals(목표)
  · chat(대본형 습관 체크 + 탐색, 대사는 `ChatBrain`) · stats(통계 — 탭을 열 때마다 `GameRepository.loadStats`)
  · tutorial(온보딩 직후 홈을 짚어 주는 `TutorialOverlay`, 설정에서 다시 보기) · home의 출석부(`attendance_popup.dart`)
- `core/widgets/help_button.dart` 낯선 말 옆 ? 버튼 `HelpButton` + 설명 창 `showInfoPopup` (시안에 없는 추가 기능)
- **상태를 바꿀 땐 `GameRepository`**(`core/state/game_repository.dart`)로: 화면에서는 `runGameAction(context, (repo) => repo.buy(…))`.
  `GameState`의 규칙 메서드를 화면에서 직접 부르지 않는다 (서버 모드에서 서버를 거치지 않게 됨). 게임 API 통신은 `core/api/ApiClient`
  (Bearer · `Idempotency-Key` · 만료 시 재발급 · 같은 키 재시도). 새 동작을 만들면 `GameRepository`에 메서드를 추가하고 `LocalGameRepository`에서 `GameState` 규칙을 부른다.
  서버 구현 `HttpGameRepository`(10-18~): `load` · `attend` · `completeOnboarding` · 체크인(`confirmCheckin` · `resubmitCheckin`, 10-19) · 탐색(`explore` · `throwBall(EncounterResult)` · `pendingEncounter`, 10-20) · 성장(`buy` · `feed` · `pet` · `play` · `moveMonster` · `setPartner` · `talk`, 10-21) · 목표(`addGoal` · `updateGoal` · `deleteGoal` · `completeGoal`, 10-28) · 도감 · 카테고리 열기(`load`의 도감 · `openCategory`, 10-28) · 통계(`loadStats`, 10-28)는 서버로, 나머지(습관)는 `LocalGameRepository`에 넘기며 단계마다 옮긴다 (남은 것은 `frontend/서버연동-메모.md`). `dragMonster`(필드 끌기 호감도)는 서버 모드에서 0 (D-46).
  서버 모드 챗봇은 `GameState.checkinHabits`(서버가 정한 오늘 대상)를 묻고, 입력값은 `GameState.recordableValue`로 서버 선택지 중 가장 가까운 값에 맞춘다 (D-42 — 나중에 입력값 그대로 받으려면 이 함수만).
  서버 모드는 `GameState.empty()`로 시작해 `GameLoader`가 `load()` 뒤 홈을 그린다. 서버 응답은 `GameState.apply…`로 옮긴다 (규칙 메서드에 서버 값을 넣지 않기).
  위젯 테스트는 `test/game_harness.dart`의 `withGame(state, child)`로 감싼다. 서버 연동은 `test/http_game_repository_test.dart`처럼 MockClient로.
- 앱의 코드(카테고리 · 몬스터 종 id · 측정 항목 순서 · 상점은 `Catalog.serverCodeOf`)는 **DB 시드와 같아야 한다** (서버가 이 코드로 응답한다)
- 서버·AI 연동 지점: `backend/README.md`의 "프론트 연동 지점" · "AI 챗봇 연결"

## 구현 순서
1. 온보딩 1~3단계: 카테고리 + 첫 파트너 → 습관 퀘스트 등록 → 목표 세우기
2. 홈: 슬라이드 시트(습관 리스트/오늘의 성실도), 호감도별 말풍선, 가방, 몬스터 교감 창
   상점: 가격 버튼 → '몇 개 살까?' 수량 팝업(−/+ · 1/5/10/최대 · 합계) → '구매 완료!' 팝업 (몬스터에게 주기 / 확인)
   (톡 건드리기 · 쓰다듬기(문지르기 게이지, 하루 1회 ♥+2) · 간식 주기 · 놀아주기(하루 1회 ♥+1) · 말 걸기)
3. 챗봇 습관 체크 + 탐색 화면
4. 도감 (카테고리 파스텔 배경 · 도감 5/10/15마리마다 카테고리 슬롯 +1 → `Economy.categorySlots`) · 목표 체크리스트(수정/삭제) · 통계
5. 로컬 저장 → 백엔드 연동 (`backend/README.md` API 초안)

## 규칙
- 픽셀 이미지는 항상 `FilterQuality.none` (PixelImage 위젯 사용)
- 폰트는 Galmuri11, 색은 AppColors만 사용
- 수치를 하드코딩하지 말고 `Economy` 상수 사용
- 새 패키지를 넣을 땐 이유를 먼저 설명
