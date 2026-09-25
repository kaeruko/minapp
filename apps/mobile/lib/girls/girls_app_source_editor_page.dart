import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'girls_errors.dart';
import 'girls_app_management_api.dart';
import 'girls_scaffold.dart';
import 'girls_source_zip.dart';

const Color _cream = Color(0xFFFFFAF0);
const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF745B9E);
const String _girlsHowToUrl = 'https://cloxs.jp/minapp/girls/howto.html';

class GirlsAppSourceEditorPage extends StatefulWidget {
  const GirlsAppSourceEditorPage({
    required this.api,
    required this.accessToken,
    required this.groupId,
    required this.appId,
    required this.title,
    required this.expectedRevision,
    super.key,
  });

  final GirlsAppManagementApi api;
  final String accessToken;
  final String groupId;
  final String appId;
  final String title;
  final int expectedRevision;

  @override
  State<GirlsAppSourceEditorPage> createState() =>
      _GirlsAppSourceEditorPageState();
}

class _GirlsAppSourceEditorPageState extends State<GirlsAppSourceEditorPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _editorFocusNode = FocusNode();
  GirlsSourceArchive? _archive;
  Map<String, String> _originalTexts = <String, String>{};
  Map<String, String> _draftTexts = <String, String>{};
  List<String> _textPaths = <String>[];
  String? _selectedPath;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _updatingController = false;

  bool get _dirty {
    if (_originalTexts.length != _draftTexts.length) return true;
    for (final MapEntry<String, String> entry in _originalTexts.entries) {
      if (_draftTexts[entry.key] != entry.value) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _load();
  }

  @override
  void dispose() {
    _editorFocusNode.dispose();
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_updatingController) return;
    final String? path = _selectedPath;
    if (path == null) return;
    final String value = _controller.text;
    if (_draftTexts[path] == value) return;
    setState(() => _draftTexts[path] = value);
  }

  void _setControllerText(String value) {
    _updatingController = true;
    try {
      _controller.value = TextEditingValue(
        text: value,
        selection: const TextSelection.collapsed(offset: 0),
      );
    } finally {
      _updatingController = false;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final GirlsSourceDownload download = await widget.api.downloadSource(
        accessToken: widget.accessToken,
        groupId: widget.groupId,
        appId: widget.appId,
      );
      if (download.revision != widget.expectedRevision) {
        throw StateError(
          'Source revision changed before editor load: '
          'expected=${widget.expectedRevision}, actual=${download.revision}.',
        );
      }
      final GirlsSourceArchive archive =
          GirlsSourceArchive.decode(download.bytes);
      final List<String> textPaths = archive.textPaths;
      if (textPaths.isEmpty) {
        throw const FormatException('編集できるUTF-8テキストファイルがありません。');
      }
      final Map<String, String> texts = <String, String>{};
      for (final String path in textPaths) {
        texts[path] = archive.readText(path);
      }
      final String selected =
          textPaths.contains('index.html') ? 'index.html' : textPaths.first;
      if (!mounted) return;
      setState(() {
        _archive = archive;
        _textPaths = textPaths;
        _originalTexts = Map<String, String>.from(texts);
        _draftTexts = Map<String, String>.from(texts);
        _selectedPath = selected;
        _loading = false;
      });
      _setControllerText(texts[selected]!);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = girlsMessageFor(error);
      });
    }
  }

  void _selectPath(String? path) {
    if (path == null || path == _selectedPath) return;
    final String? value = _draftTexts[path];
    if (value == null) {
      throw StateError('Selected source path has no draft text: $path');
    }
    setState(() => _selectedPath = path);
    _setControllerText(value);
  }

  Future<void> _showHelp() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        key: const Key('girls-source-editor-help-dialog'),
        title: const Text('コード編集で迷ったら？'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'わからないところは、AIに相談しながら進めよう。',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 12),
            Text(
              '「背景をピンクにしたい」「ボタンを増やしたい」みたいに、'
              'やりたいことをそのまま伝えてみよう。',
            ),
            SizedBox(height: 12),
            Text(
              'みんアプGirlsの使い方ガイドには、AIにアレンジをお願いする流れも載っているよ。',
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('girls-source-editor-help-close'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('閉じる'),
          ),
          FilledButton.icon(
            key: const Key('girls-source-editor-howto'),
            onPressed: () async {
              final Uri uri = Uri.parse(_girlsHowToUrl);
              final bool opened = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
              if (!opened) {
                throw StateError('使い方ガイドを開けませんでした: $uri');
              }
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('使い方ガイドを見る'),
          ),
        ],
      ),
    );
  }

  Future<void> _goHome(VoidCallback homeAction) async {
    if (_saving) return;
    if (_dirty) {
      final bool leave =
          await showDialog<bool>(
            context: context,
            builder: (BuildContext dialogContext) => AlertDialog(
              key: const Key('girls-source-editor-home-confirm-dialog'),
              title: const Text('ホームに戻る？'),
              content: const Text('まだ保存していない変更は消えます。'),
              actions: <Widget>[
                TextButton(
                  key: const Key('girls-source-editor-home-cancel'),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('編集を続ける'),
                ),
                FilledButton(
                  key: const Key('girls-source-editor-home-confirm'),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('ホームに戻る'),
                ),
              ],
            ),
          ) ??
          false;
      if (!leave || !mounted) return;
    }
    homeAction();
  }

  Future<void> _save() async {
    final GirlsSourceArchive? archive = _archive;
    if (archive == null || !_dirty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      for (final MapEntry<String, String> entry in _draftTexts.entries) {
        archive.writeText(entry.key, entry.value);
      }
      final int revision = await widget.api.updateSource(
        accessToken: widget.accessToken,
        groupId: widget.groupId,
        appId: widget.appId,
        expectedRevision: widget.expectedRevision,
        zipBytes: archive.encode(),
      );
      if (!mounted) return;
      Navigator.of(context).pop<int>(revision);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final VoidCallback? homeAction =
        GirlsScaffoldChromeScope.homeAction(context);
    return Scaffold(
      backgroundColor: _cream,
      // The authenticated shell already subtracts the keyboard height.
      resizeToAvoidBottomInset: !GirlsScaffoldChromeScope.isEmbedded(context),
      appBar: AppBar(
        backgroundColor: _cream,
        foregroundColor: _ink,
        title: Text('${widget.title} のコード'),
        actions: <Widget>[
          IconButton(
            key: const Key('girls-source-editor-help'),
            tooltip: 'コード編集のヒント',
            onPressed: _showHelp,
            icon: const Icon(Icons.help_outline_rounded),
          ),
          if (!_loading && _archive != null)
            PopupMenuButton<String>(
              key: const Key('girls-source-editor-file-menu'),
              tooltip: '編集するファイル',
              enabled: !_saving,
              icon: const Icon(Icons.folder_open_rounded),
              onSelected: (String path) => _selectPath(path),
              itemBuilder: (BuildContext context) => _textPaths
                  .map(
                    (String path) => PopupMenuItem<String>(
                      value: path,
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: 28,
                            child: path == _selectedPath
                                ? const Icon(Icons.check_rounded, size: 18)
                                : null,
                          ),
                          Expanded(
                            child: Text(
                              path,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          if (!_loading && _archive != null)
            IconButton(
              key: const Key('girls-source-editor-save-appbar'),
              tooltip: '編集版を保存',
              onPressed: !_dirty || _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (homeAction != null && !keyboardVisible)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('girls-source-editor-home'),
                    onPressed: _saving ? null : () => _goHome(homeAction),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      backgroundColor: const Color(0xFFF2E9FF),
                      side: const BorderSide(color: Color(0xFFCAB7DF)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.home_rounded, size: 20),
                    label: const Text(
                      'ホーム',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildEditor(keyboardVisible: keyboardVisible),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor({required bool keyboardVisible}) {
    if (_archive == null) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_error != null) _EditorError(message: _error!),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('もう一度読み込む'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: <Widget>[
        keyboardVisible
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 8),
                      _EditorError(message: _error!),
                    ],
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: const Key('girls-source-editor-file'),
                      initialValue: _selectedPath,
                      decoration: const InputDecoration(
                        labelText: '編集するファイル',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _textPaths
                          .map(
                            (String path) => DropdownMenuItem<String>(
                              value: path,
                              child: Text(
                                path,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _saving ? null : _selectPath,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'HTML / CSS / JavaScript / JSON / TXT を編集できます。画像・音声などのファイルはそのまま保持します。',
                      style: TextStyle(fontSize: 11, color: _lavender),
                    ),
                  ],
                ),
              ),
        Expanded(
          // Both surrounding controls change type when the IME opens. Keep
          // this subtree keyed so Flutter does not dispose EditableText and
          // close its input connection while reconciling the middle children.
          key: const Key('girls-source-editor-viewport'),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              keyboardVisible ? 12 : 16,
              keyboardVisible ? 8 : 0,
              keyboardVisible ? 12 : 16,
              keyboardVisible ? 8 : 0,
            ),
            child: _buildCodeField(),
          ),
        ),
        keyboardVisible
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: FilledButton.icon(
                  key: const Key('girls-source-editor-save'),
                  onPressed: !_dirty || _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? '保存中…' : '編集版を保存'),
                ),
              ),
      ],
    );
  }

  Widget _buildCodeField() {
    return SizedBox.expand(
      child: TextField(
        key: const Key('girls-source-editor-code'),
        controller: _controller,
        focusNode: _editorFocusNode,
        enabled: !_saving,
        expands: true,
        maxLines: null,
        minLines: null,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        autocorrect: false,
        enableSuggestions: false,
        scrollPadding: EdgeInsets.zero,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.45,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white.withValues(alpha: .94),
          contentPadding: const EdgeInsets.all(12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _EditorError extends StatelessWidget {
  const _EditorError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECEF),
        borderRadius: BorderRadius.circular(14),
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
