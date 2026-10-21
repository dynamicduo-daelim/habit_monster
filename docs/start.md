flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8081/api/v1

실제 폰 (adb 연결): adb reverse tcp:8081 tcp:8081 한 뒤
flutter run --dart-define=API_BASE_URL=http://localhost:8081/api/v1


./gradlew bootRun --args='--spring.profiles.active=local'
