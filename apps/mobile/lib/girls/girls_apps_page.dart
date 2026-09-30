import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../hosted_app_management_api.dart' show maxHostedZipUploadBytes;
import '../hosted_app_webview.dart';
import '../hosted_authoring_editor_action.dart';
import '../hosted_authoring_projects_api.dart';
import 'api.dart';
import 'girls_errors.dart';
import 'girls_app_management_api.dart';
import 'girls_app_detail_content.dart';
import 'girls_app_test_actions.dart';
import 'girls_builtin_install_api.dart';
import 'girls_footer_nav.dart';
import 'girls_shop_api.dart';
import 'girls_scaffold.dart';
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF745B9E);
const Color _pink = Color(0xFFF9DDE8);
const Color _mint = Color(0xFFDDF4E4);
const String _girlsUploadPortalUrl = 'https://minapp.cloxs.jp/girls.html';
const String _novelContentFormat = 'minapp/novel@1';

String _novelProjectTitle(HostedAuthoringProject project) {
  if (project.summary.contentFormat != _novelContentFormat) {
    throw const FormatException(
        'Novel project has an unexpected content format.');
  }
  // An empty document is the Authoring contract's intentional
  // uninitialized draft state. The Novel Editor fills it on first open.
  if (project.document.isEmpty) {
    return '新しいノベル';
  }
  final Object? rawTitle = project.document['title'];
  if (rawTitle is! String ||
      rawTitle.isEmpty ||
      rawTitle != rawTitle.trim() ||
      rawTitle.length > 80) {
    throw const FormatException(
      'Novel project document has an invalid title.',
    );
  }
  return rawTitle;
}

bool _isNovelInfrastructureApp(ManagedGirlsApp app) {
  final String? builtinId = app.app.builtinId;
  return builtinId == novelEditorBuiltinId || builtinId == novelPlayerBuiltinId;
}

class GirlsAppsPage extends StatefulWidget {
  const GirlsAppsPage({
    required this.api,
    required this.session,
    this.onHome,
    this.onGroups,
    this.currentGroup,
    this.onCurrentGroupChanged,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final VoidCallback? onHome;
  final VoidCallback? onGroups;
  final HostedGroup? currentGroup;
  final ValueChanged<HostedGroup?>? onCurrentGroupChanged;

  @override
  State<GirlsAppsPage> createState() => _GirlsAppsPageState();
}

class _GirlsAppsPageState extends State<GirlsAppsPage> {
  late final GirlsAppManagementApi _managementApi;
  late final GirlsBuiltinInstallApi _builtinInstallApi;
  List<ManagedGirlsApp>? _apps;
  List<HostedGroup>? _activeGroups;
  HostedGroup? _currentGroup;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentGroup = widget.currentGroup;
    _managementApi = GirlsAppManagementApi(
        baseUri: widget.api.baseUri, client: widget.api.httpClient);
    _builtinInstallApi = GirlsBuiltinInstallApi(baseUri: widget.api.baseUri);
    _load();
  }

  @override
  void didUpdateWidget(covariant GirlsAppsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentGroup?.groupId != oldWidget.currentGroup?.groupId) {
      _currentGroup = widget.currentGroup;
    }
  }

