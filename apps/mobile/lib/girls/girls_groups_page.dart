import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'api.dart';
import 'girls_app_core.dart' as core;
import 'girls_footer_nav.dart';
import 'hosted_girls_api.dart';

const Color _lavender = Color(0xFFB39DDB);
const Color _lavenderDark = Color(0xFF745B9E);
const Color _pink = Color(0xFFFFC4D6);
const Color _mint = Color(0xFFC8F3D0);
const Color _blue = Color(0xFFC9E5FF);
const String _mascotPairAsset = 'assets/girls/mascot_pair.svg';
const String _girlsLogoAsset =
    'assets/girls/generated/minapp_girls_logo.png';

/// Girls group selection page using the reusable five-hill footer.
///
/// Only the Groups destination is enabled for now because the other four
/// destination pages do not exist yet. Their visual slots are present without
/// inventing fake navigation behavior.
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
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
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
  }) {
    String value = '';

    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: key,
          maxLength: maxLength,
          autocorrect: !capitalize,
          enableSuggestions: !capitalize,
          textCapitalization: capitalize
              ? TextCapitalization.characters
              : TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onChanged: (String nextValue) {
            value = nextValue;
          },
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
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
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
          _error = core.girlsMessageFor(error);
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
              'グループ「${createdGroup.name}」は作成できたけれど、グループIDの発行に失敗し、その後の一覧更新にも失敗しました。${core.girlsMessageFor(error)} / ${core.girlsMessageFor(reloadError)}';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _error =
            'グループ「${createdGroup.name}」は作成できたけれど、グループIDの発行に失敗しました。${core.girlsMessageFor(error)}';
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
        builder: (BuildContext context) => core.GirlsGroupHomePage(
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
      backgroundColor: const Color(0xFFFDF9EE),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Image.asset(
                        _girlsLogoAsset,
                        width: 112,
                        height: 52,
                        fit: BoxFit.contain,
                        semanticLabel: 'みんアプ Girls',
                      ),
                    ),
                  ),
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
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _PastelPanel(
                          child: Row(
                            children: <Widget>[
                              SvgPicture.asset(
                                _mascotPairAsset,
                                width: 92,
                                height: 76,
                                fit: BoxFit.contain,
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
      bottomNavigationBar: const SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: GirlsFooterNav(
          selectedTab: GirlsFooterTab.groups,
          enabledTabs: <GirlsFooterTab>{GirlsFooterTab.groups},
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
