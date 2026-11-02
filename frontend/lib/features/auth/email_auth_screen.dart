import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pixel_widgets.dart';
import '../onboarding/onboarding_parts.dart' show DotGridPainter, pixelInputDecoration;
import 'login_parts.dart';
import '../../core/theme/app_theme.dart';

/// 이메일 로그인 · 회원가입. 성공하면 닫히고, 아래의 [AuthGate]가 온보딩이나 홈을 보여준다.
class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  bool _signUp = false;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 아이디 저장으로 남긴 이메일을 미리 채운다 (처음 한 번만)
    final saved = AuthScope.of(context).prefs.savedEmail;
    if (_email.text.isEmpty && saved != null) _email.text = saved;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text;
    final pw = _password.text;
    final err = AuthRules.emailError(email) ??
        (_signUp ? AuthRules.passwordError(pw) : (pw.isEmpty ? '비밀번호를 입력해 주세요' : null)) ??
        (_signUp && pw != _confirm.text ? '비밀번호가 서로 달라요' : null);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() => _error = null);
    final auth = AuthScope.of(context);
    final nav = Navigator.of(context);
    try {
      if (_signUp) {
        await auth.signUpWithEmail(email, pw);
      } else {
        await auth.signInWithEmail(email, pw);
      }
      nav.pop();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Widget _field(String label, TextEditingController c, {bool secret = false, String hint = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.brownMuted)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.brownText, width: 2),
          ),
          child: Semantics(
            label: label,
            child: TextField(
              controller: c,
              obscureText: secret,
              keyboardType: secret ? TextInputType.visiblePassword : TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: !secret,
              cursorColor: AppColors.brownText,
              style: const TextStyle(fontSize: 13, color: AppColors.brownText),
              decoration: pixelInputDecoration(hint),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final busy = auth.busy;
    return Scaffold(
      backgroundColor: AppColors.introSky,
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: DotGridPainter())),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    button: true,
                    label: '뒤로',
                    excludeSemantics: true,
                    onTap: () => Navigator.of(context).pop(),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('◀ 뒤로', style: TextStyle(fontSize: 12, color: AppColors.purpleSoft)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 로그인 / 회원가입 탭
                Row(
                  children: [
                    for (final (signUp, label) in const [(false, '로그인'), (true, '회원가입')]) ...[
                      if (signUp) const SizedBox(width: 6),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _signUp = signUp;
                            _error = null;
                          }),
                          child: Container(
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: _signUp == signUp ? AppColors.introFloor : AppColors.nightDeep,
                              border: Border.all(
                                  color: _signUp == signUp ? AppColors.purple : AppColors.nightLine, width: 3),
                            ),
                            child: Text(label,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: _signUp == signUp ? AppColors.text : AppColors.textMuted)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.ink, width: 2),
                    boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(0, 4))],
                  ),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_signUp ? '이메일로 가입' : '이메일로 로그인',
                        style: const TextStyle(fontFamily: AppTheme.pixelFont, fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.brownText)),
                    const SizedBox(height: 14),
                    _field('이메일', _email, hint: 'you@example.com'),
                    const SizedBox(height: 12),
                    _field('비밀번호', _password,
                        secret: true, hint: _signUp ? '${AuthRules.minPasswordLength}자 이상' : ''),
                    if (_signUp) ...[const SizedBox(height: 12), _field('비밀번호 확인', _confirm, secret: true)],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      children: [
                        if (!_signUp)
                          PixelCheckbox(
                            label: '아이디 저장',
                            value: auth.prefs.rememberEmail,
                            onChanged: auth.setRememberEmail,
                            onLight: true,
                          ),
                        PixelCheckbox(
                            label: '자동 로그인', value: auth.prefs.autoLogin, onChanged: auth.setAutoLogin, onLight: true),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 6),
                      Text(_error!,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.red)),
                    ],
                    const SizedBox(height: 10),
                    RoundBlockButton(
                      label: busy ? '잠시만요…' : (_signUp ? '가입하고 시작하기' : '로그인'),
                      onPressed: busy ? null : _submit,
                      color: AppColors.yellowButton,
                      shadowColor: AppColors.yellowShadow,
                      height: 50,
                    ),
                  ],
                  ),
                ),
                if (!_signUp) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: AppColors.purpleDeep, borderRadius: BorderRadius.circular(10)),
                    child: const Text('아이디 저장: 다음에 이메일을 미리 채워 둬요 (비밀번호는 저장하지 않아요)\n자동 로그인: 끄면 앱을 껐다 켤 때 다시 로그인해요',
                        style: TextStyle(fontSize: 11.5, height: 1.7, color: AppColors.text)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
