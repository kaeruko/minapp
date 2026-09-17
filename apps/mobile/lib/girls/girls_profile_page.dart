import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'girls_app_core.dart' as core;
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF8062A7);
const Color _pink = Color(0xFFE79AAF);
const Color _cream = Color(0xFFFFFAF0);
const int _maxDisplayNameLength = 40;

class GirlsProfilePage extends StatefulWidget {
  const GirlsProfilePage({
    required this.api,
    required this.session,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;

  @override
  State<GirlsProfilePage> createState() => _GirlsProfilePageState();
}

class _GirlsProfilePageState extends State<GirlsProfilePage> {
  final TextEditingController _displayNameController = TextEditingController();
  final FocusNode _displayNameFocusNode = FocusNode();

  String? _loginId;
  String? _savedDisplayName;
  String? _error;
  String? _message;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _displayNameFocusNode.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _editDisplayName() {
    if (_saving) return;
    _displayNameFocusNode.requestFocus();
    final int length = _displayNameController.text.length;
    _displayNameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: length,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });
    try {
      final _DisplayNameProfile profile = await _request(method: 'GET');
      if (!mounted) return;
      setState(() {
        _loginId = profile.loginId;
        _savedDisplayName = profile.displayName;
        _displayNameController.text = profile.displayName ?? '';
      });
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final String value = _displayNameController.text;
    if (value.isEmpty) {
      setState(() => _error = '表示名を入力してね。');
      return;
    }
    if (value.length > _maxDisplayNameLength) {
      setState(() => _error = '表示名は$_maxDisplayNameLength文字以内にしてね。');
      return;
    }
    if (value != value.trim()) {
      setState(() => _error = '表示名の最初や最後に空白は入れられないよ。');
      return;
    }
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      setState(() => _error = '表示名に使えない文字が含まれています。');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      final _DisplayNameProfile profile = await _request(
        method: 'PATCH',
        displayName: value,
      );
      if (!mounted) return;
      setState(() {
        _loginId = profile.loginId;
        _savedDisplayName = profile.displayName;
        _displayNameController.text = profile.displayName ?? '';
        _message = '表示名を保存したよ';
      });
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_DisplayNameProfile> _request({
    required String method,
    String? displayName,
  }) async {
    if (method != 'GET' && method != 'PATCH') {
      throw ArgumentError.value(method, 'method', 'Unsupported method.');
    }
    if (method == 'GET' && displayName != null) {
      throw ArgumentError('GET display-name request must not contain a body.');
    }
    if (method == 'PATCH' && displayName == null) {
      throw ArgumentError('PATCH display-name request requires a display name.');
    }

    final Uri uri = widget.api.baseUri.resolve('/hosted/me/display-name');
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer ${widget.session.accessToken}',
    };
    final response = switch (method) {
      'GET' => await widget.api.httpClient.get(uri, headers: headers),
      'PATCH' => await widget.api.httpClient.patch(
          uri,
          headers: <String, String>{
            ...headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, Object?>{'display_name': displayName}),
        ),
      _ => throw StateError('Unreachable display-name method.'),
    };

    final String? contentType = response.headers['content-type'];
    if (contentType == null ||
        !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException(
        'Display-name API returned a non-JSON response (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Display-name API returned an unexpected JSON payload.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        code: decoded['error'] is String ? decoded['error']! as String : 'api_error',
        message: decoded['message'] is String
            ? decoded['message']! as String
            : 'Display-name API request failed with HTTP ${response.statusCode}.',
      );
    }
    return _DisplayNameProfile.fromJson(decoded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF4F7),
        foregroundColor: _ink,
        centerTitle: true,
        title: const Text(
          'プロフィール',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
              children: <Widget>[
                const CircleAvatar(
                  radius: 42,
                  backgroundColor: Color(0xFFF2DFEF),
                  child: Icon(
                    Icons.person_rounded,
                    size: 48,
                    color: _lavender,
                  ),
                ),
                const SizedBox(height: 18),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else ...<Widget>[
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .9),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE8D8E7)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                '表示名',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Icon(Icons.edit_rounded, color: _lavender, size: 20),
                          ],
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          '友達や作品から見える名前です。ログイン用のユーザー名とは別に設定できます。',
                          style: TextStyle(
                            color: Color(0xFF8C7893),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const Key('girls-profile-display-name'),
                          controller: _displayNameController,
                          focusNode: _displayNameFocusNode,
                          enabled: !_saving,
                          maxLength: _maxDisplayNameLength,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: '名前',
                            hintText: '例：ねんね',
                            prefixIcon: const Icon(Icons.badge_rounded),
                            suffixIcon: IconButton(
                              key: const Key('girls-profile-edit-display-name'),
                              tooltip: '表示名を編集',
                              onPressed: _saving ? null : _editDisplayName,
                              icon: const Icon(
                                Icons.edit_rounded,
                                color: _lavender,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          key: const Key('girls-profile-save'),
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: _lavender,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.favorite_rounded),
                          label: Text(_saving ? '保存中…' : '保存する'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7FA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.key_rounded, color: _pink),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'ログイン用ユーザー名',
                                style: TextStyle(
                                  color: Color(0xFF8C7893),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _loginId ?? '—',
                                style: const TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_savedDisplayName == null) ...<Widget>[
                    const SizedBox(height: 10),
                    const Text(
                      '表示名はまだ未設定です。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF8C7893), fontSize: 12),
                    ),
                  ],
                ],
                if (_message != null) ...<Widget>[
                  const SizedBox(height: 14),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _lavender,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DisplayNameProfile {
  const _DisplayNameProfile({
    required this.userId,
    required this.loginId,
    required this.role,
    required this.displayName,
  });

  final String userId;
  final String loginId;
  final String role;
  final String? displayName;

  factory _DisplayNameProfile.fromJson(Map<String, Object?> json) {
    const Set<String> expected = <String>{
      'user_id',
      'login_id',
      'role',
      'display_name',
    };
    if (json.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(json.keys.toSet()).isNotEmpty) {
      throw const FormatException(
        'Display-name profile returned unexpected fields.',
      );
    }
    final Object? userId = json['user_id'];
    final Object? loginId = json['login_id'];
    final Object? role = json['role'];
    final Object? displayName = json['display_name'];
    if (userId is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(userId)) {
      throw const FormatException('Display-name profile has invalid user_id.');
    }
    if (loginId is! String || loginId.isEmpty) {
      throw const FormatException('Display-name profile has invalid login_id.');
    }
    if (role != 'user') {
      throw const FormatException('Display-name profile has invalid role.');
    }
    if (displayName != null &&
        (displayName is! String ||
            displayName.isEmpty ||
            displayName.length > _maxDisplayNameLength ||
            displayName != displayName.trim() ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(displayName))) {
      throw const FormatException('Display-name profile has invalid display_name.');
    }
    return _DisplayNameProfile(
      userId: userId,
      loginId: loginId,
      role: role as String,
      displayName: displayName as String?,
    );
  }
}
