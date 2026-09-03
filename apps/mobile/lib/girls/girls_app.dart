import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'api.dart';
import 'girls_app_core.dart' as core;
import 'hosted_girls_api.dart';

export 'girls_app_core.dart' hide GirlsApp;

const Color _lavender = Color(0xFFB39DDB);
const Color _lavenderDark = Color(0xFF745B9E);
const Color _pink = Color(0xFFFFC4D6);
const Color _text = Color(0xFF5D4037);

const String _mascotPairAsset = 'assets/girls/mascot_pair.svg';
const String _girlsLoginHeroPatternAsset =
    'assets/girls/generated/bg_pastel_pattern.png';
const String _girlsLoginHeroLaceAsset =
    'assets/girls/generated/border_lace_heart.png';

class GirlsApp extends StatelessWidget {
  const GirlsApp({required this.api, super.key});

  final HostedGirlsApi api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'みんアプ Girls',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _lavender,
          primary: _lavenderDark,
          secondary: const Color(0xFFE987A8),
          surface: const Color(0xFFFFFBFD),
        ),
        scaffoldBackgroundColor: const Color(0xFFFDF9EE),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: _text,
              displayColor: _text,
            ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: .82),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE7DDF2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE7DDF2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _lavender, width: 2),
          ),
        ),
      ),
      home: _GirlsSessionRoot(api: api),
    );
  }
}

class _GirlsSessionRoot extends StatefulWidget {
  const _GirlsSessionRoot({required this.api});

  final HostedGirlsApi api;

  @override
  State<_GirlsSessionRoot> createState() => _GirlsSessionRootState();
}

class _GirlsSessionRootState extends State<_GirlsSessionRoot> {
  AuthenticatedSession? _session;

  @override
  Widget build(BuildContext context) {
    final AuthenticatedSession? session = _session;
    if (session == null) {
      return _GirlsAuthPage(
        api: widget.api,
        onAuthenticated: (AuthenticatedSession value) {
          setState(() => _session = value);
        },
      );
    }
    return core.GirlsGroupsPage(
      api: widget.api,
      session: session,
      onLogout: () => setState(() => _session = null),
    );
  }
}

class _GirlsBackground extends StatelessWidget {
  const _GirlsBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFDF9EE),
      child: child,
    );
  }
}

class _GirlsPngHero extends StatelessWidget {
  const _GirlsPngHero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const ColoredBox(color: Color(0xFFFFE9F1)),
          Image.asset(
            _girlsLoginHeroPatternAsset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _GirlsLaceStrip(),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: TransformFlipLace(),
          ),
          const Positioned(
            top: 52,
            left: 20,
            right: 20,
            child: Center(child: _GirlsLogo()),
          ),
          const Positioned(
            left: 20,
            right: 20,
            bottom: 38,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _GirlsMascotPair(),
            ),
          ),
          Positioned(
            right: 22,
            bottom: 108,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 125),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFE7B5C8),
                  width: 1.3,
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x22A36B8A),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: const Text(
                'みんなでアプリを\nつくろう！',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _lavenderDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TransformFlipLace extends StatelessWidget {
  const TransformFlipLace({super.key});

  @override
  Widget build(BuildContext context) {
    return Transform.flip(
      flipY: true,
      child: const _GirlsLaceStrip(),
    );
  }
}

class _GirlsLaceStrip extends StatelessWidget {
  const _GirlsLaceStrip();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 34,
      child: ClipRect(
        child: Image.asset(
          _girlsLoginHeroLaceAsset,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
        ),
      ),
    );
  }
}

class _GirlsMascotPair extends StatelessWidget {
  const _GirlsMascotPair();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _mascotPairAsset,
      width: 215,
      height: 118,
      fit: BoxFit.contain,
      semanticsLabel: 'みんアプ Girls のふたりのマスコット',
    );
  }
}

