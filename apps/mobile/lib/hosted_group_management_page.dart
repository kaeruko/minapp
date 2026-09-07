import 'package:flutter/material.dart';

import 'api.dart';
import 'hosted_api.dart';
import 'hosted_app.dart' show hostedMessageFor;
import 'hosted_group_management_api.dart';

class HostedGroupManagementPage extends StatefulWidget {
  const HostedGroupManagementPage({
    required this.api,
    required this.session,
    super.key,
  });

  final HostedPlatformApi api;
  final AuthenticatedSession session;

  @override
  State<HostedGroupManagementPage> createState() =>
      _HostedGroupManagementPageState();
}

class _HostedGroupManagementPageState
    extends State<HostedGroupManagementPage> {
  List<HostedGroup>? _groups;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedGroup> groups =
          await widget.api.listGroups(widget.session.accessToken);
      if (mounted) setState(() => _groups = groups);
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(HostedGroup group) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => HostedGroupLifecycleDetailPage(
          api: widget.api,
          session: widget.session,
          group: group,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedGroup>? groups = _groups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('グループ管理'),
        actions: <Widget>[
          IconButton(
            key: const Key('hosted-group-management-refresh'),
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            const Text('退出、メンバー削除、オーナー移譲などの管理を行います。'),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              _GroupManagementError(message: _error!),
            ],
            const SizedBox(height: 16),
            if (groups == null)
              const Center(child: CircularProgressIndicator())
            else if (groups.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('所属グループがありません。'),
                ),
              )
            else
              ...groups.map(
                (HostedGroup group) => Card(
                  child: ListTile(
                    key: Key('hosted-manage-group-${group.groupId}'),
                    leading: Icon(
                      group.isOwner
                          ? Icons.admin_panel_settings_rounded
                          : Icons.groups_rounded,
                    ),
                    title: Text(group.name),
                    subtitle: Text(group.isOwner ? 'オーナー' : 'メンバー'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _busy ? null : () => _open(group),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HostedGroupLifecycleDetailPage extends StatefulWidget {
  const HostedGroupLifecycleDetailPage({
    required this.api,
    required this.session,
    required this.group,
    super.key,
  });

  final HostedPlatformApi api;
  final AuthenticatedSession session;
  final HostedGroup group;

  @override
  State<HostedGroupLifecycleDetailPage> createState() =>
      _HostedGroupLifecycleDetailPageState();
}

enum _MemberAction { transferOwnership, remove }

class _HostedGroupLifecycleDetailPageState
    extends State<HostedGroupLifecycleDetailPage> {
  late final HostedGroupManagementApi _managementApi;
  List<HostedMember>? _members;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _managementApi = HostedGroupManagementApi(baseUri: widget.api.baseUri);
    _loadMembers();
  }

  @override
  void dispose() {
    _managementApi.close();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedMember> members = await widget.api.listMembers(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      if (mounted) setState(() => _members = members);
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _leave() async {
    if (widget.group.isOwner) {
      setState(() => _error = 'オーナーは先に別のメンバーへオーナー権限を移してください。');
      return;
    }
    if (!await _confirm(
      'グループから退出しますか？',
      '退出すると、このグループのアプリや作品へアクセスできなくなります。',
      '退出する',
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _managementApi.leaveGroup(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeMember(HostedMember member) async {
    if (!widget.group.isOwner || member.isOwner) {
      throw StateError('Only a group owner can remove a non-owner member.');
    }
    if (!await _confirm(
      '${member.loginId} をグループから外しますか？',
      '対象ユーザーのmembershipだけを削除します。アプリ作者情報は自動変更しません。',
      '外す',
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _managementApi.removeMember(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        userId: member.userId,
      );
      if (mounted) {
        setState(() => _busy = false);
        await _loadMembers();
      }
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _transferOwnership(HostedMember member) async {
    if (!widget.group.isOwner || member.isOwner) {
      throw StateError('Only a group owner can transfer ownership to a member.');
    }
    if (!await _confirm(
      '${member.loginId} にオーナーを移しますか？',
      '移譲後、あなたは通常メンバーになります。',
      '移譲する',
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _managementApi.transferOwnership(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        newOwnerUserId: member.userId,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeInvite() async {
    if (!widget.group.isOwner) {
      throw StateError('Only a group owner can revoke an invite.');
    }
    if (!await _confirm(
      '現在の招待コードを無効にしますか？',
      '無効化すると、今のコードでは新しく参加できなくなります。',
      '無効にする',
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _managementApi.revokeInvite(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('招待コードを無効にしました。')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _memberAction(
    HostedMember member,
    _MemberAction action,
  ) async {
    switch (action) {
      case _MemberAction.transferOwnership:
        await _transferOwnership(member);
      case _MemberAction.remove:
        await _removeMember(member);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedMember>? members = _members;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: <Widget>[
          IconButton(
            onPressed: _busy ? null : _loadMembers,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            if (_error != null) ...<Widget>[
              _GroupManagementError(message: _error!),
              const SizedBox(height: 12),
            ],
            Text('メンバー', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (members == null)
              const LinearProgressIndicator()
            else
              ...members.map(
                (HostedMember member) => ListTile(
                  key: Key('hosted-manage-member-${member.userId}'),
                  leading: Icon(
                    member.isOwner
                        ? Icons.admin_panel_settings_rounded
                        : Icons.person_rounded,
                  ),
                  title: Text(member.loginId),
                  subtitle: Text(member.isOwner ? 'オーナー' : 'メンバー'),
                  trailing: widget.group.isOwner && !member.isOwner
                      ? PopupMenuButton<_MemberAction>(
                          onSelected: (_MemberAction action) =>
                              _memberAction(member, action),
                          itemBuilder: (BuildContext context) => const <
                              PopupMenuEntry<_MemberAction>>[
                            PopupMenuItem<_MemberAction>(
                              value: _MemberAction.transferOwnership,
                              child: Text('オーナーを移譲'),
                            ),
                            PopupMenuItem<_MemberAction>(
                              value: _MemberAction.remove,
                              child: Text('グループから外す'),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
            const SizedBox(height: 24),
            if (widget.group.isOwner)
              OutlinedButton.icon(
                key: const Key('hosted-revoke-invite'),
                onPressed: _busy ? null : _revokeInvite,
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('現在の招待コードを無効にする'),
              )
            else
              FilledButton.tonalIcon(
                key: const Key('hosted-leave-group'),
                onPressed: _busy ? null : _leave,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('グループから退出する'),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupManagementError extends StatelessWidget {
  const _GroupManagementError({required this.message});

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
