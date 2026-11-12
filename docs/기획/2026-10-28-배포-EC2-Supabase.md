# 배포: 서버는 AWS EC2, DB는 Supabase (6단계 일부)

- 날짜: 2026-10-28
- 상태: 기획 중
- 관련: `feature/backend-game-system` · 진행현황 6단계 · 사용자 결정 10-28 (구성 B: EC2 + Supabase)

## 1. 왜 하나
- **목표**: 폰에서 USB · PC 없이 앱을 쓰고, 발표 때 실제 서버로 보여 준다.
- **하지 않는 것**: 서버를 Supabase 함수로 다시 짜기, AI 대사(5단계), 스토어 등록, 결제.
- **먼저 끝나야 할 것**: 4-1 습관 앱 서버 연결 (안 하면 배포해도 습관 추가 · 그만두기가 다시 켜면 사라짐) — 프론트 담당.

## 2. 구성
```
폰 앱 ──HTTPS(443)──▶ EC2 (Nginx → Spring Boot :8080) ──▶ Supabase PostgreSQL
                      api.habitmonster.me (탄력적 IP) + 인증서(Let's Encrypt)
```
> **현재 (11-12)**: 위 구성대로 동작 — `https://api.habitmonster.me/api/v1`. 8080 직접 접속은 아직 열려 있음 (8장).

| 부분 | 쓰는 것 | 비고 |
| --- | --- | --- |
| 서버 | EC2 무료 플랜 (리눅스, 작은 인스턴스) | Java 21 + 서버 jar, 껐다 켜도 다시 뜨게 (systemd) **[가정]** Docker 대신 jar 직접 실행 — 메모리 아끼려고 |
| DB | Supabase 무료 프로젝트 | `schema.sql` · `seed.sql`을 Supabase SQL 편집기로 적용 |
| HTTPS | 도메인 + Nginx + Let's Encrypt | 운영 빌드 앱은 http를 막음 (지금 http 허용은 debug만) |
| 앱 | 릴리스 빌드 APK | `API_BASE_URL=https://api.habitmonster.me/api/v1` |

## 3. 할 일 (순서)
1. **Supabase**: 프로젝트 만들기(서울 리전) → SQL 적용 → 서버용 연결 문자열 확인 (직접 연결 / 풀러 중 EC2에서 되는 것)
2. **EC2**: 인스턴스 · 보안 그룹(22 · 80 · 443만) · Java 21 · 결제 알림(Billing alert)
3. **서버 설정 (코드 변경 작음)**: 운영 환경변수 `DB_URL` · `DB_USER` · `DB_PASSWORD` · `JWT_SECRET`(새로 만든 긴 값) · `KAKAO_APP_ID` · `GOOGLE_CLIENT_IDS`. CORS는 끔(앱은 상관없음)
4. **HTTPS**: 도메인 연결 → Nginx 프록시 → 인증서
5. **앱**: 릴리스 서명 키 → 카카오 키 해시 · 구글 SHA-1 등록 → 릴리스 APK
6. **확인**: 가입 → 온보딩 → 체크인 → 탐색 → 목표 · 도감 · 통계를 폰(와이파이 · LTE)에서 한 바퀴

## 4. 예외 · 위험
- Supabase 무료는 오래 안 쓰면 멈춤 → 발표 전날 접속해 깨우기 **[확인 필요]**
- EC2 무료 플랜 기간 · 크레딧이 끝나면 요금 → 결제 알림 필수 **[확인 필요: 지금 AWS 무료 조건]**
- `schema.sql`의 DB 역할(`app_core` · `app_ai`) 만들기가 Supabase에서 되는지 **[확인 필요]** — 안 되면 사용자에게 제안 후 그 부분만 조정
- 작은 EC2의 메모리: 서버 최대 메모리를 정해 실행 (`-Xmx`) **[가정]**
- 비밀값(키 · 비밀번호)은 저장소에 넣지 않는다 — EC2의 환경 파일에만

