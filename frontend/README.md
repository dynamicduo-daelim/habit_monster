# 모아루틴 앱 (Flutter)

작업 규칙은 [`CLAUDE.md`](CLAUDE.md), 서버를 따라가야 할 일은 [`서버연동-메모.md`](서버연동-메모.md).

## 실행

```bash
# 시연 모드 (서버 없이)
flutter run

# 에뮬레이터 + 내 PC 서버 (서버는 backend/server에서 ./gradlew bootRun --args='--spring.profiles.active=local')
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8081/api/v1

# 실제 폰 (adb 연결): 먼저 adb reverse tcp:8081 tcp:8081
flutter run --dart-define=API_BASE_URL=http://localhost:8081/api/v1
```

## 검사

```bash
flutter analyze
flutter test
```
