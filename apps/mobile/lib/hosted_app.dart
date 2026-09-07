import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'hosted_api.dart';
import 'hosted_app_webview.dart';
import 'hosted_authoring_contract_api.dart';
import 'hosted_authoring_projects_page.dart';

class HostedApp extends StatelessWidget {
  const HostedApp({
    required this.api,
    required this.onChangeMode,
    super.key,
  });

  final HostedPlatformApi api;
  final Future<void> Function() onChangeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'みんアプ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          surface: const Color(0xFFF8FAFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        useMaterial3: true,
      ),
      home: _HostedSessionRoot(api: api, onChangeMode: onChangeMode),
    );
  }
}

class _HostedSessionRoot extends StatefulWidget {
  const _HostedSessionRoot({required this.api, required this.onChangeMode});

  final HostedPlatformApi api;
  final Future<void> Function() onChangeMode;

  @override
  State<_HostedSessionRoot> createState() => _HostedSessionRootState();
}

class _HostedSessionRootState extends State<_HostedSessionRoot> {
  AuthenticatedSession? _session;

  @override
  Widget build(BuildContext context) {
    final AuthenticatedSession? session = _session;
    if (session == null) {
      return HostedAuthPage(
        api: widget.api,
        onAuthenticated: (AuthenticatedSession value) {
          setState(() => _session = value);
        },
        onChangeMode: widget.onChangeMode,
      );
    }
    return HostedHomePage(
      api: widget.api,
      session: session,
      onLogout: () => setState(() => _session = null),
      onChangeMode: widget.onChangeMode,
    );
  }
}

enum _HostedAuthMode { login, register, recover }

class HostedAuthPage extends StatefulWidget {
  const HostedAuthPage({
    required this.api,
    required this.onAuthenticated,
    required this.onChangeMode,
    super.key,
  });

  final HostedPlatformApi api;
  final ValueChanged<AuthenticatedSession> onAuthenticated;
  final Future<void> Function() onChangeMode;

  @override
  State<HostedAuthPage> createState() => _HostedAuthPageState();
}

class _HostedAuthPageState extends State<HostedAuthPage> {
  final TextEditingController _loginId = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();
  final TextEditingController _recoveryCode = TextEditingController();

  _HostedAuthMode _mode = _HostedAuthMode.login;
  HostedLegalBundle? _legal;
  Object? _legalError;
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
    _recoveryCode.dispose();
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

