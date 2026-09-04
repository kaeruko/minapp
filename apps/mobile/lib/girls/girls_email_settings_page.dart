import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'girls_app_core.dart' as core;
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF8062A7);
const Color _pink = Color(0xFFE79AAF);
const Color _cream = Color(0xFFFFFAF0);
const String _patternAsset = 'assets/girls/cutouts/home_pattern.png';

class GirlsEmailSettingsPage extends StatefulWidget {
  const GirlsEmailSettingsPage({
    required this.api,
    required this.session,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;

  @override
  State<GirlsEmailSettingsPage> createState() => _GirlsEmailSettingsPageState();
}

class _GirlsEmailSettingsPageState extends State<GirlsEmailSettingsPage> {
  final GlobalKey<FormState> _emailFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _codeFormKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  HostedEmailStatus? _status;
  String? _pendingEmail;
  String? _destination;
  String? _error;
  String? _message;
  bool _loading = true;
  bool _sending = false;
  bool _verifying = false;

  bool get _busy => _loading || _sending || _verifying;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final HostedEmailStatus status = await widget.api.fetchEmailStatus(
        widget.session.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _status = status;
        _emailController.text = status.email ?? '';
      });
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendCode() async {
    if (!(_emailFormKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
      _message = null;
    });
    try {
      final HostedEmailLinkResult result = await widget.api.requestEmailLink(
        accessToken: widget.session.accessToken,
        email: _emailController.text,
      );
      if (!mounted) return;
      setState(() {
        if (result.verified) {
          _status = HostedEmailStatus(email: result.email, verified: true);
          _pendingEmail = null;
          _destination = null;
          _message = 'このメールアドレスは紐づけ済みです。';
        } else {
          _pendingEmail = result.email;
          _destination = result.destination;
          _codeController.clear();
          _message = '確認コードを送信しました。';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    if (!(_codeFormKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _error = null;
      _message = null;
    });
    try {
      final HostedEmailStatus status = await widget.api.verifyEmailLink(
        accessToken: widget.session.accessToken,
        code: _codeController.text,
      );
      if (!mounted) return;
      setState(() {
        _status = status;
        _emailController.text = status.email ?? '';
        _pendingEmail = null;
        _destination = null;
        _codeController.clear();
        _message = 'メールアドレスを紐づけました♡';
      });
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  String? _validateEmail(String? value) {
    final String email = (value ?? '').trim();
    if (email.isEmpty) return 'メールアドレスを入力してね。';
    if (email.length > maxHostedEmailLength ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'メールアドレスの形式を確認してね。';
    }
    return null;
  }

  String? _validateCode(String? value) {
    if (!RegExp(r'^[0-9]{6}$').hasMatch((value ?? '').trim())) {
      return '6桁の確認コードを入力してね。';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final HostedEmailStatus? status = _status;
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF4F7),
        foregroundColor: _ink,
        centerTitle: true,
        title: const Text(
          'メールアドレス設定',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(_patternAsset),
            fit: BoxFit.cover,
            opacity: .1,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                children: <Widget>[
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else ...<Widget>[
                    _CurrentEmailCard(status: status),
                    const SizedBox(height: 16),
                    _SettingsCard(
                      child: Form(
                        key: _emailFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              status?.verified ?? false
                                  ? 'メールアドレスを変更する'
                                  : 'メールアドレスを紐づける',
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('girls-email-input'),
                              controller: _emailController,
                              enabled: !_busy,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const <String>[
                                AutofillHints.email
                              ],
                              autocorrect: false,
                              textCapitalization: TextCapitalization.none,
                              maxLength: maxHostedEmailLength,
                              validator: _validateEmail,
                              decoration: const InputDecoration(
                                labelText: 'メールアドレス',
                                hintText: 'honey@example.com',
                                prefixIcon: Icon(Icons.mail_outline_rounded),
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              key: const Key('girls-email-send-code'),
                              onPressed: _busy ? null : _sendCode,
                              style: FilledButton.styleFrom(
                                backgroundColor: _lavender,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: _sending
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.mark_email_read_outlined),
                              label: Text(
                                _sending ? '送信中…' : '確認コードを送る',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_pendingEmail != null) ...<Widget>[
                      const SizedBox(height: 16),
                      _SettingsCard(
                        child: Form(
                          key: _codeFormKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const Text(
                                '届いたコードを入力',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _destination == null
                                    ? '$_pendingEmail に送信しました。'
                                    : '$_destination に送信しました。',
                                style:
                                    const TextStyle(color: Color(0xFF7A6660)),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                key: const Key('girls-email-code-input'),
                                controller: _codeController,
                                enabled: !_busy,
                                keyboardType: TextInputType.number,
                                autofillHints: const <String>[
                                  AutofillHints.oneTimeCode,
                                ],
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(6),
                                ],
                                validator: _validateCode,
                                decoration: const InputDecoration(
                                  labelText: '6桁の確認コード',
                                  prefixIcon: Icon(Icons.password_rounded),
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                key: const Key('girls-email-verify'),
                                onPressed: _busy ? null : _verifyCode,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _pink,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: Text(
                                  _verifying ? '確認中…' : '紐づけを完了する',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_message != null) ...<Widget>[
                      const SizedBox(height: 14),
                      _NoticeCard(
                        key: const Key('girls-email-message'),
                        text: _message!,
                        icon: Icons.favorite_rounded,
                        color: const Color(0xFF4D8B65),
                      ),
                    ],
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 14),
                      _NoticeCard(
                        key: const Key('girls-email-error'),
                        text: _error!,
                        icon: Icons.info_outline_rounded,
                        color: const Color(0xFFB45769),
                      ),
                    ],
                    const SizedBox(height: 18),
                    const _PrivacyNote(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentEmailCard extends StatelessWidget {
  const _CurrentEmailCard({required this.status});

  final HostedEmailStatus? status;

  @override
  Widget build(BuildContext context) {
    final bool verified = status?.verified ?? false;
    return Container(
      key: const Key('girls-email-status'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: verified
              ? const <Color>[Color(0xFFE6F8EA), Color(0xFFF5FFF8)]
              : const <Color>[Color(0xFFFFEDF3), Color(0xFFFFF8FA)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: Colors.white,
            foregroundColor: verified ? const Color(0xFF4D8B65) : _pink,
            child: Icon(
              verified ? Icons.verified_rounded : Icons.mail_outline_rounded,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  verified ? '紐づけ済み' : 'まだ紐づけていません',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (status?.email != null)
                  Text(
                    status!.email!,
                    style: const TextStyle(color: Color(0xFF725E58)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0DFE8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x159B6A79),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.text,
    required this.icon,
    required this.color,
    super.key,
  });

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.lock_outline_rounded, color: _lavender, size: 19),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '登録は任意です。確認コードの送信と本人確認のため、入力したメールアドレスをAWS Cognitoに保存します。ログインIDと現在のリカバリーコードは変わりません。',
            style: TextStyle(
              color: Color(0xFF75645F),
              fontSize: 12,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}
