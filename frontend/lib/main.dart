import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/http_auth_service.dart';
import 'core/auth/social_login.dart';
import 'core/config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);

  // 서버 주소를 주고 빌드하면 진짜 로그인 + 서버 게임 데이터, 아니면 앱 안에서만 동작하는 가짜 로그인 + 샘플 데이터.
  final server = AppConfig.useServer ? HttpAuthService(baseUrl: AppConfig.apiBaseUrl, social: SdkSocialLogin()) : null;
  final AuthService auth = server ?? FakeAuthService();
  // 게임 API는 로그인 쪽 토큰을 빌려 쓴다 (재발급도 한곳에서)
  final api = server == null ? null : ApiClient(baseUrl: AppConfig.apiBaseUrl, tokens: server);
  runApp(HabitMonsterApp(authService: auth, api: api));
}
