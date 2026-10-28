# 루틴몬 (구 습관 몬스터, habit_monster)

습관 관리 몬스터 육성 앱 (졸업프로젝트2)

매일 습관을 체크하면 성실도가 쌓이고, 그 골드로 몬스터를 키우는 픽셀 게임형 습관 앱.
체크인 뒤 탐색으로 새 몬스터를 만나 잡고, 도감을 채우면 새 습관 카테고리가 열려요.

```
habit_monster/
├─ frontend/          Flutter 앱 (Android · iOS · 웹은 로컬 확인용)
│  ├─ assets/
│  │  ├─ images/monsters/     몬스터 그림 (도감은 28종, 카테고리 6개 — 운동 · 공부 · 식습관 · 명상 · 수면 · 절약)
│  │  ├─ images/characters/   대림대 박사 스프라이트 시트(6×6) · 상점 주인
│  │  ├─ images/items/        물약 하급/중급/상급 · 성실볼
│  │  ├─ images/backgrounds/  홈 초원 배경 · images/brand/ 로고
│  │  └─ fonts/               갈무리11 (OFL 라이선스 동봉)
│  ├─ lib/
│  │  ├─ core/        테마 · 색 · 경제 수치 · 공용 위젯 · 게임 상태(GameState) · 서버 통신(ApiClient · GameRepository)
│  │  ├─ data/        모델(습관/몬스터/아이템/목표) · 고정 데이터(카테고리 · 도감 · 상점 · 대사)
│  │  └─ features/    auth · onboarding · shell(상단 바+탭) · home · chat · goals · dex · stats · tutorial
│  └─ test/
├─ backend/           서버 — Spring Boot 4 · Java 21 · PostgreSQL
│  ├─ server/         API 서버 (모든 경로 /api/v1)
│  ├─ db/             DB 설명 · 다음 판에 넣을 것
│  └─ docker-compose.yml   로컬 DB (포트 5435)
└─ docs/
   ├─ README.md                 문서 지도 (어디에 무엇이 있는지)
   ├─ 프로젝트-이해.md           전체 그림 · 용어
   ├─ api/ · 데이터베이스/       API 명세 v5 · DB 스키마 v1.7 + 시드 v1.8
   ├─ 기획/ · 결정-기록.md       기능 기획서 · 정한 것과 이유
   ├─ 작업-기록.md · 할-일.md    날짜별 작업 일지 · 남은 일
   ├─ design/                   디자인 프로토타입 (브라우저로 열기)
   └─ economy-v1.md             골드 · 경험치 수치 설계
```

## 실행 방법

앱은 두 가지로 돌릴 수 있어요. 화면은 같고, 데이터를 어디서 가져오는지만 달라요.

| | 서버 모드 | 시연 모드 |
| --- | --- | --- |
| 실행할 때 | `--dart-define=API_BASE_URL=…`을 붙임 | 아무것도 안 붙임 |
| 데이터 | 로그인한 내 데이터 (서버 DB에 저장) | 앱 안의 샘플 (DAY 12 · 1,240G), 끄면 사라짐 |
| 필요한 것 | Docker DB + 서버 | Flutter만 |

> 샘플 데이터(DAY 12 · 연속 11일)가 보이면 `API_BASE_URL` 없이 실행한 시연 모드예요.

### 0. 준비물 (처음 한 번)
- Flutter (`flutter --version`), JDK 21 이상 (서버), Docker Desktop (DB)
- `frontend/`에서 `flutter pub get`
- `backend/.env.example`을 `backend/.env`로 복사하고 `HM_DB_DIR`(= 저장소의 `docs/데이터베이스` 절대 경로) · `DB_PORT=5435`를 적기 (`.env`는 커밋 금지)

### 1. 서버 켜기 (서버 모드일 때만)

```bash
# backend/ — DB (PostgreSQL, 포트 5435)
docker compose up -d

# backend/server/ — 서버 (포트 8081, PowerShell이면 .\gradlew.bat)
./gradlew bootRun --args='--spring.profiles.active=local'
```

- "Tomcat started on port 8081"이 보이면 준비 끝. 확인: `curl localhost:8081/api/v1/auth/login` → 400대 오류면 서버는 떠 있는 것
- DB 구조가 바뀐 뒤(새 커밋을 받은 뒤) 서버가 안 뜨면 `backend/db/README.md`의 반영 SQL을 실행하거나 `docker compose down -v && docker compose up -d`로 DB를 다시 만들어요 (로컬 데이터는 지워짐)
- 포트: DB 5435 · 서버 8081 (5432 ~ 5434 · 8080은 이 PC의 다른 프로젝트가 써요)

