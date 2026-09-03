import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'hosted_girls_api.dart';
import 'hosted_girls_upload_api.dart';

class GirlsZipUploadPage extends StatefulWidget {
  const GirlsZipUploadPage({
    required this.api,
    required this.session,
    required this.ownerGroups,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final List<HostedGroup> ownerGroups;

  @override
  State<GirlsZipUploadPage> createState() => _GirlsZipUploadPageState();
}

class _GirlsZipUploadPageState extends State<GirlsZipUploadPage> {
  final TextEditingController _title = TextEditingController();
  late final HostedGirlsUploadApi _uploadApi;
  late String _groupId;
  Uint8List? _zipBytes;
  String? _zipName;
  int? _zipSize;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.ownerGroups.isEmpty) {
      throw ArgumentError('GirlsZipUploadPage requires at least one owner group.');
    }
    _groupId = widget.ownerGroups.first.groupId;
    _uploadApi = HostedGirlsUploadApi(baseUri: widget.api.baseUri);
  }

  @override
  void dispose() {
    _title.dispose();
    _uploadApi.close();
    super.dispose();
  }

  Future<void> _pickZip() async {
    final PlatformFile? file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
    );
    if (file == null || !mounted) return;
    if (file.extension?.toLowerCase() != 'zip') {
      setState(() => _error = '拡張子 .zip のファイルを選んでください。');
      return;
    }

    late final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '選択したZIPのデータを読み込めませんでした: $error';
      });
      return;
    }
    if (!mounted) return;
    if (bytes.isEmpty) {
      setState(() => _error = '空のZIPはアップロードできません。');
      return;
    }
    if (bytes.length > maxGirlsZipUploadBytes) {
      setState(() {
        _error = 'ZIPは2MB以下にしてください。現在は ${_formatBytes(bytes.length)} です。';
      });
      return;
    }
    setState(() {
      _zipBytes = bytes;
      _zipName = file.name;
      _zipSize = bytes.length;
      _error = null;
    });
  }

  Future<void> _upload() async {
    final String title = _title.text.trim();
    final Uint8List? zipBytes = _zipBytes;
    if (title.isEmpty) {
      setState(() => _error = 'アプリ名を入力してください。');
      return;
    }
    if (title.length > 80) {
      setState(() => _error = 'アプリ名は80文字以下にしてください。');
      return;
    }
    if (zipBytes == null) {
      setState(() => _error = 'アップロードするZIPを選んでください。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    HostedGroupApp? created;
    try {
      created = await _uploadApi.createFromZip(
        accessToken: widget.session.accessToken,
        groupId: _groupId,
        title: title,
        zipBytes: zipBytes,
      );
      await _uploadApi.publish(
        accessToken: widget.session.accessToken,
        groupId: _groupId,
        appId: created.appId,
        revision: 1,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('🎀 アプリを追加したよ'),
          content: Text('「$title」をアップロードして公開しました。'),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final String prefix = created == null
          ? ''
          : 'アプリ自体は下書きとして作成されました（app_id=${created.appId}）が、公開に失敗しました。\n';
      setState(() => _error = '$prefix${_messageFor(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF9EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFDF9EE),
        title: const Text('ZIPからアプリを追加'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'index.html がZIPの直下にある、みんアプ用のZIPを選んでね。アップロード後、そのまま公開します。',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 22),
              DropdownButtonFormField<String>(
                key: const Key('girls-zip-group'),
                initialValue: _groupId,
                decoration: const InputDecoration(labelText: '追加するグループ'),
                items: widget.ownerGroups
                    .map(
                      (HostedGroup group) => DropdownMenuItem<String>(
                        value: group.groupId,
                        child: Text(group.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _busy
                    ? null
                    : (String? value) {
                        if (value != null) setState(() => _groupId = value);
                      },
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('girls-zip-title'),
                controller: _title,
                enabled: !_busy,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'アプリ名',
                  hintText: '例：放課後おえかき帳',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('girls-pick-zip'),
                onPressed: _busy ? null : _pickZip,
                icon: const Icon(Icons.folder_zip_rounded),
                label: Text(_zipName == null ? 'ZIPを選ぶ' : 'ZIPを選び直す'),
              ),
              if (_zipName != null && _zipSize != null) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.folder_zip_rounded, color: Color(0xFF745B9E)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$_zipName\n${_formatBytes(_zipSize!)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFECEF),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFFFC5CE)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFA04455),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                key: const Key('girls-upload-zip'),
                onPressed: _busy ? null : _upload,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(_busy ? 'アップロード中…' : 'アップロードして公開'),
              ),
              const SizedBox(height: 12),
              const Text(
                'ZIP上限: 2MB。サーバー側でもZIP構造とファイルパスを検証します。検証に失敗したZIPを別形式として扱うことはありません。',
                style: TextStyle(fontSize: 12, color: Color(0xFF8C7893), height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String _messageFor(Object error) {
  if (error is ApiException) return error.message;
  if (error is ArgumentError || error is FormatException) {
    return 'ZIPまたは入力データを確認できませんでした: $error';
  }
  return 'ZIPアップロードに失敗しました: $error';
}