  void _setMode(_HostedAuthMode mode) {
    if (_busy) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  Future<void> _submit() async {
    switch (_mode) {
      case _HostedAuthMode.login:
        await _login();
      case _HostedAuthMode.register:
        await _register();
      case _HostedAuthMode.recover:
        await _recover();
    }
  }

  Future<void> _login() async {
    final String loginId = _loginId.text.trim();
    final String password = _password.text;
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
      if (result is! AuthenticatedSession) {
        throw StateError('Hosted login returned an unsupported password challenge.');
      }
      if (mounted) widget.onAuthenticated(result);
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    final HostedLegalBundle? legal = _legal;
    if (legal == null) {
      setState(() => _error = '利用規約を読み込めていません。');
      return;
    }
    final String loginId = _loginId.text.trim();
    final String password = _password.text;
    if (loginId.isEmpty || password.isEmpty) {
      setState(() => _error = 'IDとパスワードを入力してください。');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'パスワードは6文字以上にしてください。');
      return;
    }
    if (password != _passwordConfirm.text) {
      setState(() => _error = '確認用パスワードが一致しません。');
      return;
    }
    if (!_accepted) {
      setState(() => _error = '利用規約とプライバシーポリシーへの同意が必要です。');
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
        throw StateError('New Hosted account returned an unsupported password challenge.');
      }
      widget.onAuthenticated(auth);
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    final String loginId = _loginId.text.trim();
    final String newPassword = _password.text;
    if (loginId.isEmpty || _recoveryCode.text.trim().isEmpty || newPassword.isEmpty) {
      setState(() => _error = 'ID、復旧コード、新しいパスワードを入力してください。');
      return;
    }
    if (newPassword.length < 6 || newPassword != _passwordConfirm.text) {
      setState(() => _error = '新しいパスワードを6文字以上で、確認欄と同じ内容にしてください。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedRecoveryResult recovered = await widget.api.recover(
        loginId: loginId,
        recoveryCode: _recoveryCode.text,
        newPassword: newPassword,
      );
      if (!mounted) return;
      await _showRecoveryCode(recovered.recoveryCode);
      if (!mounted) return;
      final AuthResult auth = await widget.api.login(loginId, newPassword);
      if (auth is! AuthenticatedSession) {
        throw StateError('Recovered Hosted account returned an unsupported password challenge.');
      }
      widget.onAuthenticated(auth);
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
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
              const Text('このコードはあとから同じ内容を再表示できません。安全な場所へ保存してください。'),
              const SizedBox(height: 16),
              SelectableText(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
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
              child: const Text('保存した'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLegal(HostedLegalText text) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(text.title),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: SelectableText(text.body)),
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
    final bool registering = _mode == _HostedAuthMode.register;
    final bool recovering = _mode == _HostedAuthMode.recover;
    return Scaffold(
      appBar: AppBar(
        title: const Text('みんアプ'),
        actions: <Widget>[
          TextButton(
            key: const Key('hosted-change-mode'),
            onPressed: _busy ? null : widget.onChangeMode,
            child: const Text('利用方法を切り替える'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Icon(
                        recovering ? Icons.key_rounded : Icons.person_rounded,
                        size: 44,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        registering
                            ? 'アカウントを作る'
                            : recovering
                                ? 'アカウントを復旧する'
                                : '自分ではじめる',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        key: const Key('hosted-login-id'),
                        controller: _loginId,
                        enabled: !_busy,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(labelText: 'ユーザーID'),
                      ),
                      const SizedBox(height: 12),
                      if (recovering) ...<Widget>[
                        TextField(
                          key: const Key('hosted-recovery-code'),
                          controller: _recoveryCode,
                          enabled: !_busy,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(labelText: '復旧コード'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        key: const Key('hosted-password'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: recovering ? '新しいパスワード' : 'パスワード',
                        ),
                      ),
                      if (registering || recovering) ...<Widget>[
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('hosted-password-confirm'),
                          controller: _passwordConfirm,
                          enabled: !_busy,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'パスワード（確認）'),
                        ),
                      ],
                      if (registering) ...<Widget>[
                        const SizedBox(height: 16),
                        if (_legalError != null)
                          _ErrorBox(message: hostedMessageFor(_legalError!))
                        else if (legal == null)
                          const Center(child: CircularProgressIndicator())
                        else ...<Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: TextButton(
                                  onPressed: () => _showLegal(legal.terms),
                                  child: const Text('利用規約'),
                                ),
                              ),
                              Expanded(
                                child: TextButton(
                                  onPressed: () => _showLegal(legal.privacy),
                                  child: const Text('プライバシー'),
                                ),
                              ),
                            ],
                          ),
                          CheckboxListTile(
                            key: const Key('hosted-legal-accept'),
                            value: _accepted,
                            onChanged: _busy
                                ? null
                                : (bool? value) => setState(() => _accepted = value == true),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('利用規約とプライバシーポリシーに同意する'),
                          ),
                        ],
                      ],
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _ErrorBox(message: _error!),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const Key('hosted-auth-submit'),
                        onPressed: _busy ? null : _submit,
                        child: Text(
                          _busy
                              ? '確認中…'
                              : registering
                                  ? '登録する'
                                  : recovering
                                      ? '復旧する'
                                      : 'ログイン',
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!registering)
                        TextButton(
                          key: const Key('hosted-show-register'),
                          onPressed: _busy ? null : () => _setMode(_HostedAuthMode.register),
                          child: const Text('はじめての方はこちら'),
                        ),
                      if (!recovering)
                        TextButton(
                          key: const Key('hosted-show-recover'),
                          onPressed: _busy ? null : () => _setMode(_HostedAuthMode.recover),
                          child: const Text('パスワードを忘れた'),
                        ),
                      if (_mode != _HostedAuthMode.login)
                        TextButton(
                          key: const Key('hosted-show-login'),
                          onPressed: _busy ? null : () => _setMode(_HostedAuthMode.login),
                          child: const Text('ログインに戻る'),
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

class HostedHomePage extends StatefulWidget {
  const HostedHomePage({
    required this.api,
    required this.session,
    required this.onLogout,
    required this.onChangeMode,
    super.key,
  });

  final HostedPlatformApi api;
  final AuthenticatedSession session;
  final VoidCallback onLogout;
  final Future<void> Function() onChangeMode;

  @override
  State<HostedHomePage> createState() => _HostedHomePageState();
}

class _HostedHomePageState extends State<HostedHomePage> {
  List<HostedGroup>? _groups;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedGroup> groups = await widget.api.listGroups(widget.session.accessToken);
      if (mounted) setState(() => _groups = groups);
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _ask(String title, String label, {int? maxLength}) async {
    final TextEditingController controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLength: maxLength,
            decoration: InputDecoration(labelText: label),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('決定'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _createGroup() async {
    final String? raw = await _ask('グループを作る', 'グループ名', maxLength: maxHostedGroupNameLength);
    if (raw == null || !mounted) return;
    final String name = raw.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedGroup created = await widget.api.createGroup(
        accessToken: widget.session.accessToken,
        name: name,
      );
      if (!mounted) return;
      await _loadAfterMutation();
      if (!mounted) return;
      await _openGroup(created);
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinGroup() async {
    final String? raw = await _ask('グループに参加', '招待コード');
    if (raw == null || !mounted || raw.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedGroup joined = await widget.api.joinGroup(
        accessToken: widget.session.accessToken,
        code: raw,
      );
      if (!mounted) return;
      await _loadAfterMutation();
      if (!mounted) return;
      await _openGroup(joined);
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadAfterMutation() async {
    final List<HostedGroup> groups = await widget.api.listGroups(widget.session.accessToken);
    if (mounted) setState(() => _groups = groups);
  }

  Future<void> _openGroup(HostedGroup group) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => HostedGroupPage(
          api: widget.api,
          session: widget.session,
          group: group,
        ),
      ),
    );
    if (mounted) await _loadGroups();
  }

  Future<void> _accountAction(String value) async {
    switch (value) {
      case 'logout':
        widget.onLogout();
      case 'mode':
        await widget.onChangeMode();
      default:
        throw StateError('Unknown Hosted account action: $value');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedGroup>? groups = _groups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('みんアプ'),
        actions: <Widget>[
          IconButton(
            key: const Key('hosted-groups-refresh'),
            onPressed: _busy ? null : _loadGroups,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '更新',
          ),
          PopupMenuButton<String>(
            onSelected: _accountAction,
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'mode', child: Text('利用方法を切り替える')),
              PopupMenuItem<String>(value: 'logout', child: Text('ログアウト')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadGroups,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              Text('グループ', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              const Text('友達と同じグループに参加すると、同じアプリを使えます。'),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('hosted-create-group'),
                      onPressed: _busy ? null : _createGroup,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('グループを作る'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('hosted-join-group'),
                      onPressed: _busy ? null : _joinGroup,
                      icon: const Icon(Icons.group_add_rounded),
                      label: const Text('招待で参加'),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                _ErrorBox(message: _error!),
              ],
              const SizedBox(height: 18),
              if (groups == null)
                const Center(child: CircularProgressIndicator())
              else if (groups.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('まだグループがありません。作成するか、招待コードで参加してください。'),
                  ),
                )
              else
                ...groups.map(
                  (HostedGroup group) => Card(
                    child: ListTile(
                      key: Key('hosted-group-${group.groupId}'),
                      leading: const Icon(Icons.groups_rounded),
                      title: Text(group.name),
                      subtitle: Text(group.isOwner ? 'オーナー' : 'メンバー'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _busy ? null : () => _openGroup(group),
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

class HostedGroupPage extends StatefulWidget {
  const HostedGroupPage({
    required this.api,
    required this.session,
    required this.group,
    super.key,
  });

  final HostedPlatformApi api;
  final AuthenticatedSession session;
  final HostedGroup group;

  @override
  State<HostedGroupPage> createState() => _HostedGroupPageState();
}

class _HostedGroupPageState extends State<HostedGroupPage> {
  List<HostedGroupApp>? _apps;
  List<HostedMember>? _members;
  List<HostedAuthoringAppContract>? _contracts;
  HostedAuthoringContractApi? _contractApi;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _contractApi = HostedAuthoringContractApi(baseUri: widget.api.baseUri);
    _load();
  }

  @override
  void dispose() {
    _contractApi?.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedGroupApp> apps = await widget.api.listGroupApps(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      final List<HostedMember> members = await widget.api.listMembers(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      final HostedAuthoringContractApi? contractApi = _contractApi;
      if (contractApi == null) throw StateError('Authoring contract client is not initialized.');
      final List<HostedAuthoringAppContract> contracts = await contractApi.listApps(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _members = members;
        _contracts = contracts;
      });
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  HostedAuthoringAppContract? _contractFor(String appId) {
    final List<HostedAuthoringAppContract>? contracts = _contracts;
    if (contracts == null) return null;
    for (final HostedAuthoringAppContract contract in contracts) {
      if (contract.appId == appId) return contract;
    }
    return null;
  }

  Future<void> _installBuiltin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedBuiltin> builtins = await widget.api.listBuiltins();
      if (!mounted) return;
      final HostedBuiltin? selected = await showDialog<HostedBuiltin>(
        context: context,
        builder: (BuildContext dialogContext) => SimpleDialog(
          title: const Text('追加するアプリ'),
          children: builtins
              .map(
                (HostedBuiltin builtin) => SimpleDialogOption(
                  onPressed: () => Navigator.of(dialogContext).pop(builtin),
                  child: ListTile(
                    title: Text(builtin.title),
                    subtitle: Text('v${builtin.version}'),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      );
      if (selected == null || !mounted) return;
      await widget.api.installBuiltin(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        builtinId: selected.builtinId,
      );
      if (mounted) await _loadAfterMutation();
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadAfterMutation() async {
    final List<HostedGroupApp> apps = await widget.api.listGroupApps(
      accessToken: widget.session.accessToken,
      groupId: widget.group.groupId,
    );
    final HostedAuthoringContractApi? contractApi = _contractApi;
    if (contractApi == null) throw StateError('Authoring contract client is not initialized.');
    final List<HostedAuthoringAppContract> contracts = await contractApi.listApps(
      accessToken: widget.session.accessToken,
      groupId: widget.group.groupId,
    );
    if (mounted) {
      setState(() {
        _apps = apps;
        _contracts = contracts;
      });
    }
  }

  Future<void> _launch(HostedGroupApp app) async {
    if (!app.isPublished) {
      setState(() => _error = 'このアプリはまだ公開されていません。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final launch = await widget.api.createLaunch(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        appId: app.appId,
      );
      if (!mounted) return;
      setState(() => _busy = false);
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
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _openAuthoring(HostedGroupApp app) async {
    final HostedAuthoringAppContract? contract = _contractFor(app.appId);
    if (contract == null || contract.edits.isEmpty) {
      throw StateError('Selected app is not an Authoring Editor.');
    }
    String? contentFormat;
    if (contract.edits.length == 1) {
      contentFormat = contract.edits.single;
    } else {
      contentFormat = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) => SimpleDialog(
          title: const Text('作る形式を選ぶ'),
          children: contract.edits
              .map(
                (String format) => SimpleDialogOption(
                  onPressed: () => Navigator.of(dialogContext).pop(format),
                  child: Text(format),
                ),
              )
              .toList(growable: false),
        ),
      );
    }
    if (contentFormat == null || !mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => HostedAuthoringProjectsPage(
          baseUri: widget.api.baseUri,
          accessToken: widget.session.accessToken,
          groupId: widget.group.groupId,
          editorAppId: app.appId,
          runtimeTransport: widget.api.runtimeClient,
          definition: HostedAuthoringProjectDefinition(
            contentFormat: contentFormat!,
            pageTitle: app.title,
            collectionTitle: '作品',
            emptyTitle: 'まだ作品がありません',
            emptyBody: '新しい作品を作ると、このEditorで編集できます。',
          ),
          errorMessage: hostedMessageFor,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _createInvite() async {
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
          title: const Text('招待コード'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SelectableText(
                invite.code,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: invite.code)),
                icon: const Icon(Icons.copy_rounded),
                label: const Text('コピー'),
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedGroupApp>? apps = _apps;
    final List<HostedMember>? members = _members;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: <Widget>[
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '更新',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('アプリ', style: Theme.of(context).textTheme.headlineSmall),
                ),
                if (widget.group.isOwner)
                  FilledButton.icon(
                    key: const Key('hosted-install-builtin'),
                    onPressed: _busy ? null : _installBuiltin,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('追加'),
                  ),
              ],
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              _ErrorBox(message: _error!),
            ],
            const SizedBox(height: 12),
            if (apps == null)
              const Center(child: CircularProgressIndicator())
            else if (apps.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('まだアプリがありません。'),
                ),
              )
            else
              ...apps.map((HostedGroupApp app) {
                final HostedAuthoringAppContract? contract = _contractFor(app.appId);
                final bool canAuthor = contract != null && contract.edits.isNotEmpty;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.apps_rounded),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(app.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(app.isPublished ? '公開済み' : '未公開'),
                            ],
                          ),
                        ),
                        if (canAuthor)
                          TextButton(
                            key: Key('hosted-authoring-${app.appId}'),
                            onPressed: _busy ? null : () => _openAuthoring(app),
                            child: const Text('作品を作る'),
                          ),
                        if (app.isPublished)
                          FilledButton(
                            key: Key('hosted-launch-${app.appId}'),
                            onPressed: _busy ? null : () => _launch(app),
                            child: const Text('開く'),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 28),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('メンバー', style: Theme.of(context).textTheme.titleLarge),
                ),
                if (widget.group.isOwner)
                  OutlinedButton.icon(
                    key: const Key('hosted-create-invite'),
                    onPressed: _busy ? null : _createInvite,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('招待'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (members == null)
              const LinearProgressIndicator()
            else
              ...members.map(
                (HostedMember member) => ListTile(
                  leading: Icon(member.isOwner ? Icons.admin_panel_settings_rounded : Icons.person_rounded),
                  title: Text(member.loginId),
                  subtitle: Text(member.isOwner ? 'オーナー' : 'メンバー'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

String hostedMessageFor(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'unauthorized':
      case 'not_authorized':
        return 'ID、パスワード、または復旧コードを確認してください。';
      case 'login_id_conflict':
        return 'このIDはすでに使われています。';
      case 'invite_not_found':
      case 'invite_expired':
        return '招待コードを確認してください。';
      case 'forbidden':
        return 'この操作を行う権限がありません。';
      case 'builtin_already_installed':
        return 'このアプリはすでにグループへ追加されています。';
      case 'app_unpublished':
        return 'このアプリはまだ公開されていません。';
      default:
        return error.message;
    }
  }
  if (error is FormatException || error is ArgumentError || error is StateError) {
    return error.toString();
  }
  return '処理に失敗しました: $error';
}