  @override
  void dispose() {
    _managementApi.close();
    _builtinInstallApi.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedGroup> groups = await widget.api.listGroups(
        widget.session.accessToken,
      );
      final List<ManagedGirlsApp> apps = await _managementApi.listApps(
        widget.session.accessToken,
      );
      if (!mounted) return;
      final String? previousId = _currentGroup?.groupId;
      HostedGroup? currentGroup;
      if (previousId != null) {
        for (final HostedGroup group in groups) {
          if (group.groupId == previousId) {
            currentGroup = group;
            break;
          }
        }
      }
      currentGroup ??= groups.length == 1 ? groups.single : null;
      setState(() {
        _activeGroups = groups;
        _currentGroup = currentGroup;
        _apps = currentGroup == null
            ? <ManagedGirlsApp>[]
            : apps
                .where(
                  (ManagedGirlsApp app) =>
                      app.app.groupId == currentGroup!.groupId &&
                      !_isNovelInfrastructureApp(app),
                )
                .toList(growable: false);
      });
      if (previousId != currentGroup?.groupId) {
        widget.onCurrentGroupChanged?.call(currentGroup);
      }
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openUploadPortal() async {
    final List<HostedGroup>? activeGroups = _activeGroups;
    if (activeGroups == null) return;
    if (activeGroups.isEmpty) {
      setState(() => _error = 'アプリを追加するには、参加中のグループが必要です。');
      return;
    }
    final HostedGroup? group = _currentGroup;
    if (group == null) {
      setState(() => _error = '先に「グループ」から、いま使うグループを選んでね。');
      return;
    }

    setState(() => _error = null);
    final Uri portalUri = Uri.parse(_girlsUploadPortalUrl).replace(
      queryParameters: <String, String>{'group_id': group.groupId},
    );
    try {
      final bool opened = await launchUrl(
        portalUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw StateError('外部ブラウザを開けませんでした: $portalUri');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'アプリ追加ページを開けませんでした: $error');
    }
  }

  Future<void> _openDetailById(String appId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GirlsAppDetailPage(
          api: widget.api,
          session: widget.session,
          appId: appId,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openDetail(ManagedGirlsApp app) {
    return _openDetailById(app.app.appId);
  }

  Future<void> _launchPublishedApp(ManagedGirlsApp app) async {
    if (!app.app.isPublished || app.isHidden) {
      throw StateError(
        'Published app launch requires a visible published app.',
      );
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final launch = await widget.api.createLaunch(
        accessToken: widget.session.accessToken,
        groupId: app.app.groupId,
        appId: app.app.appId,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => HostedAppWebViewPage(
            title: app.app.title,
            launch: launch,
            runtimeTransport: widget.api.runtimeClient,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _openNovelMaker() async {
    final List<HostedGroup>? activeGroups = _activeGroups;
    if (activeGroups == null) return;
    if (activeGroups.isEmpty) {
      setState(() => _error = 'ノベルゲームを作るには、参加中のグループが必要です。');
      return;
    }
    final HostedGroup? group = _currentGroup;
    if (group == null) {
      setState(() => _error = '先に「グループ」から、いま使うグループを選んでね。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedGroupApp editor = await _builtinInstallApi.ensureNovelEditor(
        accessToken: widget.session.accessToken,
        groupId: group.groupId,
        includeSample: false,
      );
      final HostedAuthoringProjectSummary sample =
          await _builtinInstallApi.ensureNovelSampleProject(
        accessToken: widget.session.accessToken,
        groupId: group.groupId,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await openHostedAuthoringProjects(
        context: context,
        baseUri: widget.api.baseUri,
        accessToken: widget.session.accessToken,
        groupId: group.groupId,
        editorAppId: editor.appId,
        runtimeTransport: widget.api.runtimeClient,
        editorFormats: const <String>[_novelContentFormat],
        errorMessage: girlsMessageFor,
        pageTitle: 'ノベルゲームを作る',
        collectionTitle: 'あなたのノベル作品',
        emptyTitle: 'まだノベル作品がありません',
        emptyBody: '「新しくつくる」から物語を作ってみよう。',
        projectTitle: _novelProjectTitle,
        hiddenContentIds: <String>{sample.contentId},
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<ManagedGirlsApp>? apps = _apps;
    return GirlsScaffold(
      title: 'アプリ',
      actions: <Widget>[
        IconButton(
          tooltip: '更新',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: <Widget>[
            _CurrentGroupBanner(
              group: _currentGroup,
              onChange: widget.onGroups,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('girls-my-apps-upload'),
              onPressed: _busy ? null : _openUploadPortal,
              style: FilledButton.styleFrom(
                backgroundColor: _lavender,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('ZIPからアプリを追加'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('girls-my-apps-novel-maker'),
              onPressed: _busy ? null : _openNovelMaker,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('ノベルゲームを作る'),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              _ErrorCard(message: _error!),
            ],
            const SizedBox(height: 22),
            const Text(
              'マイアプリ',
              style: TextStyle(
                color: _ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            if (apps == null)
              const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_currentGroup == null)
              _NoCurrentGroup(onSelect: widget.onGroups)
            else if (apps.isEmpty)
              const _EmptyApps()
            else
              ...apps.map(
                (ManagedGirlsApp app) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ManagedAppCard(
                    app: app,
                    onTap: _busy ? null : () => _openDetail(app),
                    onPlayPublished:
                        _busy || !app.app.isPublished || app.isHidden
                            ? null
                            : () => _launchPublishedApp(app),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: GirlsFooterNav(
        selectedTab: GirlsFooterTab.apps,
        enabledTabs: <GirlsFooterTab>{
          if (widget.onHome != null) GirlsFooterTab.home,
          if (widget.onGroups != null) GirlsFooterTab.groups,
          GirlsFooterTab.apps,
          GirlsFooterTab.more,
        },
        onSelected: (GirlsFooterTab tab) {
          if (tab == GirlsFooterTab.home) {
            widget.onHome?.call();
            return;
          }
          if (tab == GirlsFooterTab.groups) {
            widget.onGroups?.call();
            return;
          }
          if (tab == GirlsFooterTab.more) {
            _showMoreMenu(context);
          }
        },
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFFFFBF7),
      builder: (BuildContext context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.apps_rounded, color: _lavender),
          title: const Text('マイアプリ'),
          subtitle: const Text('追加したアプリを管理'),
          onTap: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

class GirlsAppDetailPage extends StatefulWidget {
  const GirlsAppDetailPage({
    required this.api,
    required this.session,
    required this.appId,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final String appId;

  @override
  State<GirlsAppDetailPage> createState() => _GirlsAppDetailPageState();
}

class _GirlsAppDetailPageState extends State<GirlsAppDetailPage> {
  late final GirlsAppManagementApi _managementApi;
  late final GirlsShopApi _shopApi;
  ManagedGirlsAppDetail? _detail;
  String? _authorLabel;
  bool? _shopListed;
  bool _shopBusy = false;
  String? _shopError;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _managementApi = GirlsAppManagementApi(
        baseUri: widget.api.baseUri, client: widget.api.httpClient);
    _shopApi = GirlsShopApi(
      baseUri: widget.api.baseUri,
      client: widget.api.httpClient,
    );
    _load();
  }

  @override
  void dispose() {
    _managementApi.close();
    _shopApi.close();
    super.dispose();
  }

  Future<void> _load({
    int? expectedSourceRevision,
    bool clearDetailOnError = false,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ManagedGirlsAppDetail detail = await _managementApi.getApp(
        accessToken: widget.session.accessToken,
        appId: widget.appId,
      );
      if (expectedSourceRevision != null &&
          detail.summary.sourceRevision != expectedSourceRevision) {
        throw StateError(
          'Reloaded source revision ${detail.summary.sourceRevision} '
          'does not match saved revision $expectedSourceRevision.',
        );
      }
      final List<HostedMember> members = await widget.api.listMembers(
        accessToken: widget.session.accessToken,
        groupId: detail.summary.app.groupId,
      );
      final List<HostedMember> authors = members
          .where((HostedMember member) =>
              member.userId == detail.summary.app.ownerUserId)
          .toList(growable: false);
      if (authors.length > 1) {
        throw StateError('Group member list contains duplicate app owner IDs.');
      }
      final String authorLabel = authors.isEmpty
          ? '退出済みユーザー (${detail.summary.app.ownerUserId.substring(0, 8)}…)'
          : authors.single.displayLabel;

      bool? shopListed;
      String? shopError;
      if (detail.summary.app.isPublished) {
        try {
          final List<GirlsShopApp> shopApps =
              await _shopApi.listApps(widget.session.accessToken);
          final int matches = shopApps
              .where((GirlsShopApp item) => item.appId == detail.summary.app.appId)
              .length;
          if (matches > 1) {
            throw StateError('Girls shop returned duplicate app_id entries.');
          }
          shopListed = matches == 1;
        } catch (error) {
          shopError = girlsMessageFor(error);
        }
      } else {
        shopListed = false;
      }

      if (mounted) {
        setState(() {
          _detail = detail;
          _authorLabel = authorLabel;
          _shopListed = shopListed;
          _shopError = shopError;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          if (clearDetailOnError) _detail = null;
          _error = girlsMessageFor(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reloadAfterSourceSave(int revision) async {
    await _load(
      expectedSourceRevision: revision,
      clearDetailOnError: true,
    );
  }

  Future<void> _downloadZip() async {
    final ManagedGirlsAppDetail? detail = _detail;
    final int? revision = detail?.summary.sourceRevision;
    if (detail == null || revision == null) {
      setState(() => _error = '保存する編集版を確認できません。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final GirlsSourceDownload download = await _managementApi.downloadSource(
        accessToken: widget.session.accessToken,
        groupId: detail.summary.app.groupId,
        appId: detail.summary.app.appId,
      );
      if (download.revision != revision) {
        throw StateError(
          'Downloaded source revision ${download.revision} does not match $revision.',
        );
      }
      final Uri? savedPath = await FilePicker.saveFile(
        dialogTitle: 'ZIPを保存',
        fileName: 'minapp-${detail.summary.app.appId}.zip',
        bytes: download.bytes,
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ZIPを保存しました。')));
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish({bool makeVisible = false}) async {
    final ManagedGirlsAppDetail? detail = _detail;
    final int? revision = detail?.summary.sourceRevision;
    if (detail == null || revision == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _managementApi.publish(
        accessToken: widget.session.accessToken,
        groupId: detail.summary.app.groupId,
        appId: detail.summary.app.appId,
        revision: revision,
      );
      if (makeVisible && detail.summary.isHidden) {
        await _managementApi.setHidden(
          accessToken: widget.session.accessToken,
          appId: detail.summary.app.appId,
          hidden: false,
        );
      }
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleHidden() async {
    final ManagedGirlsAppDetail? detail = _detail;
    if (detail == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _managementApi.setHidden(
        accessToken: widget.session.accessToken,
        appId: detail.summary.app.appId,
        hidden: !detail.summary.isHidden,
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateZip() async {
    final ManagedGirlsAppDetail? detail = _detail;
    final int? revision = detail?.summary.sourceRevision;
    if (detail == null || revision == null || !detail.summary.app.editable) {
      setState(() => _error = '更新する編集版を確認できません。');
      return;
    }

    final PlatformFile? file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
    );
    if (file == null || !mounted) return;
    if (file.extension?.toLowerCase() != 'zip') {
      setState(() => _error = '拡張子 .zip のファイルを選んでください。');
      return;
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxHostedZipUploadBytes) {
      setState(() => _error = 'ZIPは1byte以上2MB以下にしてください。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final int nextRevision = await _managementApi.updateSource(
        accessToken: widget.session.accessToken,
        groupId: detail.summary.app.groupId,
        appId: detail.summary.app.appId,
        expectedRevision: revision,
        zipBytes: bytes,
      );
      if (mounted) {
        await _load(
          expectedSourceRevision: nextRevision,
          clearDetailOnError: true,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _setShopListed(bool listed) async {
    final ManagedGirlsAppDetail? detail = _detail;
    if (detail == null || !detail.summary.app.isPublished) {
      setState(() => _shopError = 'ショップ掲載には先にアプリを公開してください。');
      return;
    }
    if (_shopBusy) return;
    setState(() {
      _shopBusy = true;
      _shopError = null;
    });
    try {
      await _shopApi.setVisibility(
        accessToken: widget.session.accessToken,
        appId: detail.summary.app.appId,
        listed: listed,
      );
      if (!mounted) return;
      setState(() => _shopListed = listed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            listed ? 'ショップに掲載したよ。' : 'ショップから取り下げたよ。',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _shopError = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _shopBusy = false);
    }
  }

  Widget _advancedSettings(ManagedGirlsAppDetail detail) {
    final ManagedGirlsApp app = detail.summary;
    return ExpansionTile(
      key: const Key('girls-app-advanced-settings'),
      title: const Text(
        'その他の設定',
        style: TextStyle(
          color: _lavender,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 10),
      children: <Widget>[
        if (app.app.editable && app.sourceRevision != null)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('girls-app-update-zip'),
              onPressed: _busy ? null : _updateZip,
              icon: const Icon(Icons.folder_zip_rounded),
              label: const Text('新しいZIPで更新'),
            ),
          ),
        const SizedBox(height: 10),
        if (!app.app.isPublished)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'ショップに出すには、先に上の公開スイッチでアプリを公開してね。',
              style: TextStyle(fontSize: 12, color: _lavender),
            ),
          )
        else if (_shopListed == null && _shopError == null)
          const LinearProgressIndicator()
        else if (_shopListed != null)
          SwitchListTile(
            key: const Key('girls-app-shop-listing'),
            contentPadding: EdgeInsets.zero,
            title: const Text('ショップに掲載'),
            subtitle: Text(
              _shopListed! ? 'ショップ掲載中' : 'ショップには出していません',
            ),
            value: _shopListed!,
            onChanged: _busy || _shopBusy ? null : _setShopListed,
          ),
        if (_shopError != null) ...<Widget>[
          const SizedBox(height: 8),
          _ErrorCard(message: 'ショップ状態を確認できませんでした。$_shopError'),
        ],
      ],
    );
  }

  Future<void> _delete() async {
    final ManagedGirlsAppDetail? detail = _detail;
    if (detail == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('このアプリを削除する？'),
        content: Text('「${detail.summary.app.title}」を削除します。この操作は取り消せません。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('削除する'),
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
      await _managementApi.deleteApp(
        accessToken: widget.session.accessToken,
        groupId: detail.summary.app.groupId,
        appId: detail.summary.app.appId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeVisibility() async {
    final detail = _detail;
    if (detail == null) return;
    if (!detail.summary.app.isPublished) {
      await _publish(makeVisible: true);
    } else {
      await _toggleHidden();
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        primary: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        title: const Text('アプリ詳細'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '最新の情報に更新',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
          children: [
            if (_error != null) ...[
              _ErrorCard(message: _error!),
              TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('もう一度読み込む')),
            ],
            if (detail == null && _busy)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (detail != null) ...[
              GirlsAppDetailContent(
                detail: detail,
                authorLabel: _authorLabel ?? '確認中…',
                busy: _busy,
                onVisibilityChanged: detail.summary.app.isPublished ||
                        (detail.summary.app.editable &&
                            detail.summary.sourceRevision != null)
                    ? _changeVisibility
                    : null,
                onPublish: _publish,
                onDownload:
                    detail.summary.sourceRevision == null ? null : _downloadZip,
                onDelete: _delete,
                actions: GirlsAppTestActions(
                  api: widget.api,
                  session: widget.session,
                  detail: detail,
                  onSourceSaved: _reloadAfterSourceSave,
                  detailLayout: true,
                  disabled: _busy,
                ),
              ),
              const SizedBox(height: 12),
              _advancedSettings(detail),
              const SizedBox(height: 8),
              ExpansionTile(
                title: const Text('保存・公開の履歴',
                    style: TextStyle(fontSize: 13, color: _lavender)),
                tilePadding: EdgeInsets.zero,
                children: [
                  for (final item in detail.sourceHistory)
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('保存'),
                      subtitle: Text(_formatDate(item.createdAt)),
                    ),
                  for (final item in detail.publishedHistory)
                    ListTile(
                      leading: const Icon(Icons.public_rounded),
                      title: const Text('公開'),
                      subtitle: Text(_formatDate(item.publishedAt)),
                    ),
                  if (detail.sourceHistory.isEmpty &&
                      detail.publishedHistory.isEmpty)
                    const ListTile(title: Text('まだ履歴がありません。')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CurrentGroupBanner extends StatelessWidget {
  const _CurrentGroupBanner({required this.group, required this.onChange});

  final HostedGroup? group;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('girls-apps-current-group'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF1E8FA).withValues(alpha: .78),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.groups_rounded, color: _lavender),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'いまのグループ',
                  style: TextStyle(
                    color: Color(0xFF8F7A74),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  group?.name ?? 'まだ選んでいません',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            child: Text(group == null ? '選ぶ' : '変更'),
          ),
        ],
      ),
    );
  }
}

class _NoCurrentGroup extends StatelessWidget {
  const _NoCurrentGroup({required this.onSelect});

  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: <Widget>[
          const Text(
            'グループを選ぶと、そのグループのアプリだけがここに並ぶよ。',
            textAlign: TextAlign.center,
            style: TextStyle(color: _ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onSelect,
            icon: const Icon(Icons.groups_rounded),
            label: const Text('グループを選ぶ'),
          ),
        ],
      ),
    );
  }
}

class _ManagedAppCard extends StatelessWidget {
  const _ManagedAppCard({
    required this.app,
    required this.onTap,
    required this.onPlayPublished,
  });
  final ManagedGirlsApp app;
  final VoidCallback? onTap;
  final VoidCallback? onPlayPublished;

  @override
  Widget build(BuildContext context) {
    final String status = app.isHidden
        ? '非公開'
        : app.app.isPublished
            ? '公開中'
            : '下書き';
    return Material(
      color: Colors.white.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: app.isHidden ? const Color(0xFFE9E2E0) : _pink,
                foregroundColor: _lavender,
                child: const Icon(Icons.apps_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      app.app.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$status  ・  ${app.stats.uniqueUsers}人 / ${app.stats.totalPlays}回',
                    ),
                    if (app.groupName != null)
                      Text(
                        app.groupName!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8F7A74),
                        ),
                      ),
                  ],
                ),
              ),
              if (onPlayPublished != null)
                IconButton(
                  key: ValueKey<String>(
                    'girls-app-play-published-${app.app.appId}',
                  ),
                  tooltip: '公開版で遊ぶ',
                  onPressed: onPlayPublished,
                  icon: const Text('▶️', style: TextStyle(fontSize: 21)),
                ),
              const Icon(Icons.chevron_right_rounded, color: _lavender),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyApps extends StatelessWidget {
  const _EmptyApps();

  static const String _technicalGuideUrl =
      'https://cloxs.jp/minapp/ai/index.html';
  static const String _basePrompt =
      'みんアプ技術資料 $_technicalGuideUrl を見て、○○のアプリを作って。HTML・CSS・JavaScriptは1つのindex.htmlにまとめて、完成したHTMLコードをそのまま出して。';

  Future<void> _copyPrompt(BuildContext context, String prompt) async {
    await Clipboard.setData(ClipboardData(text: prompt));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('AIに貼る文章をコピーしたよ')));
  }

  String _ideaPrompt(String idea) =>
      'みんアプ技術資料 $_technicalGuideUrl を見て、$ideaのアプリを作って。HTML・CSS・JavaScriptは1つのindex.htmlにまとめて、完成したHTMLコードをそのまま出して。';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 4),
        const Text(
          'まだ自作アプリがありません。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ink,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              flex: 4,
              child: Image.asset(
                'assets/girls/cutouts/mascot_white.png',
                height: 132,
                fit: BoxFit.contain,
                semanticLabel: 'みんアプ Girls のマスコット',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFB99B91)),
                ),
                child: const Text(
                  'AIに頼んで、\n最初のアプリを\n作ってみよう！',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    height: 1.35,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFDCE7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFF2B8CA)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x1F8E6977),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'お手元のAIにこれを貼ってね！',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF9E8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFC9A89D)),
                ),
                child: const SelectableText(
                  '「$_basePrompt」',
                  style: TextStyle(
                    color: _ink,
                    height: 1.35,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('girls-empty-app-copy-prompt'),
                  onPressed: () => _copyPrompt(context, _basePrompt),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF9F78BB),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('コピー'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'どんなアプリを作ってみる？',
          style: TextStyle(
            color: _ink,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.16,
          children: <Widget>[
            _EmptyAppIdeaCard(
              color: const Color(0xFFD9EBFF),
              icon: Icons.wb_sunny_rounded,
              title: 'お天気アプリ',
              subtitle: '天気を見られるアプリ',
              onTap: () => _copyPrompt(context, _ideaPrompt('お天気')),
            ),
            _EmptyAppIdeaCard(
              color: _mint,
              icon: Icons.restaurant_menu_rounded,
              title: 'レシピアプリ',
              subtitle: '料理をまとめるアプリ',
              onTap: () => _copyPrompt(context, _ideaPrompt('レシピ')),
            ),
            _EmptyAppIdeaCard(
              color: const Color(0xFFFFE8A8),
              icon: Icons.checklist_rounded,
              title: 'ToDoアプリ',
              subtitle: 'やることを管理するアプリ',
              onTap: () => _copyPrompt(context, _ideaPrompt('ToDo')),
            ),
            _EmptyAppIdeaCard(
              color: const Color(0xFFE5D8F6),
              icon: Icons.auto_awesome_rounded,
              title: '占いアプリ',
              subtitle: '今日の運勢を占うアプリ',
              onTap: () => _copyPrompt(context, _ideaPrompt('占い')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'アイデアカードをタップすると、その内容を入れた文章をコピーできるよ。\nAIがHTMLを作ってくれたら、上の「アプリを追加」からポータルを開いて貼り付けてね♡',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF8F756D),
            fontSize: 11,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _EmptyAppIdeaCard extends StatelessWidget {
  const _EmptyAppIdeaCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Icon(icon, color: _lavender, size: 38),
              const SizedBox(height: 7),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 10,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
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
        color: const Color(0xFFFFECEF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB8C5)),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFF9E3348))),
    );
  }
}

String _formatDate(DateTime value) {
  final DateTime local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
