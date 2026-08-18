import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

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
    if (password.length < 10) {
      setState(() => _error = '新しいパスワードは10文字以上にしてください。');
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

  @override
  Widget build(BuildContext context) {
    final bool changingPassword = _challenge != null;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('みんアプ'),
        actions: const <Widget>[
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: PhaseBadge()),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        changingPassword
                            ? '自分のパスワードに変更'
                            : '先生からもらったIDでログイン',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        changingPassword
                            ? '10文字以上で、大文字・小文字・数字を含めてください。'
                            : 'メールアドレスや電話番号は使いません。',
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.school_outlined, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.classroomName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              key: const Key('login-change-classroom'),
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await widget.onChangeClassroom();
                                    },
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
                          decoration: const InputDecoration(
                            labelText: 'ID',
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const Key('login-password'),
                          controller: _passwordController,
                          enabled: !_busy,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'パスワード',
                            border: OutlineInputBorder(),
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
                          decoration: const InputDecoration(
                            labelText: '新しいパスワード',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const Key('new-password-confirm'),
                          controller: _newPasswordConfirmController,
                          enabled: !_busy,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: '新しいパスワード（確認）',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          style: TextStyle(color: colors.error),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const Key('login-submit'),
                        onPressed: _busy
                            ? null
                            : changingPassword
                                ? _changePassword
                                : _login,
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                changingPassword ? '変更してログイン' : 'ログイン',
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
    );
  }
}
