import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'api.dart';
import 'girls_app_core.dart' as core;
import 'girls_builtin_install_api.dart';
import 'girls_current_group_store.dart';
import 'girls_scaffold.dart';
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF8B6BB2);
const Color _panelPink = Color(0xFFF8DCDD);
const Color _softCream = Color(0xFFFFFBF6);
const String _mascotPairAsset = 'assets/girls/mascot_pair.svg';

/// The Girls group tab is centered on one explicit "current group".
///
/// Browsing, joining, or creating another group never changes that selection.
/// Only [_switchCurrentGroup] persists a different group id.
class GirlsGroupsDashboardPage extends StatefulWidget {
  const GirlsGroupsDashboardPage({
    required this.api,
    required this.session,
    required this.currentGroup,
    required this.onCurrentGroupChanged,
    required this.currentGroupStore,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final HostedGroup? currentGroup;
  final ValueChanged<HostedGroup?> onCurrentGroupChanged;
  final GirlsCurrentGroupStore currentGroupStore;

  @override
  State<GirlsGroupsDashboardPage> createState() =>
      _GirlsGroupsDashboardPageState();
}

class _GirlsGroupsDashboardPageState extends State<GirlsGroupsDashboardPage> {
  HostedGroup? _currentGroup;
  List<HostedGroup>? _groups;
  List<HostedMember>? _members;
  List<HostedGroupApp>? _latestApps;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentGroup = widget.currentGroup;
    _reload();
  }

  @override
  void didUpdateWidget(covariant GirlsGroupsDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentGroup?.groupId != widget.currentGroup?.groupId) {
      _currentGroup = widget.currentGroup;
      _reload();
    }
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
      HostedGroup? current;
      final String? currentId = _currentGroup?.groupId;
      if (currentId != null) {
        for (final HostedGroup group in groups) {
          if (group.groupId == currentId) {
            current = group;
            break;
          }
        }
      }

      List<HostedMember>? members;
      List<HostedGroupApp>? latestApps;
      if (current != null) {
        members = await widget.api.listMembers(
          accessToken: widget.session.accessToken,
          groupId: current.groupId,
        );
        final List<HostedGroupApp> apps = await widget.api.listGroupApps(
          accessToken: widget.session.accessToken,
          groupId: current.groupId,
        );
        latestApps = apps
            .where(_isVisibleGroupApp)
            .toList(growable: false)
          ..sort(
            (HostedGroupApp a, HostedGroupApp b) =>
                b.createdAt.compareTo(a.createdAt),
          );
        if (latestApps.length > 3) {
          latestApps = latestApps.take(3).toList(growable: false);
        }
      }

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _currentGroup = current;
        _members = members;
        _latestApps = latestApps;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isVisibleGroupApp(HostedGroupApp app) {
    if (!app.isPublished) return false;
    final String? builtinId = app.builtinId;
    return builtinId != novelEditorBuiltinId &&
        builtinId != novelPlayerBuiltinId;
  }

  Future<void> _switchCurrentGroup(HostedGroup group) async {
    if (_currentGroup?.groupId == group.groupId) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.currentGroupStore.save(group.groupId);
      if (!mounted) return;
      setState(() => _currentGroup = group);
      widget.onCurrentGroupChanged(group);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「${group.name}」をいまのグループにしたよ。')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openGroup(HostedGroup group) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => core.GirlsGroupHomePage(
          api: widget.api,
          session: widget.session,
          group: group,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _joinGroup() async {
    final String? rawCode = await _showTextInputDialog(
      title: 'グループを探す',
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
        SnackBar(
          content: Text(
            '「${joined.name}」に参加したよ。いまのグループはそのままだよ。',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createGroup() async {
    final String? rawName = await _showTextInputDialog(
      title: 'グループを作る',
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
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
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

  Future<void> _showGroupId(HostedGroup group, HostedInvite invite) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('「${group.name}」を作ったよ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('友達はこのグループIDで参加できます。'),
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
            const SizedBox(height: 8),
            const Text(
              '作っただけでは「いまのグループ」は変わりません。切り替えたいときだけ下の一覧から選んでね。',
              style: TextStyle(fontSize: 12),
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

  @override
  Widget build(BuildContext context) {
    final HostedGroup? current = _currentGroup;
    final List<HostedGroup> groups = _groups ?? const <HostedGroup>[];
    final List<HostedGroup> otherGroups = current == null
        ? groups
        : groups
            .where((HostedGroup group) => group.groupId != current.groupId)
            .toList(growable: false);

    return GirlsScaffold(
      title: 'グループ',
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: <Widget>[
            if (current == null)
              _NoCurrentGroupCard(loading: _busy)
            else
              _CurrentGroupCard(
                group: current,
                members: _members,
                latestApps: _latestApps,
                loading: _busy,
                onOpen: () => _openGroup(current),
              ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              _ErrorCard(message: _error!),
            ],
            const SizedBox(height: 18),
            _BigGroupButton(
              key: const Key('girls-group-find'),
              icon: Icons.search_rounded,
              label: 'グループを探す',
              onPressed: _busy ? null : _joinGroup,
            ),
            const SizedBox(height: 12),
            _BigGroupButton(
              key: const Key('girls-group-create'),
              icon: Icons.add_circle_rounded,
              label: 'グループを作る',
              onPressed: _busy ? null : _createGroup,
            ),
            if (_groups == null) ...<Widget>[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ] else if (otherGroups.isNotEmpty) ...<Widget>[
              const SizedBox(height: 26),
              const Text(
                'ほかのグループ',
                style: TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              ...otherGroups.map(
                (HostedGroup group) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OtherGroupTile(
                    group: group,
                    disabled: _busy,
                    onOpen: () => _openGroup(group),
                    onSwitch: () => _switchCurrentGroup(group),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: const SizedBox.shrink(),
    );
  }
}

class _CurrentGroupCard extends StatelessWidget {
  const _CurrentGroupCard({
    required this.group,
    required this.members,
    required this.latestApps,
    required this.loading,
    required this.onOpen,
  });

  final HostedGroup group;
  final List<HostedMember>? members;
  final List<HostedGroupApp>? latestApps;
  final bool loading;
  final VoidCallback onOpen;

  HostedMember? get _owner {
    final List<HostedMember>? currentMembers = members;
    if (currentMembers == null) return null;
    for (final HostedMember member in currentMembers) {
      if (member.isOwner) return member;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final HostedMember? owner = _owner;
    final List<HostedGroupApp> apps = latestApps ?? const <HostedGroupApp>[];
    return Container(
      key: const Key('girls-current-group-dashboard-card'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: _panelPink.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x22956A80),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          const _GroupPicture(),
          const SizedBox(height: 12),
          Text(
            group.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          if (loading && members == null)
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Text(
              'オーナー: ${owner?.loginId ?? '—'}　メンバー数: ${members?.length ?? 0}',
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: _softCream.withValues(alpha: .82),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: <Widget>[
                const Text(
                  '最新アプリ',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                if (loading && latestApps == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (apps.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '公開されたアプリはまだないよ',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8C7893)),
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: apps
                        .map(
                          (HostedGroupApp app) => Expanded(
                            child: _LatestAppItem(app: app),
                          ),
                        )
                        .toList(growable: false),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('girls-current-group-open'),
              onPressed: loading ? null : onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: .7),
                foregroundColor: _ink,
                elevation: 0,
                side: const BorderSide(color: Color(0xFFE8B9C7)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text(
                'グループを開く',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupPicture extends StatelessWidget {
  const _GroupPicture();

  @override
  Widget build(BuildContext context) {
    // Hosted groups do not expose custom image metadata yet. Keep this explicit
    // visual slot stable so a future group image URL can replace only its body.
    return Container(
      key: const Key('girls-current-group-picture'),
      width: 92,
      height: 92,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7EAF0),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x22956A80), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: SvgPicture.asset(
        _mascotPairAsset,
        fit: BoxFit.contain,
        semanticsLabel: 'グループのデフォルト画像',
      ),
    );
  }
}

class _LatestAppItem extends StatelessWidget {
  const _LatestAppItem({required this.app});

  final HostedGroupApp app;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        children: <Widget>[
          _AppPicture(app: app),
          const SizedBox(height: 5),
          Text(
            app.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ink,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppPicture extends StatelessWidget {
  const _AppPicture({required this.app});

  final HostedGroupApp app;

  @override
  Widget build(BuildContext context) {
    final int seed = int.parse(app.appId.substring(0, 2), radix: 16);
    const List<IconData> icons = <IconData>[
      Icons.favorite_border_rounded,
      Icons.palette_outlined,
      Icons.menu_book_rounded,
      Icons.extension_rounded,
      Icons.celebration_outlined,
      Icons.pets_outlined,
    ];
    const List<Color> backgrounds = <Color>[
      Color(0xFFF8D8DE),
      Color(0xFFF6E1C9),
      Color(0xFFE4DAF5),
      Color(0xFFDDEEDC),
      Color(0xFFDCE9F6),
      Color(0xFFF3DCEC),
    ];
    final int index = seed % icons.length;

    // App icon metadata is intentionally not guessed from ZIP contents here.
    // Until the Hosted app contract exposes a validated icon, use a stable
    // default derived from app_id so the same app keeps the same appearance.
    return Container(
      key: ValueKey<String>('girls-latest-app-picture-${app.appId}'),
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: backgrounds[index],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7B7BF)),
      ),
      alignment: Alignment.center,
      child: Icon(icons[index], color: _ink, size: 31),
    );
  }
}

class _NoCurrentGroupCard extends StatelessWidget {
  const _NoCurrentGroupCard({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _panelPink.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Column(
        children: <Widget>[
          const _GroupPicture(),
          const SizedBox(height: 12),
          const Text(
            'いまのグループを選んでね',
            style: TextStyle(
              color: _ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'グループを見るだけでは切り替わらないよ。下の一覧から「切り替える」を押したときだけ変更します。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
          if (loading) ...<Widget>[
            const SizedBox(height: 12),
            const CircularProgressIndicator(strokeWidth: 2),
          ],
        ],
      ),
    );
  }
}

class _BigGroupButton extends StatelessWidget {
  const _BigGroupButton({
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
          elevation: 2,
          shadowColor: const Color(0x22956A80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: const BorderSide(color: Color(0xFFE6B8C2)),
          ),
        ),
        icon: Icon(icon, color: const Color(0xFFB46F86)),
        label: Text(
          label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _OtherGroupTile extends StatelessWidget {
  const _OtherGroupTile({
    required this.group,
    required this.disabled,
    required this.onOpen,
    required this.onSwitch,
  });

  final HostedGroup group;
  final bool disabled;
  final VoidCallback onOpen;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEBD9DF)),
      ),
      child: ListTile(
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
        trailing: TextButton(
          key: ValueKey<String>('girls-switch-group-${group.groupId}'),
          onPressed: disabled ? null : onSwitch,
          child: const Text('切り替える'),
        ),
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
