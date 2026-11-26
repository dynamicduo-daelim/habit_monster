# 퀘스트 시스템 — 단계별 할 일

기획서: [`기획/2026-11-12-퀘스트-시스템.md`](../기획/2026-11-12-퀘스트-시스템.md) (v2.2, 결정 D-83 · 보상 선물함 D-89) · 브랜치 `feature/quest` (11-25, `origin/dev`에서 땀)

범위가 커서 **혼자 배포할 수 있는 단계**로 나눴다. 각 단계는 자기 명세 · DB 변경 제안을 함께 가진다
(명세 · DB는 윤서 문서 — Claude는 `docs/제안/`에 제안서를 쓰고, 승인 뒤 반영한다).

## 단계

| 단계 | 파일 | 내용 | 상태 |
| --- | --- | --- | --- |
| 1 | [1-DRAG.md](1-DRAG.md) | 필드 끌기 호감도 DRAG 되살리기 (D-46). 퀘스트와 독립, 혼자 배포 가능 | 서버 끝(11-25) — 명세 v7 · DB v1.10 · 서버 · 테스트. 남은 것: 배포 · 앱(프론트 담당) |
| 2 | [2-기반-일일퀘스트.md](2-기반-일일퀘스트.md) | `quest` 스키마 · 원장 사유 · 이벤트 연결 · `GET /quests` · 일일 4개 · A3 잠금 | 서버 끝(11-25) — 명세 v8 · DB v1.11 · 서버 · 테스트 11개. 남은 것: 배포 · 앱(프론트 담당) |
| 3 | [3-주간퀘스트.md](3-주간퀘스트.md) | B1 주 4일 출석 · B2 80% 이상인 날 2일 · B3 카테고리 3곳(잠금) | 서버 끝(11-25) — 명세 v9 · DB v1.12 · 서버 · 테스트 8개. DB 적용 끝(11-26). 남은 것: 배포 · 앱 |
| 3.5 | [3.5-선물함.md](3.5-선물함.md) | 퀘스트 계열 보상을 선물함으로 (받기 · 모두 받기), 2 · 3단계 자동 지급을 바꿈. 4단계보다 먼저 (D-89) | 서버 끝(11-26) — 명세 v10 · DB v1.13 · Supabase · 로컬 DB 적용 · 서버 · 테스트 8개(전체 245) · 배포(PR #27). 남은 것: 앱 |
| 4 | [4-월간배지.md](4-월간배지.md) | 20개 완료 → 배지 + 성실볼(**선물함으로**) · `GET /quests/badges`. 3.5단계 뒤 | 서버 끝(11-26) — 명세 v11 · DB v1.14 · Supabase · 로컬 DB 적용 · 서버 · 테스트 9개(전체 254). D-91 카운터 · 볼 1개. 남은 것: 배포 · 앱 |
| — | | **여기까지 1차** | |
| 5 | [5-업적-칭호-1차.md](5-업적-칭호-1차.md) | 업적 일부 + `displayTitle`(최근 1개 자동) | |
| 6 | [6-깜짝퀘스트.md](6-깜짝퀘스트.md) | 하루 1 · 주 3 · 3G, `Dice` 한 번 굴려 저장 | |
| 7 | [7-조건깜짝퀘스트.md](7-조건깜짝퀘스트.md) | 기록 추가(상호작용 시각 · 파트너 이력 · 포획 실패) + 트리거 12종 | |
| 8 | [8-업적-나머지.md](8-업적-나머지.md) | 5단계에서 뺀 업적 | |

상태 칸: 비어 있음 → 할 차례 → 진행 중 → 끝 (날짜). 단계 안의 체크박스가 모두 [x]가 되면 "끝".

## 단계마다 공통으로 하는 것
1. 명세 · DB 제안서 (`docs/제안/`) → 사용자 확인 → 명세 · 스키마 · 시드 · `verify.sql` · 마이그레이션 SQL 반영
2. 서버 구현 + 테스트 (`backend/server/`에서 `.\gradlew.bat test`, Docker 필요)
3. 앱 전달분은 `frontend/서버연동-메모.md`에 (앱은 프론트 담당)
4. 기록: 작업-기록 일지 · 결정이 있으면 결정-기록 · `backend/README.md` API 표 · 이 표의 상태
5. 배포 전: 로컬 DB 마이그레이션 · Supabase 마이그레이션은 사용자가 실행

## 정한 것 (구현 방식)

| 무엇 | 정한 것 | 결정 |
| --- | --- | --- |
| 깜짝 퀘스트의 "다시 조회해도 같은 랜덤" | 시드 계산 대신 **그날 첫 조회 때 `Dice.roll()`을 한 번 굴리고 저장**. 일일 퀘스트 생성과 같은 트랜잭션. 동시 첫 조회는 유니크 키가 막는다 | D-84 |
| 퀘스트 진행을 올리는 방식 | 직접 호출 대신 **Spring 이벤트**(`publishEvent` → `@EventListener`), **동기 · 같은 트랜잭션** | D-85 |
| 잠금 순서 | **`gift(받기만) → habit_user → goal_user → monster_user → inventory → wallet → quest`** — 퀘스트는 항상 지갑을 먼저 잠근다 (D-85의 "퀘스트 → 지갑"은 체크인 경로 때문에 지킬 수 없어 바꿈). gift는 v1.13 (D-89) | D-87 · D-89 |
| 칭호 표시 | 최근 획득 1개 자동 | D-83 |
| 주간 진행도 | 알림 · 조회 때마다 이번 주 기록에서 다시 계산 (내려가지 않음) — 일일은 알림마다 +1 | D-88 |
| 보상 지급 | 사용자가 직접 한 요청의 결과로 보이는 보상(체크인 · 레벨업 · 기간 보너스 · 목표 · 탐색 중복)은 **즉시**, 퀘스트 계열(일일 · 주간 · 월간 · 업적 · 깜짝)은 **선물함 → 받기**. 잠금 순서에 `gift` 추가 예정 (퀘스트 경로는 `… → wallet → quest → gift`에 새 행만, 받기는 `gift → inventory → wallet` — 스키마 v1.13 원칙 3-1) | D-89 |

## 이벤트 목록 (보내는 곳 → 받는 곳)

이벤트 방식은 코드만 보면 흐름이 안 보이므로 여기에 모아 둔다. 단계가 진행되면서 채운다.

| 이벤트 | 보내는 곳 | 언제 | 받는 곳 (단계) |
| --- | --- | --- | --- |
| `checkin.CheckinSubmitted(userId, businessDate)` | `CheckinService.submit` 끝 (지갑 잠근 뒤) | 첫 제출만 (PUT 아님) | `DAILY_CHECKIN` (2) · 주간 다시 계산 (3) · 업적 (5) |
| `monster.AffectionGiven(userId, userMonsterId, action, businessDate)` | `MonsterService.affection` | 기록이 들어갔을 때만 (409 · DRAG 두 번째는 안 보냄) | `DAILY_PET`(PET만) (2) · 업적 · 깜짝 (5 ~ 7) |
| `monster.MonsterTalked(userId, userMonsterId, businessDate)` | `MonsterService.line` | 성공 | `DAILY_TALK` (2) · 깜짝 (6 · 7) |
| `habit.TimerStopped(userId, habitId, businessDate, minutes, endReason)` | `TimerService.stop` (USER · MAX_DURATION · HABIT_STOPPED) | 탈퇴 정리는 안 보냄 · 날짜는 끝난 날 | `DAILY_TIMER` (2) · 업적 (5) |
| `habit.Attended(userId, businessDate)` | `HabitService.attend` | 그날 첫 출석만 | 주간 `WEEKLY_ATTEND` (3) · 업적 (5) |
| `MonsterFed` · `Explored` · `CaptureTried` · `ItemPurchased` · `PartnerChanged` · `MonsterMoved` · `CategoryUnlocked` · `DexViewed` · `GoalCompleted` · `HabitPeriodCompleted` (안) | 각 모듈 | | 5 ~ 8 |

## 정할 것
- 1차(1 ~ 4단계)까지를 발표 범위로 할지
- 5단계 업적을 어디까지 넣을지 (5단계 파일 참고)