### 4-1. 보안 주의점 (11-03 추가 — 지금은 HTTPS 전, 8080을 http로 열어 둔 상태)
| 무엇이 | 왜 위험한가 | 지금 할 것 / 할 때 |
| --- | --- | --- |
| **http (암호화 없음)** | 와이파이 · LTE 구간에서 로그인 비밀번호 · 토큰이 그대로 보인다. 토큰을 훔치면 그 사람으로 요청할 수 있다 | 테스트 계정만 쓴다 (실제 비밀번호 재사용 금지). 실사용 · 발표 전에 HTTPS(3장 4번) |
| **8080을 모든 IP(`0.0.0.0/0`)에 열어 둠** | 누구나 서버에 닿는다. 단 `/auth/**` 말고는 토큰이 있어야 해서 접속만으로 데이터가 열리지는 않는다 | 폰 IP는 LTE에서 계속 바뀌어 IP를 고정할 수 없어서 임시로 연 것. Nginx(80 · 443)가 생기면 **8080은 닫는다** |
| **22(SSH)** | 열려 있으면 비밀번호 · 키 대입 시도가 계속 들어온다 | 보안 그룹에서 **내 IP만** (집 IP가 바뀌면 다시 설정). 키 파일(.pem)은 저장소 · 메신저에 올리지 않는다 |
| **릴리스 빌드는 http를 막음** | 안드로이드 운영 빌드는 암호화 안 된 연결을 거부한다 (`usesCleartextTraffic`는 debug 설정에만) | http인 지금은 **debug 빌드로만** 폰 테스트 (`flutter run --dart-define=API_BASE_URL=http://<EC2 IP>:8080/api/v1`). 릴리스 APK는 HTTPS 뒤에 |
| **로그인 요청 횟수 제한 없음** | 이메일 로그인에 비밀번호를 계속 넣어 보는 공격을 막지 못한다 | 6단계(진행현황) · 7장 "정해야 할 것". 그때까지 테스트 계정 비밀번호는 길게 |
| **`JWT_SECRET`** | 이 값을 알면 누구의 토큰이든 만들 수 있다. 짧거나 예시 값이면 추측된다 | 새로 만든 **긴 무작위 값**(32바이트 이상)을 EC2 환경 파일에만. 바꾸면 기존 로그인이 모두 풀린다 (알고 바꿀 것) |
| **`DB_PASSWORD` (Supabase)** | DB에 바로 접속해 모든 데이터를 읽고 바꿀 수 있다 | EC2 환경 파일에만. 유출이 의심되면 Supabase에서 비밀번호 재설정 → EC2 값 바꾸고 서버 다시 시작 |
| **Supabase RLS 경고** | Supabase는 `public` 스키마 테이블을 앱 키(anon)로 읽을 수 있어서 RLS를 권한다 | **무시해도 된다** — 우리 앱은 anon 키를 쓰지 않고(서버만 DB 비밀번호로 접속), 테이블도 `public`이 아닌 모듈 스키마에 있다 |
| **카카오 · 구글 값** | 앱 ID(`KAKAO_APP_ID`) · 클라이언트 ID(`GOOGLE_CLIENT_IDS`)는 공개돼도 되는 값이지만, **카카오 REST · Admin 키 · 구글 client secret은 비밀** | 비밀 값은 어디에도 넣지 않는다 (서버는 토큰 검증에 공개 값만 씀). 두 ID가 EC2에 없으면 소셜 로그인이 실패한다 |
| **`GEMINI_API_KEY` (AI 챗봇, `feature/ai-chatbot-study-timer`)** | 키가 새면 남이 우리 요금으로 호출한다 | EC2 환경 파일에만 (앱 · 저장소에 넣지 않음, `.env`는 `.gitignore`). 하루 호출 한도가 지금은 서버 메모리라 서버를 다시 켜면 초기화된다 |

## 5. 영향
- 서버: 운영 설정(환경변수) — 코드 변경은 거의 없음 **[가정]**. 로그인 요청 횟수 제한은 이번에 넣을지 8장에서
- 앱: 릴리스 빌드 설정 · 서명 키(커밋 금지)
- 문서: 배포 방법을 `backend/server/README.md`에, 결정 기록, 루트 README 실행 방법에 "배포 서버로 보기"

## 6. 완료 기준
- [ ] 폰에서 USB 없이 `https://<도메인>/api/v1`로 가입부터 통계까지 한 바퀴
- [ ] EC2를 다시 시작해도 서버가 저절로 뜸
- [ ] 저장소에 비밀값 없음, 결제 알림 걸림

