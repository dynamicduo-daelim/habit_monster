# 1단계 — 필드 끌기 호감도 DRAG 되살리기

## 목표
홈 필드에서 몬스터를 끌어 옮기면(DRAG) 서버 모드에서도 몬스터마다 하루 1번 호감도 +1.
지금은 명세 · DB에 DRAG가 없어 서버 모드에서는 안 오른다 (D-46). 퀘스트(2 · 6단계) · 업적(5단계)도 이 기록을 쓴다.
퀘스트와 독립이라 **이 단계만 먼저 배포할 수 있다.**

참고 체크리스트: `backend/db/제안-필드-끌기-호감도.md` (10-21 작성, 명세 v5 · 스키마 v1.7 기준 — 지금 판에 맞게 다시 확인)

## 명세 변경 제안 (v6 → v7) — 반영함 11-25
- [x] `POST /monsters/{id}/affection` 요청 `action`: `PET | PLAY | DRAG`
- [x] 이미 오늘 끌었을 때 응답 → **200 `gain: 0`** (오류 아님, D-86 · 11-25). PET · PLAY는 409 그대로
- [x] 제안서 작성 → [`제안/2026-11-25-DRAG-호감도.md`](../제안/2026-11-25-DRAG-호감도.md) (11-25). **윤서 확인 대기**
- [x] `GET /monsters/{id}` `todayActions`에 `drag`

## DB 변경 제안 (v1.9 → v1.10) — 반영함 11-25
- [x] `monster.affection_action.action_type` CHECK에 `'DRAG'` (하루 1번은 기존 기본 키가 막음)
- [x] 시드 `balance_config`: `affection_drag_gain = 1`
- [x] `verify.sql`: 설정 키 · DRAG 하루 1회 (200개 통과)
- [x] `backend/db/migrate-v1.10.sql` (v1.9 DB에 두 번 실행해 확인)
- [x] 간식(쿠키, D-79 · D-80): 아직 `affection_action`에 없음(CHECK는 PET · PLAY였음) → 이 판에 **넣지 않기로** (11-25)
- [x] 로컬 Docker DB에 `migrate-v1.10.sql` 적용 (11-25, Claude)
- [x] Supabase에 적용 (11-25, 사용자)

## 서버 할 일 — 끝 (11-25)
- [x] `config/BalanceConfig` — `affection_drag_gain`을 `REQUIRED`로 · `affectionDragGain()`
- [x] `monster/MonsterService.affection` — `DRAG` 허용, 이미 끌었으면 200 `gain 0`(PET · PLAY는 409 그대로), 주석 고침
- [x] `monster/MonsterService.monster` — `TodayActions.drag`
- [x] `backend/README.md` API 표

## 테스트 — 끝 (11-25)
- [x] `GrowthApiTest`: DRAG +1 · 두 번째 200 gain 0(기록 1줄) · PET과 별개 · 몬스터마다 · 다음 날 다시 · 최대 호감도 0 · 남의 몬스터 404 · 400(`FEED` · 소문자)
- [x] 전체 `.\gradlew.bat test` — 217개 통과

## 프론트 전달 — 적음 (`frontend/서버연동-메모.md` 7장), 앱 변경은 프론트 담당
- [ ] `http_game_repository.dart dragMonster`: `return 0` → `POST …/affection {action: DRAG}` · gain 0이면 조용히
- [ ] 불러오기 `todayActions.drag` → `OwnedMonster.draggedToday`

## 배포
- [ ] 서버 배포 (`dev`에 합친 뒤 CD — 사용자). DB는 Supabase 적용 끝이라 순서 문제 없음

## 완료 기준
- 서버 모드에서 끌면 몬스터마다 하루 1번 호감도 +1, 두 번째부터는 오류 토스트 없이 0
- 테스트 통과 · 로컬 DB 마이그레이션 적용 · 기록(작업-기록 · 결정-기록 · `프로젝트-이해.md` 297행 · `할-일.md` D-46 항목 [x])

## 정할 것
- ~~이미 끌었을 때 409 vs 200 `gain: 0`~~ → 200 `gain: 0` (D-86)
- ~~판 번호 · 간식 FEED~~ → v7 · v1.10, FEED 빼기 (11-25)
- ~~Supabase 반영 시점~~ → 11-25 적용함
