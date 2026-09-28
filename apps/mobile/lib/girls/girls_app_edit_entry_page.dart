import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../hosted_app_management_api.dart'
    show maxHostedThumbnailBytes, hostedThumbnailContentTypes;
import 'girls_app_management_api.dart';
import 'girls_app_source_editor_page.dart';
import 'girls_code_help.dart';
import 'girls_errors.dart';
import 'girls_scaffold.dart';
import 'girls_source_zip.dart';

const Color _cream = Color(0xFFFFFAF0);
const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF745B9E);
const Color _mint = Color(0xFF9AD9C9);
const Color _pink = Color(0xFFF6DDE8);

class GirlsAppEditEntryPage extends StatefulWidget {
  const GirlsAppEditEntryPage({
    required this.api,
    required this.accessToken,
    required this.groupId,
    required this.appId,
    required this.title,
    required this.expectedRevision,
    this.onSaved,
    this.onMetadataSaved,
    super.key,
  });

  final GirlsAppManagementApi api;
  final String accessToken;
  final String groupId;
  final String appId;
  final String title;
  final int expectedRevision;
  final Future<void> Function(int revision)? onSaved;
  final Future<void> Function()? onMetadataSaved;

  @override
  State<GirlsAppEditEntryPage> createState() => _GirlsAppEditEntryPageState();
}

class _GirlsAppEditEntryPageState extends State<GirlsAppEditEntryPage> {
  late int _currentRevision;
  late String _currentTitle;
  late final TextEditingController _titleController;
  Uint8List? _thumbnailBytes;
  Uint8List? _pendingThumbnailBytes;
  String? _pendingThumbnailContentType;
  bool _thumbnailLoading = false;
  bool _metadataBusy = false;
  String? _metadataMessage;
  bool _copying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentRevision = widget.expectedRevision;
    _currentTitle = widget.title;
    _titleController = TextEditingController(text: widget.title);
    _loadThumbnail();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadThumbnail() async {
    if (_thumbnailLoading) return;
    setState(() {
      _thumbnailLoading = true;
      _metadataMessage = null;
    });
    try {
      final HostedThumbnailDownload? thumbnail = await widget.api.getThumbnail(
        accessToken: widget.accessToken,
        appId: widget.appId,
      );
      if (!mounted) return;
      setState(() => _thumbnailBytes = thumbnail?.bytes);
    } catch (error) {
      if (mounted) setState(() => _metadataMessage = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _thumbnailLoading = false);
    }
  }

  Future<void> _saveTitle() async {
    if (_metadataBusy) return;
    final String rawTitle = _titleController.text;
    if (rawTitle.isEmpty) {
      setState(() => _metadataMessage = 'アプリ名を入力してください。');
      return;
    }
    if (rawTitle != rawTitle.trim()) {
      setState(() => _metadataMessage = 'アプリ名の前後に空白を入れないでください。');
      return;
    }
    if (rawTitle.length > 80) {
      setState(() => _metadataMessage = 'アプリ名は80文字以内にしてください。');
      return;
    }
    if (rawTitle == _currentTitle) {
      setState(() => _metadataMessage = 'アプリ名は変更されていません。');
      return;
    }

    setState(() {
      _metadataBusy = true;
      _metadataMessage = null;
    });
    try {
      final ManagedGirlsApp updated = await widget.api.setTitle(
        accessToken: widget.accessToken,
        appId: widget.appId,
        title: rawTitle,
      );
      if (updated.app.appId != widget.appId || updated.app.title != rawTitle) {
        throw const FormatException('アプリ名の保存結果が一致しません。');
      }
      _currentTitle = rawTitle;
      final Future<void> Function()? onMetadataSaved = widget.onMetadataSaved;
      if (onMetadataSaved != null) await onMetadataSaved();
      if (!mounted) return;
      setState(() => _metadataMessage = 'アプリ名を保存しました ♡');
    } catch (error) {
      if (mounted) setState(() => _metadataMessage = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _metadataBusy = false);
    }
  }

  Future<void> _pickThumbnail() async {
    if (_metadataBusy) return;
    final PlatformFile? file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null || !mounted) return;

