import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'api.dart';
import 'builtin_apps.dart';
import 'builtin_webview.dart';
import 'hosted_app_webview.dart';
import 'hosted_girls_api.dart';

const Color _lavender = Color(0xFFB39DDB);
const Color _lavenderDark = Color(0xFF745B9E);
const Color _pink = Color(0xFFFFC4D6);
const Color _cream = Color(0xFFFFF5E1);
const Color _mint = Color(0xFFC8F3D0);
const Color _blue = Color(0xFFC9E5FF);
const Color _text = Color(0xFF5D4037);

const String _mascotPairAsset = 'assets/girls/mascot_pair.svg';
const String _girlsLoginHeroBackgroundAsset =
    'assets/girls/generated/login_hero_bg.svg';

const Set<String> _girlsBuiltinIds = <String>{
  'ol-home',
  'novel-starter',
  'shiba-goshujin',
};

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
        scaffoldBackgroundColor: const Color(0xFFFFF8FB),
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
      return GirlsAuthPage(
        api: widget.api,
        onAuthenticated: (AuthenticatedSession value) {
          setState(() => _session = value);
        },
      );
    }
    return GirlsGroupsPage(
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFFFFEDF5),
            Color(0xFFF6F0FF),
            _cream,
          ],
        ),
      ),
      child: child,
    );
  }
}

class _GirlsMascot extends StatelessWidget {
  const _GirlsMascot({
    required this.assetName,
    required this.width,
    required this.height,
    required this.semanticsLabel,
  });

  final String assetName;
  final double width;
  final double height;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      assetName,
      width: width,
      height: height,
      fit: BoxFit.contain,
      semanticsLabel: semanticsLabel,
    );
  }
}

class _GirlsLoginHero extends StatelessWidget {
  const _GirlsLoginHero();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: SizedBox(
        height: 300,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            SvgPicture.asset(
              _girlsLoginHeroBackgroundAsset,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
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
              bottom: 34,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _GirlsMascot(
                  assetName: _mascotPairAsset,
                  width: 215,
                  height: 118,
                  semanticsLabel: 'みんアプ Girls のふたりのマスコット',
                ),
              ),
            ),
            Positioned(
              right: 22,
              bottom: 104,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 125),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
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
                  'おかえりなさい ♡',
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
      ),
    );
  }
}

class _GirlsLogo extends StatelessWidget {
  const _GirlsLogo({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: compact ? 34 : 48,
          height: compact ? 34 : 48,
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
          child: Icon(
            Icons.favorite_rounded,
            color: Colors.white,
            size: compact ? 20 : 28,
          ),
        ),
        SizedBox(width: compact ? 9 : 12),
        Text(
          'みんアプ Girls',
          style: TextStyle(
            color: _lavenderDark,
            fontSize: compact ? 20 : 29,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
          ),
        ),
      ],
    );
  }
}

class GirlsAuthPage extends StatefulWidget {
  const GirlsAuthPage({
    required this.api,
    required this.onAuthenticated,
    super.key,
  });

  final HostedGirlsApi api;
  final ValueChanged<AuthenticatedSession> onAuthenticated;

  @override
  State<GirlsAuthPage> createState() => _GirlsAuthPageState();
}