## 7. 정해야 할 것
- [x] 도메인: 사서 쓸지(연 1~2만 원대) / 무료 도메인 · 무료 하위 도메인 서비스 **[가정: 사서 쓰기]** → GitHub 학생 혜택으로 받은 `habitmonster.me`, 서버는 `api.` 하위 도메인 (11-12, D-70)
- [ ] AWS · Supabase 계정은 누구 것으로 (사용자가 직접 만들고, Claude는 명령 · 설정만 안내)
- [ ] 4-1 습관 앱 연결을 배포 전에 누가 언제
- [ ] 로그인 요청 횟수 제한 · 카카오 연결 끊기(6단계)를 이번에 같이 할지
- [ ] AWS 콘솔 작업처럼 Claude가 직접 할 수 없는 단계는 사용자가 하고, Claude는 단계별 안내 문서를 쓴다 **[가정]**

## 8. 결과 (구현 뒤에 쓴다)

### 2026-11-11 — EC2 서버를 systemd 서비스로 (D-65)
- 그전: `export`로 비밀값을 넣고 `nohup java -jar ~/app-new.jar &`로 손으로 띄움 → SSH를 새로 열 때마다 다시 입력, 11-06에 **메모리 부족으로 강제 종료**된 뒤 11-11까지 꺼져 있었다.
- 지금: 서비스 `habit-monster` (`Restart=on-failure`, 부팅 시 시작), 비밀값은 `/etc/habit-monster/app.env`(root 600), `-Xmx256m`, 포트 8080. 명령은 `backend/server/README.md` "EC2 배포 서버".
- 2장 표의 [가정] "systemd · jar 직접 실행" → 확정. 구성도의 `:8081`은 실제로는 **8080** (기본 프로필).
- 같은 날 `GEMINI_API_KEY` · `KAKAO_APP_ID` · `GOOGLE_CLIENT_IDS`도 넣음 (소셜 설정 · Gemini 키 유효 확인).
- 아직: HTTPS(도메인 · nginx 연결 — nginx는 80에 떠 있으나 서버로 넘기는 설정은 못 찾음), 재부팅 시험, 새 jar(v1.9) 배포.

### 2026-11-12 — 탄력적 IP · 도메인 · HTTPS (D-70)
- 사용자가 직접 함 (AWS 콘솔 · 도메인 사이트 · EC2 SSH), Claude는 단계 안내와 바깥에서 확인만.
- **탄력적 IP** `16.179.63.74`를 인스턴스에 연결 → 그전 퍼블릭 IP(`3.26.72.239`)는 반납돼 다시 못 씀. 예전 IP로 빌드한 앱은 다시 빌드해야 한다.
- **도메인** `habitmonster.me` (GitHub 학생 혜택), DNS A 레코드 `api` → 탄력적 IP.
- **보안 그룹**: 80 · 443 추가 (Anywhere-IPv4). 22는 내 IP, 8080은 아직 열림.
- **Nginx**: `/etc/nginx/sites-available/habit-monster` (→ `sites-enabled` 링크) — `server_name api.habitmonster.me`, `proxy_pass http://127.0.0.1:8080`, `proxy_read_timeout 30s` (Gemini 5초보다 넉넉히).
- **인증서**: `sudo certbot --nginx -d api.habitmonster.me` — Let's Encrypt(YE1), 유효 11-12 ~ **2027-02-10**, http → https 자동 전환.
- 확인 (Claude, 이 PC에서 11-12 13:48): `https://…/api/v1/me/status` → **401** `INVALID_TOKEN` JSON (Nginx → Spring까지 옴) · `http://` → **301** · 인증서 이름 `api.habitmonster.me` · DNS → `16.179.63.74`.
- 막혔던 것: ① PowerShell 5.1의 `curl`은 `Invoke-WebRequest` 별명이라 `-i`에서 `Uri:`를 물음 → `curl.exe` ② 443 연결이 22초 뒤 시간 초과 → 보안 그룹에 443이 없었음 (80 · 8080 · 22만).
- 아직: `sudo certbot renew --dry-run`(자동 갱신 시험), 폰에서 https 주소로 한 바퀴(6장 첫 항목), 그다음 보안 그룹에서 **8080 삭제**, 재부팅 시험.