    final String extension = file.extension?.toLowerCase() ?? '';
    final String? contentType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    if (contentType == null || !hostedThumbnailContentTypes.contains(contentType)) {
      setState(() => _metadataMessage = 'JPEG・PNG・WebPの画像を選んでください。');
      return;
    }

    final Uint8List bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.isEmpty || bytes.length > maxHostedThumbnailBytes) {
      setState(() => _metadataMessage = 'アイコン画像は1byte以上192KB以下にしてください。');
      return;
    }
    setState(() {
      _pendingThumbnailBytes = bytes;
      _pendingThumbnailContentType = contentType;
      _metadataMessage = '保存前のアイコンです。';
    });
  }

  Future<void> _saveThumbnail() async {
    if (_metadataBusy) return;
    final Uint8List? bytes = _pendingThumbnailBytes;
    final String? contentType = _pendingThumbnailContentType;
    if (bytes == null || contentType == null) {
      setState(() => _metadataMessage = '先にアイコン画像を選んでください。');
      return;
    }

    setState(() {
      _metadataBusy = true;
      _metadataMessage = null;
    });
    try {
      await widget.api.setThumbnail(
        accessToken: widget.accessToken,
        appId: widget.appId,
        bytes: bytes,
        contentType: contentType,
      );
      final Future<void> Function()? onMetadataSaved = widget.onMetadataSaved;
      if (onMetadataSaved != null) await onMetadataSaved();
      if (!mounted) return;
      setState(() {
        _thumbnailBytes = bytes;
        _pendingThumbnailBytes = null;
        _pendingThumbnailContentType = null;
        _metadataMessage = 'アイコンを保存しました ♡';
      });
    } catch (error) {
      if (mounted) setState(() => _metadataMessage = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _metadataBusy = false);
    }
  }

  Future<void> _copyForAi() async {
    if (_copying) return;
    setState(() {
      _copying = true;
      _error = null;
    });
    try {
      final GirlsSourceDownload download = await widget.api.downloadSource(
        accessToken: widget.accessToken,
        groupId: widget.groupId,
        appId: widget.appId,
      );
      if (download.revision != _currentRevision) {
        throw StateError(
          'Source revision changed before AI copy: '
          'expected=$_currentRevision, actual=${download.revision}.',
        );
      }
      final GirlsSourceArchive archive = GirlsSourceArchive.decode(download.bytes);
      final String text = _buildAiClipboardText(
        title: _currentTitle,
        archive: archive,
      );
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AIに貼り付けるコードをコピーしたよ')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _openEditor() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GirlsAppSourceEditorPage(
          api: widget.api,
          accessToken: widget.accessToken,
          groupId: widget.groupId,
          appId: widget.appId,
          title: _currentTitle,
          expectedRevision: _currentRevision,
          onSaved: (int revision) async {
            if (!mounted) return;
            setState(() => _currentRevision = revision);
            final Future<void> Function(int revision)? onSaved = widget.onSaved;
            if (onSaved != null) {
              await onSaved(revision);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool embedded = GirlsScaffoldChromeScope.isEmbedded(context);
    final Color background = embedded ? Colors.transparent : _cream;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        leading: const BackButton(
          key: Key('girls-edit-entry-back'),
        ),
        actions: <Widget>[
          IconButton(
            key: const Key('girls-edit-entry-help'),
            tooltip: '使い方ガイド',
            onPressed: () => showGirlsCodeHelpDialog(context),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              children: <Widget>[
                const Text(
                  'どうやってアレンジする？',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  key: const Key('girls-edit-entry-metadata'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE1C7D2)),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x1A604943),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        'アプリの見た目',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              key: const Key('girls-edit-entry-icon-preview'),
                              width: 88,
                              height: 88,
                              color: const Color(0xFFF6EAF7),
                              child: _thumbnailLoading
                                  ? const Center(
                                      child: SizedBox.square(
                                        dimension: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : (_pendingThumbnailBytes ?? _thumbnailBytes) == null
                                      ? const Icon(
                                          Icons.apps_rounded,
                                          color: _lavender,
                                          size: 38,
                                        )
                                      : Image.memory(
                                          _pendingThumbnailBytes ?? _thumbnailBytes!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, Object error, StackTrace? stack) =>
                                              const Icon(
                                            Icons.broken_image_outlined,
                                            color: Color(0xFFA04455),
                                          ),
                                        ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                OutlinedButton.icon(
                                  key: const Key('girls-edit-entry-pick-icon'),
                                  onPressed: _metadataBusy ? null : _pickThumbnail,
                                  icon: const Icon(Icons.image_outlined),
                                  label: const Text('アイコン画像を選ぶ'),
                                ),
                                const SizedBox(height: 8),
                                FilledButton.tonal(
                                  key: const Key('girls-edit-entry-save-icon'),
                                  onPressed: _metadataBusy || _pendingThumbnailBytes == null
                                      ? null
                                      : _saveThumbnail,
                                  child: const Text('アイコンを保存'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const Key('girls-edit-entry-title'),
                        controller: _titleController,
                        enabled: !_metadataBusy,
                        maxLength: 80,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'アプリ名',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _saveTitle(),
                      ),
                      FilledButton(
                        key: const Key('girls-edit-entry-save-title'),
                        onPressed: _metadataBusy ? null : _saveTitle,
                        style: FilledButton.styleFrom(
                          backgroundColor: _lavender,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('アプリ名を保存'),
                      ),
                      if (_metadataMessage != null) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          _metadataMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF8C7893),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: const Color(0xFFCBB4D8),
                      width: 2,
                    ),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x26745B9E),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: <Widget>[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        color: _pink.withValues(alpha: .9),
                        child: const Text(
                          'AIといっしょにアレンジ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _ink,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                        child: Column(
                          children: <Widget>[
                            const Text(
                              'コードをコピーして、ChatGPTなど\nお手持ちのAIに貼り付けよう',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _ink,
                                fontSize: 16,
                                height: 1.35,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _BigCopyButton(
                              busy: _copying,
                              onTap: _copyForAi,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const _IdeaPill(
                  icon: Icons.palette_rounded,
                  label: '背景をピンクにしたい',
                  color: Color(0xFFF4D2BF),
                ),
                const SizedBox(height: 10),
                const _IdeaPill(
                  icon: Icons.star_rounded,
                  label: 'ボタンをもっとかわいくしたい',
                  color: Color(0xFFFFE3A8),
                ),
                const SizedBox(height: 10),
                const _IdeaPill(
                  icon: Icons.pets_rounded,
                  label: '犬の画像を追加したい',
                  color: Color(0xFFF5D6CE),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE8EC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFA04455),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  key: const Key('girls-edit-entry-open-editor'),
                  onPressed: _copying ? null : _openEditor,
                  style: FilledButton.styleFrom(
                    backgroundColor: _mint,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(58),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 3,
                  ),
                  child: const Text(
                    'コードを編集！',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'AIが作ったコードを貼り付けるのもここだよ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF8C7893),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _buildAiClipboardText({
  required String title,
  required GirlsSourceArchive archive,
}) {
  final List<String> textPaths = archive.textPaths;
  if (textPaths.isEmpty) {
    throw const FormatException('AIに渡せるUTF-8テキストファイルがありません。');
  }

  final StringBuffer buffer = StringBuffer()
    ..writeln('「みんアプGirls」で動くミニアプリ')
    ..writeln('アプリ名: $title')
    ..writeln('技術仕様: $girlsTechnicalGuideUrl')
    ..writeln()
    ..writeln('改造したい！')
    ..writeln('ファイル一覧:');

  for (final String path in archive.paths) {
    buffer.writeln('- $path');
  }

  for (final String path in textPaths) {
    buffer
      ..writeln()
      ..writeln('===== $path =====')
      ..writeln(archive.readText(path));
  }

  return buffer.toString();
}

class _BigCopyButton extends StatelessWidget {
  const _BigCopyButton({
    required this.busy,
    required this.onTap,
  });

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[
            Color(0xFFCBB8EB),
            Color(0xFF9B79C5),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x3D745B9E),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('girls-edit-entry-copy'),
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (busy)
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(
                    Icons.content_paste_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                const SizedBox(width: 10),
                Text(
                  busy ? 'コピー中…' : 'コードをコピー',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IdeaPill extends StatelessWidget {
  const _IdeaPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 18, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EE).withValues(alpha: .93),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE1C7C9)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A604943),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 22,
            backgroundColor: color,
            child: Icon(icon, color: _lavender),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _ink,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