class _GirlsLogo extends StatelessWidget {
  const _GirlsLogo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _pink,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x33B39DDB),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.favorite_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'みんアプ Girls',
          style: TextStyle(
            color: _lavenderDark,
            fontSize: 29,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
          ),
        ),
      ],
    );
  }
}

class _GirlsAuthPage extends StatefulWidget {
  const _GirlsAuthPage({
    required this.api,
    required this.onAuthenticated,
  });

  final HostedGirlsApi api;
  final ValueChanged<AuthenticatedSession> onAuthenticated;

  @override
  State<_GirlsAuthPage> createState() => _GirlsAuthPageState();
}

class _GirlsAuthPageState extends State<_GirlsAuthPage> {
  final TextEditingController _loginId = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();

  HostedLegalBundle? _legal;
  Object? _legalError;
  bool _creating = false;
  bool _accepted = false;
  bool _busy = false;
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

  Future<void> _login() async {
    final String loginId = _loginId.text.trim();
    final String password = _password.text;
    if (loginId.isEmpty || password.isEmpty) {
      setState(() => _error = 'IDとパスワードを入力してね。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AuthResult result = await widget.api.login(loginId, password);
      if (result is! AuthenticatedSession) {
        throw StateError(
          'Hosted login unexpectedly returned a password challenge.',
        );
      }
      if (mounted) widget.onAuthenticated(result);
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    final HostedLegalBundle? legal = _legal;
    if (legal == null) {
      setState(() => _error = '利用規約を読み込めていません。もう一度お試しください。');
      return;
    }
    final String loginId = _loginId.text.trim();
    final String password = _password.text;
    if (loginId.isEmpty || password.isEmpty) {
      setState(() => _error = 'IDとパスワードを入力してね。');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'パスワードは6文字以上にしてね。');
      return;
    }
    if (password != _passwordConfirm.text) {
      setState(() => _error = '確認用パスワードが一致していないよ。');
      return;
    }
    if (!_accepted) {
      setState(() => _error = '利用規約とプライバシーポリシーを確認して同意してね。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedRegistrationResult registration = await widget.api.register(
        loginId: loginId,
        password: password,
        legal: legal,
      );
      if (!mounted) return;
      await _showRecoveryCode(registration.recoveryCode);
      if (!mounted) return;
      final AuthResult auth = await widget.api.login(loginId, password);
      if (auth is! AuthenticatedSession) {
        throw StateError(
          'New Hosted account unexpectedly returned a password challenge.',
        );
      }
      if (mounted) widget.onAuthenticated(auth);
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: const Text('🔑 復旧コードを保存してね'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'メールアドレスを登録しないので、パスワードを忘れたときはこのコードが必要です。同じコードはあとから再表示できません。',
              ),
              const SizedBox(height: 16),
              _CodeBox(code: code),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('コピー'),
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('保存した'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLegal(HostedLegalText legal) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(legal.title),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(legal.body),
          ),
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
      body: _GirlsBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 28, bottom: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _GirlsPngHero(),
                const SizedBox(height: 20),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (_creating) ...<Widget>[
                            const Text(
                              '新規登録',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _lavenderDark,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'メールアドレスや電話番号はいらないよ。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF8C7893),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          TextField(
                            key: const Key('girls-login-id'),
                            controller: _loginId,
                            enabled: !_busy,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: _fieldDecoration(
                              label: 'Login ID / ユーザー名',
                              icon: Icons.key_rounded,
                              iconColor: _lavender,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const Key('girls-password'),
                            controller: _password,
                            enabled: !_busy,
                            obscureText: true,
                            decoration: _fieldDecoration(
                              label: 'パスワード',
                              icon: Icons.favorite_border_rounded,
                              iconColor: const Color(0xFFD59AB6),
                            ),
                            onSubmitted: (_) {
                              if (!_creating && !_busy) _login();
                            },
                          ),
                          if (_creating) ...<Widget>[
                            const SizedBox(height: 14),
                            TextField(
                              key: const Key('girls-password-confirm'),
                              controller: _passwordConfirm,
                              enabled: !_busy,
                              obscureText: true,
                              decoration: _fieldDecoration(
                                label: 'パスワードをもう一度入力してください',
                                icon: Icons.favorite_rounded,
                                iconColor: const Color(0xFFD59AB6),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_legalError != null)
                              Row(
                                children: <Widget>[
                                  const Expanded(
                                    child: Text('利用規約を読み込めませんでした。'),
                                  ),
                                  TextButton(
                                    onPressed: _loadLegal,
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
                                    : (bool? value) {
                                        setState(
                                          () => _accepted = value ?? false,
                                        );
                                      },
                                title: const Text(
                                  '利用規約とプライバシーポリシーに同意します',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                controlAffinity: ListTileControlAffinity.leading,
                              ),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                children: <Widget>[
                                  TextButton(
                                    onPressed: () => _showLegal(legal.terms),
                                    child: const Text('利用規約を読む'),
                                  ),
                                  TextButton(
                                    onPressed: () => _showLegal(legal.privacy),
                                    child: const Text('プライバシーを読む'),
                                  ),
                                ],
                              ),
                            ],
                          ] else ...<Widget>[
                            const SizedBox(height: 8),
                            const Text(
                              'パスワードを忘れた場合は、登録時に保存した復旧コードを使います。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFAA91A4),
                                fontSize: 11,
                              ),
                            ),
                          ],
                          if (_error != null) ...<Widget>[
                            const SizedBox(height: 12),
                            _GirlsError(message: _error!),
                          ],
                          const SizedBox(height: 16),
                          Container(
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _creating
                                    ? const <Color>[
                                        Color(0xFF9ADFC8),
                                        Color(0xFF62C9AD),
                                      ]
                                    : const <Color>[
                                        Color(0xFFD7C2F1),
                                        Color(0xFFA77BD5),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x33745B9E),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: FilledButton.icon(
                              key: const Key('girls-auth-submit'),
                              onPressed: _busy
                                  ? null
                                  : (_creating ? _register : _login),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                disabledBackgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              icon: _busy
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      _creating
                                          ? Icons.favorite_rounded
                                          : Icons.login_rounded,
                                    ),
                              label: Text(
                                _busy
                                    ? '確認しています…'
                                    : _creating
                                        ? '新規登録する'
                                        : 'ログイン',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: <Widget>[
                              const Expanded(
                                child: Divider(color: Color(0xFFE0CFD7)),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  _creating ? 'すでに登録済み？' : 'はじめての方',
                                  style: const TextStyle(
                                    color: Color(0xFF9A8793),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const Expanded(
                                child: Divider(color: Color(0xFFE0CFD7)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      setState(() {
                                        _creating = !_creating;
                                        _error = null;
                                      });
                                    },
                              style: OutlinedButton.styleFrom(
                                backgroundColor: _creating
                                    ? Colors.white.withValues(alpha: .72)
                                    : const Color(0xFFA7E2CE),
                                foregroundColor: _creating
                                    ? _lavenderDark
                                    : const Color(0xFF356F61),
                                side: BorderSide(
                                  color: _creating
                                      ? const Color(0xFFD7C7E8)
                                      : const Color(0xFF70C8AD),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                ),
                              ),
                              icon: Icon(
                                _creating
                                    ? Icons.arrow_back_rounded
                                    : Icons.favorite_rounded,
                              ),
                              label: Text(
                                _creating ? 'ログインに戻る' : '新規登録はこちら',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    required Color iconColor,
  }) {
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      prefixIcon: Icon(icon, color: iconColor),
      filled: true,
      fillColor: const Color(0xFFFFFEFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: Color(0xFFD7C7E8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: Color(0xFFD7C7E8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: _lavender, width: 1.5),
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3ECFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SelectableText(
        code,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _lavenderDark,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _GirlsError extends StatelessWidget {
  const _GirlsError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECEF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFFFC5CE)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFA04455),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
