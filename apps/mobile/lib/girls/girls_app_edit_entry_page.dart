import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

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
    super.key,
  });

  final GirlsAppManagementApi api;
  final String accessToken;
  final String groupId;
  final String appId;
  final String title;
  final int expectedRevision;
  final Future<void> Function(int revision)? onSaved;

  @override
  State<GirlsAppEditEntryPage> createState() => _GirlsAppEditEntryPageState();
}

class _GirlsAppEditEntryPageState extends State<GirlsAppEditEntryPage> {
  late int _currentRevision;
  bool _copying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentRevision = widget.expectedRevision;
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
        title: widget.title,
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
          title: widget.title,
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
    ..writeln('これは「みんアプGirls」で動くミニアプリです。')
    ..writeln('アプリ名: $title')
    ..writeln('技術仕様: $girlsTechnicalGuideUrl')
    ..writeln()
    ..writeln('このアプリの現在のコードを貼ります。')
    ..writeln('みんアプGirlsで動く形を保ちながら、このあと私が伝えるアレンジ内容について相談に乗ってください。')
    ..writeln('変更後は、必要なファイルごとに完成したコードを出してください。')
    ..writeln()
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
