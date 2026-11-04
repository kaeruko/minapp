import 'package:flutter/material.dart';

import '../api.dart';
import '../hosted_consumer_api.dart';
import '../hosted_consumer_errors.dart';
import '../hosted_group_management_api.dart';
import '../hosted_profile_api.dart';
import 'kobo_groups_page.dart';
import 'kobo_theme.dart';

class KoboAccountSettingsPage extends StatefulWidget {
  const KoboAccountSettingsPage({
    required this.api,
    required this.session,
    required this.onAccountDeleted,
    super.key,
  });

  final HostedConsumerApi api;
  final AuthenticatedSession session;
  final Future<void> Function() onAccountDeleted;

  @override
  State<KoboAccountSettingsPage> createState() =>
      _KoboAccountSettingsPageState();
}

class _KoboAccountSettingsPageState extends State<KoboAccountSettingsPage> {
  late final HostedProfileApi _profileApi;
  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();

  HostedProfile? _profile;
  HostedEmailStatus? _emailStatus;
  String? _pendingDestination;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _profileApi = HostedProfileApi(
      baseUri: widget.api.baseUri,
      client: widget.api.httpClient,
    );
    _load();
  }

  @override
  void dispose() {
    _profileApi.close();
    _displayName.dispose();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final HostedProfile profile =
          await _profileApi.fetch(widget.session.accessToken);
      final HostedEmailStatus emailStatus =
          await widget.api.fetchEmailStatus(widget.session.accessToken);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _emailStatus = emailStatus;
        _displayName.text = profile.displayName ?? '';
        _email.text = emailStatus.email ?? '';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveDisplayName() async {
    if (_busy) return;
    final String value = _displayName.text;
    if (value.isEmpty ||
        value != value.trim() ||
        value.length > maxHostedDisplayNameLength) {
      setState(() => _error = '表示名は前後に空白のない1〜40文字で入力してください。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final HostedProfile profile = await _profileApi.updateDisplayName(
        accessToken: widget.session.accessToken,
        displayName: value,
      );
      if (mounted) {
        setState(() {
          _profile = profile;
          _message = '表示名を保存しました。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendEmailCode() async {
    if (_busy) return;
    final String email = _email.text.trim();
    if (email.length > maxHostedEmailLength ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'メールアドレスの形式を確認してください。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final HostedEmailLinkResult result = await widget.api.requestEmailLink(
        accessToken: widget.session.accessToken,
        email: email,
      );
      if (!mounted) return;
      setState(() {
        _emailStatus = HostedEmailStatus(
          email: result.email,
          verified: result.verified,
        );
        _pendingDestination = result.verified ? null : result.destination;
        _code.clear();
        _message = result.verified ? 'このメールアドレスは確認済みです。' : '確認コードを送信しました。';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyEmailCode() async {
    if (_busy) return;
    final String code = _code.text.trim();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      setState(() => _error = '6桁の確認コードを入力してください。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final HostedEmailStatus status = await widget.api.verifyEmailLink(
        accessToken: widget.session.accessToken,
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _emailStatus = status;
        _email.text = status.email ?? '';
        _pendingDestination = null;
        _code.clear();
        _message = 'メールアドレスを確認しました。';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openGroups() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => KoboGroupsPage(
          api: widget.api,
          session: widget.session,
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    if (_busy) return;
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('アカウントを削除しますか？'),
            content: const Text(
              'この操作は取り消せません。オーナーになっている非公開グループと、'
              'その中のアプリも削除されます。',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('やめる'),
              ),
              FilledButton(
                key: const Key('kobo-delete-account-confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: KoboColors.error,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('削除する'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final HostedGroupManagementApi groupApi = HostedGroupManagementApi(
      baseUri: widget.api.baseUri,
      client: widget.api.httpClient,
    );
    try {
      final String token = widget.session.accessToken;
      final List<HostedGroup> groups = await widget.api.listGroups(token);
      widget.api.edition.community.requireFrom(groups);
      for (final HostedGroup group
          in widget.api.edition.community.privateGroupsFrom(groups)) {
        if (!group.isOwner) continue;
        await groupApi.deleteGroup(
          accessToken: token,
          groupId: group.groupId,
        );
      }
      await widget.api.deleteAccount(token);
      if (!mounted) return;
      await widget.onAccountDeleted();
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      groupApi.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final HostedProfile? profile = _profile;
    final HostedEmailStatus? emailStatus = _emailStatus;
    return Scaffold(
      appBar: AppBar(
        title: const Text('アカウント設定'),
        actions: <Widget>[
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '更新',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(KoboSpacing.md),
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(KoboSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Text('表示名', style: KoboTextStyles.cardTitle),
                        const SizedBox(height: KoboSpacing.xs),
                        Text('ログイン名：${profile?.loginId ?? '—'}'),
                        const SizedBox(height: KoboSpacing.sm),
                        TextField(
                          key: const Key('kobo-display-name'),
                          controller: _displayName,
                          enabled: !_busy,
                          maxLength: maxHostedDisplayNameLength,
                          decoration: const InputDecoration(
                            labelText: 'みんなに見える名前',
                          ),
                        ),
                        FilledButton.icon(
                          key: const Key('kobo-save-display-name'),
                          onPressed: _busy ? null : _saveDisplayName,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('表示名を保存'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: KoboSpacing.sm),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(KoboSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Text(
                          'メールアドレス',
                          style: KoboTextStyles.cardTitle,
                        ),
                        const SizedBox(height: KoboSpacing.xs),
                        Text(
                          emailStatus?.verified ?? false ? '確認済み' : '未確認・未設定',
                          style: KoboTextStyles.secondary,
                        ),
                        const SizedBox(height: KoboSpacing.sm),
                        TextField(
                          key: const Key('kobo-email'),
                          controller: _email,
                          enabled: !_busy,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'メールアドレス',
                          ),
                        ),
                        const SizedBox(height: KoboSpacing.xs),
                        OutlinedButton.icon(
                          key: const Key('kobo-send-email-code'),
                          onPressed: _busy ? null : _sendEmailCode,
                          icon: const Icon(Icons.mark_email_unread_outlined),
                          label: const Text('確認コードを送る'),
                        ),
                        if (_pendingDestination != null) ...<Widget>[
                          const SizedBox(height: KoboSpacing.sm),
                          Text('送信先：$_pendingDestination'),
                          const SizedBox(height: KoboSpacing.xs),
                          TextField(
                            key: const Key('kobo-email-code'),
                            controller: _code,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: const InputDecoration(
                              labelText: '6桁の確認コード',
                            ),
                          ),
                          FilledButton(
                            key: const Key('kobo-verify-email-code'),
                            onPressed: _busy ? null : _verifyEmailCode,
                            child: const Text('確認する'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: KoboSpacing.sm),
                Card(
                  child: ListTile(
                    key: const Key('kobo-private-groups'),
                    leading: const Icon(
                      Icons.groups_outlined,
                      color: KoboColors.navy,
                    ),
                    title: const Text('非公開グループ'),
                    subtitle: const Text('必要なときだけ仲間の工房を追加'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _busy ? null : _openGroups,
                  ),
                ),
                if (_message != null) ...<Widget>[
                  const SizedBox(height: KoboSpacing.sm),
                  Text(
                    _message!,
                    style: const TextStyle(color: KoboColors.success),
                  ),
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: KoboSpacing.sm),
                  Text(_error!,
                      style: const TextStyle(color: KoboColors.error)),
                ],
                const SizedBox(height: KoboSpacing.lg),
                OutlinedButton.icon(
                  key: const Key('kobo-delete-account'),
                  onPressed: _busy ? null : _deleteAccount,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KoboColors.error,
                    side: const BorderSide(color: KoboColors.error),
                  ),
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text('アカウントを削除'),
                ),
              ],
            ),
    );
  }
}
