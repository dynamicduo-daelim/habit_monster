#!/bin/sh
# Docker PostgreSQL이 처음 뜰 때 한 번만 실행된다 (데이터 볼륨이 비어 있을 때).
# 공식 스키마(v1.7~)는 저장소 밖(공유 폴더)에 있어서 /hm-official 로 연결해 둔다 — backend/docker-compose.yml
# (서버용 추가 테이블은 v1.7부터 공식 schema.sql에 들어 있다: api.idempotency_record)
set -e

run() {
  echo "[habit-monster] 적용: $1"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$1"
}

if [ ! -f /hm-official/schema.sql ]; then
  echo "[habit-monster] /hm-official/schema.sql 이 없어요. backend/.env 의 HM_DB_DIR(공유 폴더 경로)을 확인하세요." >&2
  exit 1
fi

run /hm-official/schema.sql
if [ -f /hm-official/seed.sql ]; then
  run /hm-official/seed.sql
else
  echo "[habit-monster] seed.sql 이 없어서 건너뜀 (카테고리 · 몬스터 마스터 데이터가 비어 있음)"
fi
