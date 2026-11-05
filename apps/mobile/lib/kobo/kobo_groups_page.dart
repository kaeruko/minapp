import 'package:flutter/material.dart';

import '../api.dart';
import '../hosted_consumer_api.dart';
import '../hosted_consumer_errors.dart';
import '../hosted_group_management_page.dart';
import '../hosted_private_group_dialogs.dart';
import '../hosted_private_groups.dart';
import 'kobo_theme.dart';

class KoboGroupsPage extends StatefulWidget {
  const KoboGroupsPage({
    required this.api,
    required this.session,
    super.key,
  });

  final HostedConsumerApi api;
  final AuthenticatedSession session;

  @override
  State<KoboGroupsPage> createState() => _KoboGroupsPageState();
}

class _KoboGroupsPageState extends State<KoboGroupsPage> {
  late final HostedPrivateGroupsService _privateGroupService;
  List<HostedGroup>? _privateGroups;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _privateGroupService = HostedPrivateGroupsService(
      api: widget.api,
      session: widget.session,
    );
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedPrivateGroupsSnapshot snapshot =
          await _privateGroupService.load();
      if (mounted) setState(() => _privateGroups = snapshot.privateGroups);
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final String? rawName = await showHostedPrivateGroupTextDialog(
      context: context,
      title: '非公開グループをつくる',
      label: 'グループ名',
      hint: '例：釣り仲間の工房',
      maxLength: maxHostedGroupNameLength,
      submitLabel: 'つくる',
      capitalize: false,
      initialValue: '仲間の工房',
    );
    if (rawName == null || !mounted) return;
    final String name = rawName.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedPrivateGroupCreation creation =
          await _privateGroupService.create(name: name);
      if (mounted) {
        setState(() => _busy = false);
        await _load();
        if (!mounted) return;
        await showHostedPrivateGroupCreatedDialog(
          context: context,
          creation: creation,
          title: '「${creation.group.name}」を作りました',
          codeColor: KoboColors.navy,
          codeBackgroundColor: KoboColors.paper,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final String? rawCode = await showHostedPrivateGroupTextDialog(
      context: context,
      title: 'グループに参加する',
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
      await _privateGroupService.join(code: code);
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
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
    final List<HostedGroup>? groups = _privateGroups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('非公開グループ'),
        actions: <Widget>[
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '更新',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(KoboSpacing.md),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(KoboSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      '普段は「みんなの工房」だけで遊べます。',
                      style: KoboTextStyles.cardTitle,
                    ),
                    const SizedBox(height: KoboSpacing.xs),
                    Text(
                      '限られた仲間だけで道具を置きたいときに、非公開グループを追加してください。',
                      style: KoboTextStyles.body,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: KoboSpacing.md),
            FilledButton.icon(
              key: const Key('kobo-create-group'),
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('非公開グループをつくる'),
            ),
            const SizedBox(height: KoboSpacing.xs),
            OutlinedButton.icon(
              key: const Key('kobo-join-group'),
              onPressed: _busy ? null : _join,
              icon: const Icon(Icons.vpn_key_outlined),
              label: const Text('グループIDで参加する'),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: KoboSpacing.sm),
              Text(_error!, style: const TextStyle(color: KoboColors.error)),
            ],
            const SizedBox(height: KoboSpacing.lg),
            const Text('参加中の非公開グループ', style: KoboTextStyles.sectionTitle),
            const SizedBox(height: KoboSpacing.sm),
            if (groups == null)
              const Center(child: CircularProgressIndicator())
            else if (groups.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(KoboSpacing.lg),
                  child: Text('非公開グループにはまだ参加していません。'),
                ),
              )
            else
              for (final HostedGroup group in groups)
                Card(
                  child: ListTile(
                    leading: Icon(
                      group.isOwner
                          ? Icons.admin_panel_settings_outlined
                          : Icons.groups_outlined,
                      color: KoboColors.navy,
                    ),
                    title: Text(group.name),
                    subtitle: Text(group.isOwner ? 'オーナー' : 'メンバー'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _busy ? null : () => _open(group),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
