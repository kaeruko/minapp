import 'package:flutter/material.dart';

import '../hosted_app_management_api.dart';
import '../hosted_consumer_errors.dart';
import '../hosted_source_archive.dart';
import 'kobo_theme.dart';

class KoboSourceEditorPage extends StatefulWidget {
  const KoboSourceEditorPage({
    required this.api,
    required this.accessToken,
    required this.groupId,
    required this.appId,
    required this.title,
    required this.expectedRevision,
    super.key,
  });

  final HostedAppManagementApi api;
  final String accessToken;
  final String groupId;
  final String appId;
  final String title;
  final int expectedRevision;

  @override
  State<KoboSourceEditorPage> createState() => _KoboSourceEditorPageState();
}

class _KoboSourceEditorPageState extends State<KoboSourceEditorPage> {
  final TextEditingController _controller = TextEditingController();
  HostedSourceArchive? _archive;
  List<String> _textPaths = const <String>[];
  String? _selectedPath;
  String? _originalText;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _updatingController = false;
  late int _revision;

  bool get _dirty => _selectedPath != null && _controller.text != _originalText;

  @override
  void initState() {
    super.initState();
    _revision = widget.expectedRevision;
    _controller.addListener(_refreshDirtyState);
    _load();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refreshDirtyState)
      ..dispose();
    super.dispose();
  }

  void _refreshDirtyState() {
    if (!_updatingController && mounted) setState(() {});
  }

  void _setControllerText(String value) {
    _updatingController = true;
    try {
      _controller.text = value;
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
      final HostedSourceDownload download = await widget.api.downloadSource(
        accessToken: widget.accessToken,
        groupId: widget.groupId,
        appId: widget.appId,
      );
      final HostedSourceArchive archive =
          HostedSourceArchive.decode(download.bytes);
      final List<String> paths = archive.textPaths;
      if (paths.isEmpty) {
        throw const FormatException('編集できるテキストファイルがありません。');
      }
      final String selected =
          paths.contains('index.html') ? 'index.html' : paths.first;
      final String text = archive.readText(selected);
      if (!mounted) return;
      setState(() {
        _archive = archive;
        _textPaths = paths;
        _selectedPath = selected;
        _originalText = text;
        _setControllerText(text);
        _revision = download.revision;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectPath(String? path) {
    final HostedSourceArchive? archive = _archive;
    if (path == null || archive == null || path == _selectedPath) return;
    if (_dirty) {
      setState(() => _error = '先に現在のファイルを保存してください。');
      return;
    }
    final String text = archive.readText(path);
    setState(() {
      _selectedPath = path;
      _originalText = text;
      _setControllerText(text);
      _error = null;
    });
  }

  Future<void> _save() async {
    final HostedSourceArchive? archive = _archive;
    final String? path = _selectedPath;
    if (archive == null || path == null || !_dirty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      archive.writeText(path, _controller.text);
      final int revision = await widget.api.updateSource(
        accessToken: widget.accessToken,
        groupId: widget.groupId,
        appId: widget.appId,
        expectedRevision: _revision,
        zipBytes: archive.encode(),
      );
      if (!mounted) return;
      setState(() {
        _revision = revision;
        _originalText = _controller.text;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('編集内容を保存しました')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title}を編集'),
        actions: <Widget>[
          IconButton(
            key: const Key('kobo-source-save-appbar'),
            tooltip: '保存',
            onPressed: _dirty && !_saving ? _save : null,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _archive == null
                ? _ErrorBody(message: _error, onRetry: _load)
                : Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(KoboSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            DropdownButtonFormField<String>(
                              key: const Key('kobo-source-file'),
                              initialValue: _selectedPath,
                              decoration: const InputDecoration(
                                labelText: '編集するファイル',
                              ),
                              items: _textPaths
                                  .map(
                                    (String path) => DropdownMenuItem<String>(
                                      value: path,
                                      child: Text(path),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: _saving ? null : _selectPath,
                            ),
                            if (_error != null) ...<Widget>[
                              const SizedBox(height: KoboSpacing.sm),
                              Text(
                                _error!,
                                style: const TextStyle(color: KoboColors.error),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: KoboSpacing.md,
                          ),
                          child: TextField(
                            key: const Key('kobo-source-editor'),
                            controller: _controller,
                            enabled: !_saving,
                            expands: true,
                            minLines: null,
                            maxLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.multiline,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              height: 1.45,
                            ),
                            decoration: const InputDecoration(
                              alignLabelWithHint: true,
                              labelText: 'コード',
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(KoboSpacing.md),
                        child: FilledButton.icon(
                          key: const Key('kobo-source-save'),
                          onPressed: _dirty && !_saving ? _save : null,
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? '保存中…' : '編集内容を保存'),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoboSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message ?? 'ソースを読み込めませんでした。'),
            const SizedBox(height: KoboSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('もう一度'),
            ),
          ],
        ),
      ),
    );
  }
}
