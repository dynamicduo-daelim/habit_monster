# 습관 몬스터 서버 (Spring Boot)

Spring Boot 4.1 · Java 21 · PostgreSQL. 지금은 **인증**만 들어 있어요. API 계약은 [`../README.md`](../README.md)의 "인증 API".

> **JDK 21 이상**이 필요해요. Gradle은 `JAVA_HOME`의 JDK로 돌아가니, `JAVA_HOME`이 그보다 낮은 버전(예: jdk-20)이면
> `release version 21 not supported` 오류가 나요. `JAVA_HOME`을 jdk-21 이상으로 바꾸거나 IntelliJ에서 Gradle JVM을 21+로 고르세요.

## 바로 띄워 보기 (DB 없이)

```bash
./gradlew bootRun --args='--spring.profiles.active=local'
```

메모리 DB(H2)라 서버를 끄면 데이터가 사라져요. `http://localhost:8080/auth/signup` 등으로 호출해 보면 돼요.

```bash
curl -X POST localhost:8080/auth/signup -H "Content-Type: application/json" -d '{"email":"me@habit.kr","password":"password1"}'
```

## PostgreSQL로 띄우기

1. DB를 만들고 공유 폴더의 `schema.sql`(v1.6) → `seed.sql` 순서로 실행 (메모: `backend/db/README.md`)
2. 환경변수를 넣고 실행

| 환경변수 | 설명 |
| --- | --- |
| `DB_URL` | 기본 `jdbc:postgresql://localhost:5432/habit_monster` |
| `DB_USER` / `DB_PASSWORD` | DB 계정 |
| `JWT_SECRET` | access 토큰 서명 키, **32자 이상** 랜덤 문자열 (필수) |
| `KAKAO_APP_ID` | 카카오 개발자 콘솔의 앱 ID (숫자). 없으면 카카오 로그인은 `SOCIAL_NOT_CONFIGURED` |
| `GOOGLE_CLIENT_IDS` | 구글 OAuth 클라이언트 ID들, 쉼표로 (Android · iOS · 웹) |

JPA는 테이블을 만들거나 바꾸지 않아요 (`ddl-auto=none`). 스키마는 SQL 파일이 기준이에요.

## 테스트

```bash
./gradlew test
```

`local` 프로필(H2)로 가입 · 로그인 · refresh 교체/재사용 감지 · 로그아웃 · 소셜(카카오는 가짜로 대체) · 탈퇴 계정을 검사해요.

## 구조

```
kr.habitmonster
├─ auth/            AuthController · AuthService · TokenService · AuthRules · AuthDtos
│  └─ social/       KakaoVerifier · GoogleVerifier (토큰을 서버가 직접 검증)
├─ identity/        identity 스키마 엔티티 (User · AuthCredential · RefreshToken) + 저장소
├─ config/          SecurityConfig (/auth/** 만 공개) · JwtConfig · AuthProperties
└─ common/          ErrorCode · ApiException · ApiExceptionHandler ({code, message} 오류 응답)
```

다음에 붙일 것: habits · checkins · explore · monsters · shop · goals (`../README.md` API 초안).