### 2. 앱 실행 — 보는 방법별 (`frontend/`에서)

#### A. 웹 (Chrome) — 가장 빠르게 화면 확인
```bash
# 서버 모드
flutter run -d chrome --web-port=5000 --dart-define=API_BASE_URL=http://localhost:8081/api/v1
# 시연 모드
flutter run -d chrome
```
- 서버 모드는 **포트 5000 고정** — 서버가 `http://localhost:5000`에서 온 요청만 허용해요 (CORS, `local` 프로필).
- 웹에서는 **카카오 · 구글 로그인이 안 돼요** → 이메일로 가입 · 로그인.
- 브라우저를 직접 열고 싶으면 `-d chrome` 대신 `-d web-server --web-port=5000`을 쓰고 `http://localhost:5000`을 열어요.

#### B. 안드로이드 에뮬레이터
```bash
flutter emulators                        # 에뮬레이터 목록
flutter emulators --launch <에뮬레이터 id>  # 켜기 (Android Studio의 Device Manager로 켜도 됨)
flutter devices                          # 잡혔는지 확인

# 서버 모드 — 에뮬레이터 안에서 PC는 10.0.2.2
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8081/api/v1
# 시연 모드
flutter run
```
- 첫 빌드는 오래 걸려요 (몇 분 ~ 10분대). 기기가 여러 개면 `-d <기기 id>`로 고르기.
- 카카오 · 구글 로그인은 에뮬레이터에서 끝까지 확인하지 못했어요 (Google Play 서비스 버전 문제). 이메일 로그인은 돼요.

#### C. 실제 안드로이드 폰 (USB 디버깅)
1. 폰: 설정 → 휴대전화 정보 → 소프트웨어 정보 → 빌드 번호 7번 눌러 개발자 모드 → 개발자 옵션 → **USB 디버깅 켜기**
2. USB로 PC에 연결 → 폰의 "USB 디버깅 허용" 팝업에서 허용
3. `adb devices` 또는 `flutter devices`로 폰이 보이는지 확인
4. 서버 모드면 **폰의 localhost:8081을 PC로 연결** (폰에서는 `10.0.2.2`가 안 돼요)
   ```bash
   adb reverse tcp:8081 tcp:8081
   flutter run --dart-define=API_BASE_URL=http://localhost:8081/api/v1
   ```
   시연 모드면 `flutter run`만.
- 케이블이 빠지거나 adb가 끊기면 `adb reverse`도 풀려요 → 다시 걸기. 서버에 안 붙으면 이것부터 확인.
- 실행 중 단축키 (터미널): `r` 화면 새로 그리기(hot reload), `R` 처음부터 다시(hot restart), `q` 끝내기.

### 3. 테스트
- 앱: `frontend/`에서 `flutter analyze` → `flutter test`
- 서버: `backend/server/`에서 `./gradlew test` (Docker가 켜져 있어야 해요 — 테스트용 DB를 스스로 띄움)

더 자세한 서버 설정(환경변수 · 프로필 · CORS)은 `backend/server/README.md`, DB는 `backend/db/README.md`.

## 지금 만들어진 것

- **앱 화면**: 로그인(카카오 · 구글 · 이메일) → 박사 인트로 · 온보딩(카테고리 + 첫 파트너 → 습관 → 목표) → 튜토리얼,
  홈(몬스터가 돌아다니는 필드 · 상점 · 가방 · 교감 · 출석부), 챗봇(습관 체크 → 탐색 · 포획), 목표, 도감(본 종 · 실루엣 · 카테고리 열기), 통계
- **서버 (`feature/backend-game-system`)**: 회원 · 토큰 · 탈퇴, 온보딩 · 출석, 메인 조회, 체크인(점수 · 골드 · 카테고리 경험치 · 기간 보너스),
  탐색 · 포획, 상점 · 물약 · 교감, 습관 추가 · 연장 · 그만두기, 목표, 도감 · 카테고리 열기, 통계 — 앱은 서버 모드에서 이 API로 동작
- **테스트**: 서버 150개 (실제 PostgreSQL 위에서) · 앱 130개 (10-28 기준)

## 다음에 만들 것

- 습관 화면의 서버 연결 · 기간 연장 화면 (프론트 담당 — `frontend/서버연동-메모.md`)
- 5단계: AI 대사(체크인 대사를 서버에서 LLM으로) · 21시 알림
- 6단계: 서버 배포 · HTTPS · 릴리스 서명 · 스토어 등록
- 전체 목록은 `docs/할-일.md`, 진행 상황은 `docs/진행현황-및-계획.md`
