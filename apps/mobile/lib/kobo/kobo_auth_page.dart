import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../hosted_consumer_api.dart';
import '../hosted_consumer_errors.dart';
import 'kobo_theme.dart';

class KoboAuthPage extends StatefulWidget {
  const KoboAuthPage({
    required this.api,
    required this.onAuthenticated,
    super.key,
  });

  final HostedConsumerApi api;
  final ValueChanged<AuthenticatedSession> onAuthenticated;

  @override
  State<KoboAuthPage> createState() => _KoboAuthPageState();
}

class _KoboAuthPageState extends State<KoboAuthPage> {
  final TextEditingController _loginId = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();

  HostedLegalBundle? _legal;
  bool _creating = false;
  bool _accepted = false;
  bool _busy = false;
  Object? _legalError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLegal();
  }

  @override
  void dispose() {
    _loginId.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  Future<void> _loadLegal() async {
    try {
      final HostedLegalBundle legal = await widget.api.fetchLegal();
      if (!mounted) return;
      setState(() {
        _legal = legal;
        _legalError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _legal = null;
        _legalError = error;
      });
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final String loginId = _loginId.text.trim();
    final String password = _password.text;
    if (loginId.isEmpty || password.isEmpty) {
      setState(() => _error = 'ユーザー名とパスワードを入力してください。');
      return;
    }
    if (_creating) {
      if (password.length < 6) {
        setState(() => _error = 'パスワードは6文字以上にしてください。');
        return;
      }
      if (password != _passwordConfirm.text) {
        setState(() => _error = '確認用パスワードが一致していません。');
        return;
      }
      if (_legal == null) {
        setState(() => _error = '利用規約を読み込めていません。');
        return;
      }
      if (!_accepted) {
        setState(() => _error = '利用規約とプライバシーポリシーへの同意が必要です。');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_creating) {
        final HostedRegistrationResult registration = await widget.api.register(
          loginId: loginId,
          password: password,
          legal: _legal!,
        );
        if (!mounted) return;
        await _showRecoveryCode(registration.recoveryCode);
        if (!mounted) return;
      }
      final AuthResult result = await widget.api.login(loginId, password);
      if (result is! AuthenticatedSession) {
        throw StateError(
          'Hosted login unexpectedly returned a password challenge.',
        );
      }
      if (mounted) widget.onAuthenticated(result);
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRecoveryCode(String code) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('復旧コードを保存してください'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'パスワードを忘れたときに必要です。'
                '同じコードはあとから再表示できません。',
              ),
              const SizedBox(height: KoboSpacing.md),
              Container(
                padding: const EdgeInsets.all(KoboSpacing.md),
                decoration: BoxDecoration(
                  color: KoboColors.paper,
                  borderRadius: BorderRadius.circular(KoboRadii.input),
                  border: Border.all(color: KoboColors.divider),
                ),
                child: SelectableText(
                  code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: KoboColors.navy,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: KoboSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                icon: const Icon(Icons.copy_rounded),
                label: const Text('コピー'),
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('保存しました'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLegal(HostedLegalText legal) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(legal.title),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: SelectableText(legal.body)),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final HostedLegalBundle? legal = _legal;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('kobo-auth-back'),
          tooltip: '戻る',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(_creating ? '工房をはじめる' : 'ログイン'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(KoboSpacing.md),
          children: <Widget>[
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(KoboSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          _creating
                              ? '遊んでみて、気に入ったら自分の工房を持てます。'
                              : '自分のアプリや工房を続きから使えます。',
                          style: KoboTextStyles.body,
                        ),
                        const SizedBox(height: KoboSpacing.lg),
                        TextField(
                          key: const Key('kobo-login-id'),
                          controller: _loginId,
                          enabled: !_busy,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'ユーザー名',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: KoboSpacing.sm),
                        TextField(
                          key: const Key('kobo-password'),
                          controller: _password,
                          enabled: !_busy,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'パスワード',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          onSubmitted: (_) {
                            if (!_creating) _submit();
                          },
                        ),
                        if (_creating) ...<Widget>[
                          const SizedBox(height: KoboSpacing.sm),
                          TextField(
                            key: const Key('kobo-password-confirm'),
                            controller: _passwordConfirm,
                            enabled: !_busy,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'パスワードをもう一度',
                              prefixIcon: Icon(Icons.lock_reset_outlined),
                            ),
                          ),
                          const SizedBox(height: KoboSpacing.sm),
                          if (_legalError != null)
                            Row(
                              children: <Widget>[
                                const Expanded(child: Text('利用規約を読み込めませんでした。')),
                                TextButton(
                                  onPressed: _busy ? null : _loadLegal,
                                  child: const Text('再読み込み'),
                                ),
                              ],
                            )
                          else if (legal == null)
                            const Center(child: CircularProgressIndicator())
                          else ...<Widget>[
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _accepted,
                              onChanged: _busy
                                  ? null
                                  : (bool? value) => setState(
                                        () => _accepted = value ?? false,
                                      ),
                              title: const Text(
                                '利用規約とプライバシーポリシーに同意します',
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            Wrap(
                              alignment: WrapAlignment.center,
                              children: <Widget>[
                                TextButton(
                                  onPressed: () => _showLegal(legal.terms),
                                  child: const Text('利用規約'),
                                ),
                                TextButton(
                                  onPressed: () => _showLegal(legal.privacy),
                                  child: const Text('プライバシー'),
                                ),
                              ],
                            ),
                          ],
                        ],
                        if (_error != null) ...<Widget>[
                          const SizedBox(height: KoboSpacing.sm),
                          Container(
                            padding: const EdgeInsets.all(KoboSpacing.sm),
                            decoration: BoxDecoration(
                              color: KoboColors.error.withValues(alpha: .08),
                              borderRadius:
                                  BorderRadius.circular(KoboRadii.input),
                              border: Border.all(color: KoboColors.error),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: KoboColors.error),
                            ),
                          ),
                        ],
                        const SizedBox(height: KoboSpacing.md),
                        FilledButton.icon(
                          key: const Key('kobo-auth-submit'),
                          onPressed: _busy ? null : _submit,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(_creating ? Icons.handyman : Icons.login),
                          label: Text(_creating ? '工房を登録する' : 'ログイン'),
                        ),
                        const SizedBox(height: KoboSpacing.sm),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _creating = !_creating;
                                    _error = null;
                                  }),
                          child: Text(
                            _creating ? 'ログインに戻る' : 'はじめての方はこちら',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
