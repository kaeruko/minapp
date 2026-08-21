import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

const Color _brandBlue = Color(0xFF2563EB);
const Color _brandDark = Color(0xFF1E3A8A);
const Color _pageBackground = Color(0xFFF8FAFC);
const Color _mutedText = Color(0xFF64748B);

class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.api,
    required this.classroomName,
    required this.onChangeClassroom,
    required this.onAuthenticated,
    super.key,
  });

  final MinAppApi api;
  final String classroomName;
  final Future<void> Function() onChangeClassroom;
  final ValueChanged<AuthenticatedSession> onAuthenticated;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _loginIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _newPasswordConfirmController = TextEditingController();

  NewPasswordChallenge? _challenge;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _loginIdController.dispose();
    _passwordController.dispose();
    _newPasswordController.dispose();
    _newPasswordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final String loginId = _loginIdController.text.trim();
    final String password = _passwordController.text;
    if (loginId.isEmpty || password.isEmpty) {
      setState(() => _error = 'IDとパスワードを入力してください。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AuthResult result = await widget.api.login(loginId, password);
      if (!mounted) return;
      if (result is AuthenticatedSession) {
        widget.onAuthenticated(result);
        return;
      }
      if (result is NewPasswordChallenge) {
        setState(() {
          _challenge = result;
          _passwordController.clear();
        });
        return;
      }
      throw StateError('Unsupported authentication result.');
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final NewPasswordChallenge? challenge = _challenge;
    if (challenge == null) throw StateError('Password challenge is missing.');
    final String password = _newPasswordController.text;
    if (password != _newPasswordConfirmController.text) {
      setState(() => _error = '確認用パスワードが一致しません。');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = '新しいパスワードは6文字以上にしてください。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AuthenticatedSession session = await widget.api.completeNewPassword(
        loginId: challenge.loginId,
        newPassword: password,
        session: challenge.session,
      );
      if (mounted) widget.onAuthenticated(session);
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _mutedText, fontWeight: FontWeight.w700),
      prefixIcon: Icon(icon, color: const Color(0xFF94A3B8)),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF93C5FD), width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool changingPassword = _challenge != null;
    return Scaffold(
      backgroundColor: _pageBackground,
      body: Column(
        children: <Widget>[
          Container(
            key: const Key('login-brand-header'),
            width: double.infinity,
            color: _brandBlue,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.classroomName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFDBEAFE),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'みんアプ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 27,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'クラスのみんなのアプリへ',
                            style: TextStyle(
                              color: Color(0xFFBFDBFE),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4F7DF0),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.school_rounded,
                        color: Colors.white,
                        size: 27,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x120F172A),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            changingPassword
                                ? '自分のパスワードに変更'
                                : '先生からもらったIDでログイン',
                            style: const TextStyle(
                              color: _brandDark,
                              fontSize: 24,
                              height: 1.3,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            changingPassword
                                ? '6文字以上なら使えます。文字の種類に決まりはありません。'
                                : 'メールアドレスや電話番号は使いません。',
                            style: const TextStyle(
                              color: _mutedText,
                              fontSize: 14,
                              height: 1.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Container(
                            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFDBEAFE)),
                            ),
                            child: Row(
                              children: <Widget>[
                                const Icon(
                                  Icons.school_outlined,
                                  size: 21,
                                  color: _brandBlue,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    widget.classroomName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF334155),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  key: const Key('login-change-classroom'),
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          await widget.onChangeClassroom();
                                        },
                                  style: TextButton.styleFrom(
                                    foregroundColor: _brandBlue,
                                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  child: const Text('変更'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (!changingPassword) ...<Widget>[
                            TextField(
                              key: const Key('login-id'),
                              controller: _loginIdController,
                              enabled: !_busy,
                              decoration: _fieldDecoration(
                                label: 'ID',
                                icon: Icons.person_outline_rounded,
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              key: const Key('login-password'),
                              controller: _passwordController,
                              enabled: !_busy,
                              obscureText: true,
                              decoration: _fieldDecoration(
                                label: 'パスワード',
                                icon: Icons.lock_outline_rounded,
                              ),
                              onSubmitted: (_) {
                                if (!_busy) _login();
                              },
                            ),
                          ] else ...<Widget>[
                            TextField(
                              key: const Key('new-password'),
                              controller: _newPasswordController,
                              enabled: !_busy,
                              obscureText: true,
                              decoration: _fieldDecoration(
                                label: '新しいパスワード',
                                icon: Icons.lock_reset_rounded,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              key: const Key('new-password-confirm'),
                              controller: _newPasswordConfirmController,
                              enabled: !_busy,
                              obscureText: true,
                              decoration: _fieldDecoration(
                                label: '新しいパスワード（確認）',
                                icon: Icons.verified_user_outlined,
                              ),
                            ),
                          ],
                          if (_error != null) ...<Widget>[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFB91C1C),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 56,
                            child: FilledButton.icon(
                              key: const Key('login-submit'),
                              onPressed: _busy
                                  ? null
                                  : changingPassword
                                      ? _changePassword
                                      : _login,
                              style: FilledButton.styleFrom(
                                backgroundColor: _brandBlue,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(0xFF93C5FD),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              icon: _busy
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.3,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      changingPassword
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.login_rounded,
                                    ),
                              label: Text(
                                _busy
                                    ? '確認しています…'
                                    : changingPassword
                                        ? '変更してログイン'
                                        : 'ログイン',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