class _GirlsAuthPageState extends State<GirlsAuthPage> {
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
      if (mounted) setState(() => _error = girlsMessageFor(error));
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
      if (mounted) setState(() => _error = girlsMessageFor(error));
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: <Widget>[
                    const _GirlsLoginHero(),
                    const SizedBox(height: 16),
                    const Text(
                      'かわいいアプリを、友達といっしょに。',
                      style: TextStyle(
                        color: Color(0xFF8C7893),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _PastelPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SegmentedButton<bool>(
                            segments: const <ButtonSegment<bool>>[
                              ButtonSegment<bool>(
                                value: false,
                                icon: Icon(Icons.login_rounded),
                                label: Text('ログイン'),
                              ),
                              ButtonSegment<bool>(
                                value: true,
                                icon: Icon(Icons.favorite_border_rounded),
                                label: Text('はじめて'),
                              ),
                            ],
                            selected: <bool>{_creating},
                            onSelectionChanged: _busy
                                ? null
                                : (Set<bool> values) {
                                    setState(() {
                                      _creating = values.single;
                                      _error = null;
                                    });
                                  },
                          ),
                          const SizedBox(height: 22),
                          Text(
                            _creating ? '新しいアカウントをつくる' : 'おかえりなさい ♡',
                            style: const TextStyle(
                              color: _lavenderDark,
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _creating
                                ? 'メールアドレスや電話番号はいらないよ。'
                                : 'IDとパスワードで入ってね。',
                            style: const TextStyle(
                              color: Color(0xFF8C7893),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            key: const Key('girls-login-id'),
                            controller: _loginId,
                            enabled: !_busy,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: 'ID',
                              prefixIcon: Icon(Icons.face_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('girls-password'),
                            controller: _password,
                            enabled: !_busy,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'パスワード',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                            onSubmitted: (_) {
                              if (!_creating && !_busy) _login();
                            },
                          ),
                          if (_creating) ...<Widget>[
                            const SizedBox(height: 12),
                            TextField(
                              key: const Key('girls-password-confirm'),
                              controller: _passwordConfirm,
                              enabled: !_busy,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'パスワード（もう一度）',
                                prefixIcon: Icon(Icons.verified_user_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_legalError != null)
                              Row(
                                children: <Widget>[
                                  const Expanded(child: Text('利用規約を読み込めませんでした。')),
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
                                        setState(() => _accepted = value ?? false);
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
                          ],
                          if (_error != null) ...<Widget>[
                            const SizedBox(height: 12),
                            _GirlsError(message: _error!),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 56,
                            child: FilledButton.icon(
                              key: const Key('girls-auth-submit'),
                              onPressed: _busy
                                  ? null
                                  : (_creating ? _register : _login),
                              style: FilledButton.styleFrom(
                                backgroundColor: _lavenderDark,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
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
                                          : Icons.arrow_forward_rounded,
                                    ),
                              label: Text(
                                _busy
                                    ? '確認しています…'
                                    : _creating
                                        ? 'アカウントをつくる'
                                        : 'ログイン',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GirlsGroupsPage extends StatefulWidget {
  const GirlsGroupsPage({
    required this.api,
    required this.session,
    required this.onLogout,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final VoidCallback onLogout;

  @override
  State<GirlsGroupsPage> createState() => _GirlsGroupsPageState();
}

class _GirlsGroupsPageState extends State<GirlsGroupsPage> {
  List<HostedGroup>? _groups;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedGroup> groups = await widget.api.listGroups(
        widget.session.accessToken,
      );
      if (mounted) setState(() => _groups = groups);
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askForGroupId() {
    return _showTextInputDialog(
      title: '🎀 グループに参加',
      label: 'グループID',
      hint: 'XXXX-XXXX-XXXX',
      maxLength: 20,
      key: const Key('girls-group-id'),
      submitLabel: '参加する',
      capitalize: true,
    );
  }

  Future<String?> _askForGroupName() {
    return _showTextInputDialog(
      title: '💗 新しいグループ',
      label: 'グループ名',
      hint: '例：放課後イラスト部',
      maxLength: maxHostedGroupNameLength,
      key: const Key('girls-group-name'),
      submitLabel: 'つくる',
      capitalize: false,
    );
  }

  Future<String?> _showTextInputDialog({
    required String title,
    required String label,
    required String hint,
    required int maxLength,
    required Key key,
    required String submitLabel,
    required bool capitalize,
  }) async {
    final TextEditingController controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            key: key,
            controller: controller,
            maxLength: maxLength,
            autocorrect: !capitalize,
            enableSuggestions: !capitalize,
            textCapitalization: capitalize
                ? TextCapitalization.characters
                : TextCapitalization.sentences,
            decoration: InputDecoration(labelText: label, hintText: hint),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('やめる'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(submitLabel),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _joinGroup() async {
    final String? rawCode = await _askForGroupId();
    if (rawCode == null || !mounted) return;
    final String code = rawCode.trim();
    if (code.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedGroup group = await widget.api.joinGroup(
        accessToken: widget.session.accessToken,
        code: code,
      );
      final List<HostedGroup> groups = await widget.api.listGroups(
        widget.session.accessToken,
      );
      if (!mounted) return;
      setState(() => _groups = groups);
      await _openGroup(group);
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createGroup() async {
    final String? rawName = await _askForGroupName();
    if (rawName == null || !mounted) return;
    final String name = rawName.trim();
    if (name.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    late final HostedGroup createdGroup;
    try {
      createdGroup = await widget.api.createGroup(
        accessToken: widget.session.accessToken,
        name: name,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = girlsMessageFor(error);
        });
      }
      return;
    }

    try {
      final HostedInvite invite = await widget.api.createInvite(
        accessToken: widget.session.accessToken,
        groupId: createdGroup.groupId,
      );
      final List<HostedGroup> groups = await widget.api.listGroups(
        widget.session.accessToken,
      );
      if (!mounted) return;
      setState(() => _groups = groups);
      await _showGroupId(invite);
      if (!mounted) return;
      await _openGroup(createdGroup);
    } catch (error) {
      if (!mounted) return;
      try {
        final List<HostedGroup> groups = await widget.api.listGroups(
          widget.session.accessToken,
        );
        if (!mounted) return;
        setState(() => _groups = groups);
      } catch (reloadError) {
        if (!mounted) return;
        setState(() {
          _error =
              'グループ「${createdGroup.name}」は作成できたけれど、グループIDの発行に失敗し、その後の一覧更新にも失敗しました。${girlsMessageFor(error)} / ${girlsMessageFor(reloadError)}';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _error =
            'グループ「${createdGroup.name}」は作成できたけれど、グループIDの発行に失敗しました。${girlsMessageFor(error)}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showGroupId(HostedInvite invite) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('🎀 グループIDができたよ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('友達はGirlsの「グループIDで参加」からこのIDを入力すると参加できます。'),
            const SizedBox(height: 14),
            _CodeBox(code: invite.code),
            const SizedBox(height: 8),
            const Text(
              '7日間有効です。新しいIDを発行すると前のIDは使えなくなります。',
              style: TextStyle(fontSize: 12, color: Color(0xFF8C7893)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: invite.code));
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('IDをコピー'),
            ),
          ],
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openGroup(HostedGroup group) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GirlsGroupHomePage(
          api: widget.api,
          session: widget.session,
          group: group,
        ),
      ),
    );
    if (mounted) await _loadGroups();
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedGroup>? groups = _groups;
    return Scaffold(
      body: _GirlsBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 10, 8),
                child: Row(
                  children: <Widget>[
                    const Expanded(child: _GirlsLogo(compact: true)),
                    IconButton(
                      tooltip: '更新',
                      onPressed: _busy ? null : _loadGroups,
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: _lavenderDark,
                      ),
                    ),
                    IconButton(
                      tooltip: 'ログアウト',
                      onPressed: _busy ? null : widget.onLogout,
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: _lavenderDark,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 34),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _PastelPanel(
                            child: Row(
                              children: <Widget>[
                                const _GirlsMascot(
                                  assetName: _mascotPairAsset,
                                  width: 92,
                                  height: 76,
                                  semanticsLabel: 'みんアプ Girls のふたりのマスコット',
                                ),
                                const SizedBox(width: 15),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        'どのグループで遊ぶ？',
                                        style: TextStyle(
                                          color: _lavenderDark,
                                          fontSize: 21,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text('友達のIDで参加するか、自分のグループをつくれるよ。'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: _GroupActionCard(
                                  color: _blue,
                                  icon: Icons.vpn_key_rounded,
                                  title: 'グループIDで参加',
                                  onTap: _busy ? null : _joinGroup,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _GroupActionCard(
                                  color: _mint,
                                  icon: Icons.add_circle_outline_rounded,
                                  title: '新しくつくる',
                                  onTap: _busy ? null : _createGroup,
                                ),
                              ),
                            ],
                          ),
                          if (_error != null) ...<Widget>[
                            const SizedBox(height: 14),
                            _GirlsError(message: _error!),
                          ],
                          const SizedBox(height: 24),
                          const Text(
                            'わたしのグループ',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (groups == null)
                            const Padding(
                              padding: EdgeInsets.all(30),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (groups.isEmpty)
                            const _EmptyGroups()
                          else
                            ...groups.map(
                              (HostedGroup group) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _GroupTile(
                                  group: group,
                                  onTap: _busy ? null : () => _openGroup(group),
                                ),
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
      ),
    );
  }
}

class GirlsGroupHomePage extends StatefulWidget {
  const GirlsGroupHomePage({
    required this.api,
    required this.session,
    required this.group,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final HostedGroup group;

  @override
  State<GirlsGroupHomePage> createState() => _GirlsGroupHomePageState();
}

class _GirlsGroupHomePageState extends State<GirlsGroupHomePage> {
  List<HostedGroupApp>? _apps;
  bool _busy = false;
  String? _error;
  String? _launchingAppId;

  List<BuiltInApp> get _girlsBuiltins => builtInApps
      .where((BuiltInApp app) => _girlsBuiltinIds.contains(app.id))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedGroupApp> apps = await widget.api.listGroupApps(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      if (mounted) setState(() => _apps = apps);
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _launchBuiltin(BuiltInApp app) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => BuiltInWebViewPage(
          title: app.title,
          assetPath: app.assetPath,
        ),
      ),
    );
  }

  Future<void> _launchHostedApp(HostedGroupApp app) async {
    if (!app.isPublished) {
      setState(() => _error = '「${app.title}」はまだ公開版がありません。');
      return;
    }
    setState(() {
      _launchingAppId = app.appId;
      _error = null;
    });
    try {
      final launch = await widget.api.createLaunch(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        appId: app.appId,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => HostedAppWebViewPage(
            title: app.title,
            launch: launch,
            runtimeTransport: widget.api.runtimeClient,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _launchingAppId = null);
    }
  }

  Future<void> _issueGroupId() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('新しいグループIDを発行する？'),
        content: const Text('新しく発行すると、前に発行したグループIDは使えなくなります。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('発行する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedInvite invite = await widget.api.createInvite(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('🎀 グループID'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _CodeBox(code: invite.code),
              const SizedBox(height: 10),
              const Text('友達にこのIDを送ってね。7日間有効です。'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: invite.code));
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('コピー'),
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedGroupApp>? apps = _apps;
    return Scaffold(
      body: _GirlsBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 5),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: _lavenderDark,
                      ),
                    ),
                    const _GirlsLogo(compact: true),
                    const Spacer(),
                    IconButton(
                      onPressed: _busy ? null : _loadApps,
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: _lavenderDark,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 34),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _GroupHeader(
                            group: widget.group,
                            issueGroupId: widget.group.isOwner && !_busy
                                ? _issueGroupId
                                : null,
                          ),
                          if (_error != null) ...<Widget>[
                            const SizedBox(height: 12),
                            _GirlsError(message: _error!),
                          ],
                          const SizedBox(height: 22),
                          const _SectionTitle('Girls おすすめアプリ'),
                          const SizedBox(height: 10),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: .98,
                            children: _girlsBuiltins
                                .map(
                                  (BuiltInApp app) => _GirlsBuiltinCard(
                                    app: app,
                                    onTap: () => _launchBuiltin(app),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                          const SizedBox(height: 26),
                          const _SectionTitle('このグループのアプリ'),
                          const SizedBox(height: 10),
                          if (apps == null)
                            const Padding(
                              padding: EdgeInsets.all(28),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (apps.isEmpty)
                            const _EmptyGroupApps()
                          else
                            ...apps.map(
                              (HostedGroupApp app) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _HostedAppTile(
                                  app: app,
                                  loading: _launchingAppId == app.appId,
                                  onTap: () => _launchHostedApp(app),
                                ),
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
      ),
    );
  }
}

class _PastelPanel extends StatelessWidget {
  const _PastelPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .68),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x22B39DDB),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
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

class _GroupActionCard extends StatelessWidget {
  const _GroupActionCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          child: Column(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(icon, color: _lavenderDark),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.onTap});

  final HostedGroup group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .76),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: group.isOwner ? _pink : _blue,
                child: Icon(
                  group.isOwner
                      ? Icons.favorite_rounded
                      : Icons.groups_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      group.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      group.isOwner ? 'オーナー' : 'メンバー',
                      style: const TextStyle(
                        color: Color(0xFF8C7893),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _lavender),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.issueGroupId});

  final HostedGroup group;
  final VoidCallback? issueGroupId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFFD7E5), Color(0xFFE7DCFF)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Row(
        children: <Widget>[
          const CircleAvatar(
            radius: 27,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.favorite_rounded,
              color: Color(0xFFE987A8),
              size: 29,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  group.name,
                  style: const TextStyle(
                    color: _lavenderDark,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(group.isOwner ? 'あなたがオーナーです ♡' : 'メンバーとして参加中'),
              ],
            ),
          ),
          if (group.isOwner)
            IconButton.filledTonal(
              tooltip: 'グループIDを発行',
              onPressed: issueGroupId,
              icon: const Icon(Icons.vpn_key_rounded),
            ),
        ],
      ),
    );
  }
}

class _GirlsBuiltinCard extends StatelessWidget {
  const _GirlsBuiltinCard({required this.app, required this.onTap});

  final BuiltInApp app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color pastel = switch (app.id) {
      'ol-home' => _blue,
      'novel-starter' => const Color(0xFFE8D8FF),
      'shiba-goshujin' => const Color(0xFFFFD8C2),
      _ => _pink,
    };
    return Material(
      color: pastel.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(app.icon, color: _lavenderDark, size: 31),
              ),
              const SizedBox(height: 11),
              Text(
                app.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostedAppTile extends StatelessWidget {
  const _HostedAppTile({
    required this.app,
    required this.loading,
    required this.onTap,
  });

  final HostedGroupApp app;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .78),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: <Widget>[
              const CircleAvatar(
                backgroundColor: _mint,
                child: Icon(Icons.widgets_rounded, color: _lavenderDark),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      app.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app.isPublished ? 'タップして遊ぶ' : 'まだ公開されていません',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8C7893),
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.chevron_right_rounded, color: _lavender),
            ],
          ),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(
        children: <Widget>[
          Icon(
            Icons.favorite_border_rounded,
            color: _lavender,
            size: 36,
          ),
          SizedBox(height: 8),
          Text(
            'まだグループがないよ。\n友達のグループに入るか、新しくつくってみよう！',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EmptyGroupApps extends StatelessWidget {
  const _EmptyGroupApps();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Text(
        'まだグループのアプリはないよ。\nGirlsおすすめアプリは上からすぐ遊べるよ ♡',
        textAlign: TextAlign.center,
      ),
    );
  }
}

String girlsMessageFor(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'IDかパスワードが違うみたい。もう一度確認してね。';
      case 'login_id_conflict':
        return 'そのIDはもう使われています。別のIDにしてね。';
      case 'invalid_invite_code':
      case 'invite_not_found':
        return 'グループIDが見つからないみたい。文字を確認してね。';
      case 'invite_expired':
        return 'このグループIDは期限切れです。オーナーに新しいIDを発行してもらってね。';
      case 'already_member':
        return 'もうこのグループに参加しているよ。';
      case 'group_full':
        return 'このグループは参加人数の上限に達しています。';
      case 'group_limit_reached':
        return '参加できるグループ数の上限に達しています。';
      case 'rate_limited':
        return '操作が続きすぎたみたい。少し待ってからもう一度試してね。';
      default:
        return error.message;
    }
  }
  if (error is ArgumentError || error is FormatException) {
    return '入力またはサーバーから届いたデータの形式を確認できませんでした。';
  }
  return '処理に失敗しました: $error';
}
