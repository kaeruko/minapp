import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../hosted_group_management_api.dart';
import 'api.dart';
import 'girls_errors.dart';
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF8062A7);
const Color _pink = Color(0xFFE79AAF);
const Color _cream = Color(0xFFFFFAF0);
const String _patternAsset = 'assets/girls/cutouts/home_pattern.png';

class GirlsGroupSettingsResult {
  const GirlsGroupSettingsResult.updated(HostedGroup group)
      : updatedGroup = group,
        removed = false;

  const GirlsGroupSettingsResult.removed()
      : updatedGroup = null,
        removed = true;

  final HostedGroup? updatedGroup;
  final bool removed;
}

class GirlsGroupSettingsPage extends StatefulWidget {
  const GirlsGroupSettingsPage({
    required this.api,
    required this.session,
    required this.group,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final HostedGroup group;

  @override
  State<GirlsGroupSettingsPage> createState() => _GirlsGroupSettingsPageState();
}

class _GirlsGroupSettingsPageState extends State<GirlsGroupSettingsPage> {
  late final TextEditingController _nameController;
  late final HostedGroupManagementApi _managementApi;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _saving = false;
  bool _removing = false;
  bool _memberActionBusy = false;
  bool _loadingGroupId = true;
  bool _loadingMembers = false;
  List<HostedMember>? _members;
  String? _groupIdCode;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _managementApi = HostedGroupManagementApi(
      baseUri: widget.api.baseUri,
      client: widget.api.httpClient,
    );
    if (widget.group.isOwner) {
      _loadGroupId();
      _loadMembers();
    } else {
      _loadingGroupId = false;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _managementApi.close();
    super.dispose();
  }

  Future<void> _loadGroupId() async {
    try {
      final HostedInvite invite = await widget.api.createInvite(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      if (!mounted) return;
      setState(() => _groupIdCode = invite.code);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _loadingGroupId = false);
    }
  }

  Future<void> _copyGroupId() async {
    final String? code = _groupIdCode;
    if (code == null) {
      throw StateError('Group ID is not loaded.');
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('グループIDをコピーしたよ。')),
    );
  }

  Future<void> _loadMembers() async {
    if (!widget.group.isOwner || _loadingMembers) return;
    setState(() {
      _loadingMembers = true;
      _error = null;
    });
    try {
      final List<HostedMember> members = await widget.api.listMembers(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      final int ownerCount =
          members.where((HostedMember member) => member.isOwner).length;
      if (ownerCount != 1) {
        throw StateError(
          'Expected exactly one owner in group members, got $ownerCount.',
        );
      }
      if (!mounted) return;
      setState(() => _members = members);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<bool> _confirmMemberAction({
    required String title,
    required String body,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('やめる'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(action),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _removeMember(HostedMember member) async {
    if (!widget.group.isOwner || member.isOwner || _memberActionBusy) {
      throw StateError('Only the owner can remove a non-owner member.');
    }
    final bool confirmed = await _confirmMemberAction(
      title: '「${member.displayLabel}」を削除する？',
      body: 'このメンバーをグループから外します。',
      action: '削除する',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _memberActionBusy = true;
      _error = null;
    });
    try {
      await _managementApi.removeMember(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        userId: member.userId,
      );
      if (!mounted) return;
      setState(() => _memberActionBusy = false);
      await _loadMembers();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted && _memberActionBusy) {
        setState(() => _memberActionBusy = false);
      }
    }
  }

  Future<void> _changeOwner() async {
    if (!widget.group.isOwner || _memberActionBusy) {
      throw StateError('Only the owner can transfer group ownership.');
    }
    final List<HostedMember>? members = _members;
    if (members == null) {
      throw StateError('Group members are not loaded.');
    }
    final List<HostedMember> candidates = members
        .where((HostedMember member) => !member.isOwner)
        .toList(growable: false);
    if (candidates.isEmpty) return;

    final HostedMember? nextOwner = await showModalBottomSheet<HostedMember>(
      context: context,
      showDragHandle: true,
      backgroundColor: _cream,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '新しいオーナーを選ぶ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ...candidates.map(
                (HostedMember member) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.white.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      key: ValueKey<String>(
                        'girls-group-settings-owner-candidate-${member.userId}',
                      ),
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFF3ECFF),
                        foregroundColor: _lavender,
                        child: Icon(Icons.person_rounded),
                      ),
                      title: Text(
                        member.displayLabel,
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(sheetContext).pop(member),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (nextOwner == null || !mounted) return;

    final bool confirmed = await _confirmMemberAction(
      title: 'オーナーを変更する？',
      body:
          '「${nextOwner.displayLabel}」を新しいオーナーにします。変更後、あなたは通常メンバーになります。',
      action: '変更する',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _memberActionBusy = true;
      _error = null;
    });
    try {
      final HostedOwnershipTransferResult result =
          await _managementApi.transferOwnership(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        newOwnerUserId: nextOwner.userId,
      );
      if (result.ownerUserId != nextOwner.userId) {
        throw StateError('Ownership transfer returned an unexpected owner.');
      }

      final List<HostedGroup> groups = await widget.api.listGroups(
        widget.session.accessToken,
      );
      HostedGroup? updated;
      for (final HostedGroup group in groups) {
        if (group.groupId == widget.group.groupId) {
          updated = group;
          break;
        }
      }
      if (updated == null) {
        throw StateError('Transferred group disappeared from group list.');
      }
      if (updated.isOwner) {
        throw StateError('Ownership transfer did not change the current role.');
      }
      if (!mounted) return;
      Navigator.of(context).pop<GirlsGroupSettingsResult>(
        GirlsGroupSettingsResult.updated(updated),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _memberActionBusy = false);
    }
  }

  Widget _buildOwnerMembersCard() {
    final List<HostedMember>? members = _members;
    final List<HostedMember> editableMembers = members == null
        ? const <HostedMember>[]
        : members
            .where((HostedMember member) => !member.isOwner)
            .toList(growable: false);

    return Container(
      key: const Key('girls-group-settings-members'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0DFE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'メンバー管理',
            style: TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingMembers && members == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (editableMembers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'ほかのメンバーはいません。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF75645F)),
              ),
            )
          else
            ...editableMembers.map(
              (HostedMember member) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: const Color(0xFFFFFBFD),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFECDCE2)),
                  ),
                  child: ListTile(
                    key: ValueKey<String>(
                      'girls-group-settings-member-${member.userId}',
                    ),
                    title: Text(
                      member.displayLabel,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    trailing: OutlinedButton(
                      key: ValueKey<String>(
                        'girls-group-settings-remove-member-${member.userId}',
                      ),
                      onPressed: _memberActionBusy
                          ? null
                          : () => _removeMember(member),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB5465C),
                        side: const BorderSide(color: Color(0xFFE4AAB6)),
                      ),
                      child: const Text(
                        '削除',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('girls-group-settings-change-owner'),
            onPressed: editableMembers.isEmpty || _memberActionBusy
                ? null
                : _changeOwner,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF3D6DF),
              foregroundColor: _ink,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            icon: const Icon(Icons.workspace_premium_rounded),
            label: const Text(
              'オーナーを変更',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  String? _validateName(String? rawValue) {
    final String value = rawValue ?? '';
    if (value.isEmpty) return 'グループ名を入力してね。';
    if (value != value.trim()) return '前後の空白を消してね。';
    if (value.length > maxHostedGroupNameLength) {
      return 'グループ名は$maxHostedGroupNameLength文字までだよ。';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final String name = _nameController.text;
    if (name == widget.group.name) {
      Navigator.of(context).pop<GirlsGroupSettingsResult>(
        GirlsGroupSettingsResult.updated(widget.group),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final HostedGroup updated = await _managementApi.renameGroup(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        name: name,
      );
      if (!mounted) return;
      Navigator.of(context).pop<GirlsGroupSettingsResult>(
        GirlsGroupSettingsResult.updated(updated),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeGroup() async {
    if (_removing) return;
    final bool owner = widget.group.isOwner;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            key: const Key('girls-group-settings-remove-confirm'),
            title: Text(owner ? 'グループを削除する？' : 'グループから抜ける？'),
            content: Text(
              owner
                  ? '「${widget.group.name}」を削除します。グループ内のアプリやメンバー情報も削除され、この操作は取り消せません。'
                  : '「${widget.group.name}」から脱退します。もう一度参加するにはグループIDが必要です。',
            ),
            actions: <Widget>[
              TextButton(
                key: const Key('girls-group-settings-remove-cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('やめる'),
              ),
              FilledButton(
                key: const Key('girls-group-settings-remove-confirm-button'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB5465C),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(owner ? '削除する' : '脱退する'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _removing = true;
      _error = null;
    });
    try {
      if (owner) {
        await _managementApi.deleteGroup(
          accessToken: widget.session.accessToken,
          groupId: widget.group.groupId,
        );
      } else {
        await _managementApi.leaveGroup(
          accessToken: widget.session.accessToken,
          groupId: widget.group.groupId,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop<GirlsGroupSettingsResult>(
        const GirlsGroupSettingsResult.removed(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF4F7),
        foregroundColor: _ink,
        centerTitle: true,
        title: const Text(
          'グループ設定',
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
                  if (widget.group.isOwner)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .9),
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
                      child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const Row(
                            children: <Widget>[
                              CircleAvatar(
                                backgroundColor: Color(0xFFFFEDF3),
                                foregroundColor: _pink,
                                child: Icon(Icons.edit_rounded),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'グループ名',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('girls-group-settings-name'),
                            controller: _nameController,
                            enabled: !_saving,
                            maxLength: maxHostedGroupNameLength,
                            validator: _validateName,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _save(),
                            decoration: const InputDecoration(
                              labelText: 'グループ名',
                              hintText: '例：わんわん',
                              prefixIcon: Icon(Icons.groups_rounded),
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            key: const Key('girls-group-settings-save'),
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: _lavender,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: Text(
                              _saving ? '保存中…' : '変更を保存',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.group.isOwner) ...<Widget>[
                    const SizedBox(height: 14),
                    Container(
                      key: const Key('girls-group-settings-group-id'),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .9),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFF0DFE8)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Row(
                          children: <Widget>[
                            CircleAvatar(
                              backgroundColor: Color(0xFFF3ECFF),
                              foregroundColor: _lavender,
                              child: Icon(Icons.key_rounded),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'グループID',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_loadingGroupId)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (_groupIdCode != null) ...<Widget>[
                          SelectableText(
                            _groupIdCode!,
                            key: const Key('girls-group-settings-group-id-code'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _lavender,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            key: const Key('girls-group-settings-group-id-copy'),
                            onPressed: _copyGroupId,
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('グループIDをコピー'),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '友達はこのIDを「グループを探す」に入力すると参加できます。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF75645F),
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ],
                  if (widget.group.isOwner) ...<Widget>[
                    const SizedBox(height: 14),
                    _buildOwnerMembersCard(),
                  ],
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 14),
                    Container(
                      key: const Key('girls-group-settings-error'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB45769).withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFFB45769),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFB45769),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    key: const Key('girls-group-settings-danger-zone'),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFF1C8D0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          widget.group.isOwner ? 'グループを削除' : 'グループから脱退',
                          style: const TextStyle(
                            color: Color(0xFF9E3E52),
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          widget.group.isOwner
                              ? '削除すると、このグループ内のアプリやメンバー情報も削除されます。'
                              : 'このグループから抜けます。再参加にはグループIDが必要です。',
                          style: const TextStyle(
                            color: Color(0xFF75645F),
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: Key(
                            widget.group.isOwner
                                ? 'girls-group-settings-delete'
                                : 'girls-group-settings-leave',
                          ),
                          onPressed: _saving || _removing ? null : _removeGroup,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFB5465C),
                            side: const BorderSide(color: Color(0xFFE4AAB6)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          icon: _removing
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  widget.group.isOwner
                                      ? Icons.delete_forever_rounded
                                      : Icons.logout_rounded,
                                ),
                          label: Text(
                            _removing
                                ? (widget.group.isOwner ? '削除中…' : '脱退中…')
                                : (widget.group.isOwner
                                      ? 'グループを削除する'
                                      : 'グループから抜ける'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.lock_outline_rounded,
                        color: _lavender,
                        size: 19,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.group.isOwner
                              ? 'グループ名を変更できるのはオーナーだけです。グループIDは固定で、いつでも同じIDを使えます。'
                              : 'このグループにはメンバーとして参加しています。',
                          style: const TextStyle(
                            color: Color(0xFF75645F),
                            fontSize: 12,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
