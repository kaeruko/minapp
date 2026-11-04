import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'girls_community.dart';
import 'girls_errors.dart';
import 'girls_group_home_page.dart';
import 'girls_group_settings_page.dart';
import 'girls_scaffold.dart';
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF8B6BB2);
const Color _pink = Color(0xFFE79AAF);
const String _backgroundAsset =
    'assets/girls/backgrounds/group_home_background.jpg';

/// Optional private groups. The system community is intentionally absent here:
/// ordinary Girls use never requires selecting or switching a group.
class GirlsGroupsDashboardPage extends StatefulWidget {
  const GirlsGroupsDashboardPage({
    required this.api,
    required this.session,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;

  @override
  State<GirlsGroupsDashboardPage> createState() =>
      _GirlsGroupsDashboardPageState();
}

class _GirlsGroupsDashboardPageState extends State<GirlsGroupsDashboardPage> {
  List<HostedGroup>? _groups;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedGroup> groups = await widget.api.listGroups(
        widget.session.accessToken,
      );
      final List<HostedGroup> privateGroups = girlsPrivateGroups(groups);
      if (!mounted) return;
      setState(() => _groups = privateGroups);
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinGroup() async {
    final String? rawCode = await _showTextInputDialog(
      title: '友達グループに参加',
      label: 'グループID',
      hint: 'XXXX-XXXX-XXXX',
      maxLength: 20,
      submitLabel: '参加する',
      capitalize: true,
    );
    if (rawCode == null || !mounted) return;
    final String code = rawCode.trim();
    if (code.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedGroup joined = await widget.api.joinGroup(
        accessToken: widget.session.accessToken,
        code: code,
      );
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「${joined.name}」に参加したよ。')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createGroup() async {
    final String? rawName = await _showTextInputDialog(
      title: '友達だけのグループを作る',
      label: 'グループ名',
      hint: '例：女子会アプリ開発部',
      maxLength: maxHostedGroupNameLength,
      submitLabel: '作る',
      capitalize: false,
    );
    if (rawName == null || !mounted) return;
    final String name = rawName.trim();
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
      final HostedInvite invite = await widget.api.createInvite(
        accessToken: widget.session.accessToken,
        groupId: created.groupId,
      );
      await _reload();
      if (!mounted) return;
      await _showGroupId(created, invite);
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _showTextInputDialog({
    required String title,
    required String label,
    required String hint,
    required int maxLength,
    required String submitLabel,
    required bool capitalize,
  }) async {
    String value = '';
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          maxLength: maxLength,
          autocorrect: !capitalize,
          enableSuggestions: !capitalize,
          textCapitalization: capitalize
              ? TextCapitalization.characters
              : TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onChanged: (String nextValue) => value = nextValue,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(value),
            child: Text(submitLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _showGroupId(
    HostedGroup group,
    HostedInvite invite,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('「${group.name}」を作ったよ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('このIDを知っている友達だけが参加できます。'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF3ECFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(
                invite.code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _lavender,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: invite.code),
              ),
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
    if (mounted) await _reload();
  }

  Future<void> _openSettings(HostedGroup group) async {
    await Navigator.of(context).push<GirlsGroupSettingsResult>(
      MaterialPageRoute<GirlsGroupSettingsResult>(
        builder: (BuildContext context) => GirlsGroupSettingsPage(
          api: widget.api,
          session: widget.session,
          group: group,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedGroup>? groups = _groups;
    return GirlsScaffold(
      title: '友達グループ',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      pageBackgroundDecoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(_backgroundAsset),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: <Widget>[
            const _PrivateGroupsIntro(),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              _ErrorCard(message: _error!),
            ],
            const SizedBox(height: 16),
            _GroupActionButton(
              key: const Key('girls-group-find'),
              icon: Icons.vpn_key_rounded,
              label: 'グループIDで参加',
              onPressed: _busy ? null : _joinGroup,
            ),
            const SizedBox(height: 10),
            _GroupActionButton(
              key: const Key('girls-group-create'),
              icon: Icons.add_circle_rounded,
              label: '友達だけのグループを作る',
              onPressed: _busy ? null : _createGroup,
            ),
            const SizedBox(height: 24),
            const Text(
              '参加中のグループ',
              style: TextStyle(
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            if (groups == null)
              const Center(child: CircularProgressIndicator())
            else if (groups.isEmpty)
              const _EmptyPrivateGroups()
            else
              ...groups.map(
                (HostedGroup group) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PrivateGroupTile(
                    group: group,
                    disabled: _busy,
                    onOpen: () => _openGroup(group),
                    onSettings: () => _openSettings(group),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: const SizedBox.shrink(),
    );
  }
}

class _PrivateGroupsIntro extends StatelessWidget {
  const _PrivateGroupsIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8DCDD).withValues(alpha: .94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.lock_rounded, color: _pink, size: 32),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'いつものアプリは「みんなの広場」で楽しめます。ここでは、招待した友達だけの閉じたグループを作れます。',
              style: TextStyle(
                color: _ink,
                height: 1.55,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupActionButton extends StatelessWidget {
  const _GroupActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFF3CDD3),
          foregroundColor: _ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        icon: Icon(icon, color: const Color(0xFFB46F86)),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _PrivateGroupTile extends StatelessWidget {
  const _PrivateGroupTile({
    required this.group,
    required this.disabled,
    required this.onOpen,
    required this.onSettings,
  });

  final HostedGroup group;
  final bool disabled;
  final VoidCallback onOpen;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFEBD9DF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: ValueKey<String>('girls-private-group-${group.groupId}'),
        onTap: disabled ? null : onOpen,
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFF5DDE5),
          child: Icon(Icons.groups_rounded, color: _lavender),
        ),
        title: Text(
          group.name,
          style: const TextStyle(color: _ink, fontWeight: FontWeight.w900),
        ),
        subtitle: Text(group.isOwner ? 'オーナー' : 'メンバー'),
        trailing: IconButton(
          key:
              ValueKey<String>('girls-private-group-settings-${group.groupId}'),
          tooltip: 'グループ設定',
          onPressed: disabled ? null : onSettings,
          icon: const Icon(Icons.settings_rounded, color: _lavender),
        ),
      ),
    );
  }
}

class _EmptyPrivateGroups extends StatelessWidget {
  const _EmptyPrivateGroups();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        '友達グループにはまだ参加していません。普通に遊ぶだけなら、このままで大丈夫です。',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF75645F), height: 1.5),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE3E7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF9F455D),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
