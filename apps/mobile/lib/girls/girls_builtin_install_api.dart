import 'dart:convert';

import 'package:http/http.dart' as http;

import '../hosted_authoring_projects_api.dart';
import 'api.dart';
import 'hosted_girls_api.dart';

const String novelEditorBuiltinId = 'novel-editor';
const String novelPlayerBuiltinId = 'novel-starter';
const String _novelContentFormat = 'minapp/novel@1';
const String _novelSampleTitle = 'ひみつの放課後';

final RegExp _hostedIdPattern = RegExp(r'^[0-9a-f]{32}$');

class GirlsBuiltinInstallApi {
  GirlsBuiltinInstallApi({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  Future<HostedGroupApp> installNovelEditor({
    required String accessToken,
    required String groupId,
  }) async {
    await ensureNovelPlayer(
      accessToken: accessToken,
      groupId: groupId,
    );
    final HostedGroupApp editor = await _installBuiltin(
      accessToken: accessToken,
      groupId: groupId,
      builtinId: novelEditorBuiltinId,
      label: 'Novel Editor',
    );
    await _ensureNovelSampleProject(
      accessToken: accessToken,
      groupId: groupId,
    );
    return editor;
  }

  Future<HostedGroupApp> ensureNovelEditor({
    required String accessToken,
    required String groupId,
  }) async {
    await ensureNovelPlayer(
      accessToken: accessToken,
      groupId: groupId,
    );
    final List<HostedGroupApp> apps = await _listGroupApps(
      accessToken: accessToken,
      groupId: groupId,
    );
    final List<HostedGroupApp> editors = apps
        .where(
          (HostedGroupApp app) =>
              app.sourceKind == 'builtin' &&
              app.builtinId == novelEditorBuiltinId,
        )
        .toList(growable: false);
    if (editors.length > 1) {
      throw const FormatException(
        'Group app list contains duplicate Novel Editor installations.',
      );
    }
    final HostedGroupApp editor = editors.length == 1
        ? editors.single
        : await _installBuiltin(
            accessToken: accessToken,
            groupId: groupId,
            builtinId: novelEditorBuiltinId,
            label: 'Novel Editor',
          );
    await _ensureNovelSampleProject(
      accessToken: accessToken,
      groupId: groupId,
    );
    return editor;
  }

  Future<HostedGroupApp> ensureNovelPlayer({
    required String accessToken,
    required String groupId,
  }) async {
    final List<HostedGroupApp> apps = await _listGroupApps(
      accessToken: accessToken,
      groupId: groupId,
    );
    final List<HostedGroupApp> players = apps
        .where(
          (HostedGroupApp app) =>
              app.sourceKind == 'builtin' &&
              app.builtinId == novelPlayerBuiltinId,
        )
        .toList(growable: false);
    if (players.length > 1) {
      throw const FormatException(
        'Group app list contains duplicate Novel Player installations.',
      );
    }
    if (players.length == 1) return players.single;
    return installNovelPlayer(
      accessToken: accessToken,
      groupId: groupId,
    );
  }

  Future<HostedGroupApp> installNovelPlayer({
    required String accessToken,
    required String groupId,
  }) {
    return _installBuiltin(
      accessToken: accessToken,
      groupId: groupId,
      builtinId: novelPlayerBuiltinId,
      label: 'Novel Player',
    );
  }

  Future<void> _ensureNovelSampleProject({
    required String accessToken,
    required String groupId,
  }) async {
    final HostedAuthoringProjectsApi projectsApi = HostedAuthoringProjectsApi(
      baseUri: _baseUri,
      client: _client,
    );
    final List<HostedAuthoringProjectSummary> projects =
        await projectsApi.listProjects(
      accessToken: accessToken,
      groupId: groupId,
      contentFormat: _novelContentFormat,
    );

    for (final HostedAuthoringProjectSummary summary in projects) {
      final HostedAuthoringProject project = await projectsApi.loadProject(
        accessToken: accessToken,
        contentId: summary.contentId,
      );
      if (project.summary.groupId != groupId ||
          project.summary.contentFormat != _novelContentFormat) {
        throw const FormatException(
          'Novel sample lookup changed the requested project scope.',
        );
      }
      if (project.document['title'] == _novelSampleTitle) {
        await _hydrateNovelSampleProject(
          accessToken: accessToken,
          groupId: groupId,
          contentId: project.summary.contentId,
        );
        return;
      }
    }

    final HostedAuthoringProjectSummary created = await projectsApi.createProject(
      accessToken: accessToken,
      groupId: groupId,
      contentFormat: _novelContentFormat,
      document: _novelSampleDocument(),
    );
    await _hydrateNovelSampleProject(
      accessToken: accessToken,
      groupId: groupId,
      contentId: created.contentId,
    );
  }

  Future<void> _hydrateNovelSampleProject({
    required String accessToken,
    required String groupId,
    required String contentId,
  }) async {
    _validateRequestScope(accessToken: accessToken, groupId: groupId);
    if (!_hostedIdPattern.hasMatch(contentId)) {
      throw ArgumentError.value(
        contentId,
        'contentId',
        'must be a 32-character lowercase hexadecimal ID',
      );
    }
    final Uri uri = _baseUri.resolve(
      '/hosted/authoring/projects/$contentId/samples/novel',
    );
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );
    final Map<String, Object?> payload = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response.statusCode, payload);
    }
    final HostedAuthoringProjectSummary hydrated =
        HostedAuthoringProjectSummary.fromJson(payload);
    if (hydrated.contentId != contentId ||
        hydrated.groupId != groupId ||
        hydrated.contentFormat != _novelContentFormat) {
      throw const FormatException(
        'Novel sample hydration changed the requested project scope.',
      );
    }
  }

  Map<String, Object?> _novelSampleDocument() {
    return <String, Object?>{
      'content_format': _novelContentFormat,
      'schema_version': 1,
      'content_revision': 1,
      'title': _novelSampleTitle,
      'start_scene': 'start',
      'assets': <String, Object?>{},
      'characters': <String, Object?>{},
      'scenes': <String, Object?>{
        'start': <String, Object?>{
          'id': 'start',
          'events': <Object?>[
            <String, Object?>{
              'id': 'evt-start-line',
              'type': 'dialogue',
              'text': 'なあ。\n今日、ちょっとだけ寄り道していかない？',
            },
            <String, Object?>{
              'id': 'evt-start-choice',
              'type': 'choice',
              'options': <Object?>[
                <String, Object?>{
                  'id': 'ask',
                  'label': '「どうしたの？」',
                  'goto': 'rooftop',
                },
                <String, Object?>{
                  'id': 'leave',
                  'label': '「今日は帰るね」',
                  'goto': 'leave',
                },
              ],
            },
          ],
        },
        'rooftop': <String, Object?>{
          'id': 'rooftop',
          'events': <Object?>[
            <String, Object?>{
              'id': 'evt-rooftop-line',
              'type': 'dialogue',
              'text': '屋上の空、すごくきれいだったから。\nきみに見せたかったんだ。',
            },
            <String, Object?>{
              'id': 'evt-rooftop-choice',
              'type': 'choice',
              'options': <Object?>[
                <String, Object?>{
                  'id': 'sit',
                  'label': 'となりに座る',
                  'goto': 'together',
                },
                <String, Object?>{
                  'id': 'photo',
                  'label': '空の写真を撮る',
                  'goto': 'photo',
                },
              ],
            },
          ],
        },
        'together': <String, Object?>{
          'id': 'together',
          'events': <Object?>[
            <String, Object?>{
              'id': 'evt-together-line',
              'type': 'dialogue',
              'text': '……よかった。\nこの場所、ふたりだけの秘密にしよう。',
            },
            <String, Object?>{
              'id': 'evt-together-end',
              'type': 'end',
              'label': 'END - ふたりの秘密',
            },
          ],
        },
        'photo': <String, Object?>{
          'id': 'photo',
          'events': <Object?>[
            <String, Object?>{
              'id': 'evt-photo-line',
              'type': 'dialogue',
              'text': 'じゃあ同じ空を持って帰れるね。\n明日も、ここで会おう。',
            },
            <String, Object?>{
              'id': 'evt-photo-end',
              'type': 'end',
              'label': 'END - 同じ空',
            },
          ],
        },
        'leave': <String, Object?>{
          'id': 'leave',
          'events': <Object?>[
            <String, Object?>{
              'id': 'evt-leave-line',
              'type': 'dialogue',
              'text': 'そっか。じゃあ、また明日。\n次はちゃんと誘うから。',
            },
            <String, Object?>{
              'id': 'evt-leave-end',
              'type': 'end',
              'label': 'END - また明日',
            },
          ],
        },
      },
    };
  }

  Future<List<HostedGroupApp>> _listGroupApps({
    required String accessToken,
    required String groupId,
  }) async {
    _validateRequestScope(accessToken: accessToken, groupId: groupId);
    final Uri uri = _baseUri.resolve('/hosted/groups/$groupId/apps');
    final http.Response response = await _client.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );
    final Map<String, Object?> payload = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response.statusCode, payload);
    }
    if (payload.length != 1 || !payload.containsKey('apps')) {
      throw const FormatException(
        'Group app list response fields are invalid.',
      );
    }
    final Object? rawApps = payload['apps'];
    if (rawApps is! List<Object?>) {
      throw const FormatException(
        'Group app list response has an invalid apps field.',
      );
    }
    final List<HostedGroupApp> apps = <HostedGroupApp>[];
    for (final Object? rawApp in rawApps) {
      if (rawApp is! Map<String, Object?>) {
        throw const FormatException(
          'Group app list response contains an invalid app entry.',
        );
      }
      final HostedGroupApp app = HostedGroupApp.fromJson(rawApp);
      if (app.groupId != groupId) {
        throw const FormatException(
          'Group app list response changed the requested group scope.',
        );
      }
      apps.add(app);
    }
    return apps;
  }

  Future<HostedGroupApp> _installBuiltin({
    required String accessToken,
    required String groupId,
    required String builtinId,
    required String label,
  }) async {
    _validateRequestScope(accessToken: accessToken, groupId: groupId);

    final Uri uri = _baseUri.resolve('/hosted/groups/$groupId/apps/install');
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{'builtin_id': builtinId}),
    );

    final Map<String, Object?> payload = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response.statusCode, payload);
    }

    final HostedGroupApp app = HostedGroupApp.fromJson(payload);
    if (app.groupId != groupId ||
        app.sourceKind != 'builtin' ||
        app.builtinId != builtinId) {
      throw FormatException(
        '$label install response changed the requested app scope.',
      );
    }
    return app;
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  static void _validateRequestScope({
    required String accessToken,
    required String groupId,
  }) {
    if (accessToken.isEmpty) {
      throw ArgumentError.value(accessToken, 'accessToken', 'must not be empty');
    }
    if (!_hostedIdPattern.hasMatch(groupId)) {
      throw ArgumentError.value(
        groupId,
        'groupId',
        'must be a 32-character lowercase hexadecimal ID',
      );
    }
  }

  static Map<String, Object?> _decodeJsonObject(http.Response response) {
    final String? contentType = response.headers['content-type'];
    if (contentType == null ||
        !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException(
        'Builtin install API returned a non-JSON response (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Builtin install API returned an unexpected JSON payload.',
      );
    }
    return decoded;
  }

  static ApiException _apiException(
    int statusCode,
    Map<String, Object?> payload,
  ) {
    final Set<String> actual = payload.keys.toSet();
    if (actual.length != 2 ||
        !actual.contains('error') ||
        !actual.contains('message')) {
      throw const FormatException(
        'Builtin install API error response fields are invalid.',
      );
    }
    final Object? rawCode = payload['error'];
    final Object? rawMessage = payload['message'];
    if (rawCode is! String ||
        rawCode.isEmpty ||
        rawMessage is! String ||
        rawMessage.isEmpty) {
      throw const FormatException(
        'Builtin install API error response is missing error or message.',
      );
    }
    return ApiException(
      statusCode: statusCode,
      code: rawCode,
      message: rawMessage,
    );
  }

  static Uri _validateBaseUri(Uri uri) {
    if (uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'must be an HTTPS origin without credentials, path, query, or fragment',
      );
    }
    return uri;
  }
}
