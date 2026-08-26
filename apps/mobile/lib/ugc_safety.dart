import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

const String minAppSupportEmail = 'mail@cloxs.jp';

abstract interface class CreatorSafetyStore {
  Future<Set<String>> loadHiddenCreators();

  Future<void> hideCreator(String creatorLoginId);

  Future<void> unhideCreator(String creatorLoginId);
}

class MemoryCreatorSafetyStore implements CreatorSafetyStore {
  MemoryCreatorSafetyStore([Set<String>? initial])
      : _hiddenCreators = <String>{...?initial};

  final Set<String> _hiddenCreators;

  @override
  Future<Set<String>> loadHiddenCreators() async =>
      Set<String>.unmodifiable(_hiddenCreators);

  @override
  Future<void> hideCreator(String creatorLoginId) async {
    _validateCreatorLoginId(creatorLoginId);
    _hiddenCreators.add(creatorLoginId);
  }

  @override
  Future<void> unhideCreator(String creatorLoginId) async {
    _validateCreatorLoginId(creatorLoginId);
    _hiddenCreators.remove(creatorLoginId);
  }
}

class SharedPreferencesCreatorSafetyStore implements CreatorSafetyStore {
  static const String _key = 'ugc_hidden_creators_v1';

  @override
  Future<Set<String>> loadHiddenCreators() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<String> values = preferences.getStringList(_key) ?? <String>[];
    for (final String value in values) {
      _validateCreatorLoginId(value);
    }
    return values.toSet();
  }

  @override
  Future<void> hideCreator(String creatorLoginId) async {
    _validateCreatorLoginId(creatorLoginId);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final Set<String> values = (preferences.getStringList(_key) ?? <String>[]).toSet();
    values.add(creatorLoginId);
    final bool saved = await preferences.setStringList(
      _key,
      values.toList(growable: false)..sort(),
    );
    if (!saved) {
      throw StateError('Could not persist the hidden creator list.');
    }
  }

  @override
  Future<void> unhideCreator(String creatorLoginId) async {
    _validateCreatorLoginId(creatorLoginId);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final Set<String> values = (preferences.getStringList(_key) ?? <String>[]).toSet();
    values.remove(creatorLoginId);
    final bool saved = await preferences.setStringList(
      _key,
      values.toList(growable: false)..sort(),
    );
    if (!saved) {
      throw StateError('Could not persist the hidden creator list.');
    }
  }
}

Future<void> openAppReportEmail(PublishedApp app) async {
  final Uri uri = Uri(
    scheme: 'mailto',
    path: minAppSupportEmail,
    queryParameters: <String, String>{
      'subject': 'みんアプ 不適切な作品の報告',
      'body': <String>[
        '作品名: ${app.title}',
        '作成者: ${app.ownerLoginId}',
        'app_id: ${app.appId}',
        'version_id: ${app.versionId}',
        'group_id: ${app.groupId}',
        '',
        '報告理由や状況をご記入のうえ送信してください。',
      ].join('\n'),
    },
  );
  final bool launched = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
  if (!launched) {
    throw StateError('Could not open a mail client for $minAppSupportEmail.');
  }
}

void _validateCreatorLoginId(String value) {
  if (value.isEmpty || value != value.trim()) {
    throw ArgumentError.value(
      value,
      'creatorLoginId',
      'must be a non-empty string without surrounding whitespace',
    );
  }
  if (value.length > 80) {
    throw ArgumentError.value(
      value,
      'creatorLoginId',
      'must be at most 80 characters',
    );
  }
  if (value.runes.any((int rune) => rune < 0x20 || rune == 0x7f)) {
    throw ArgumentError.value(
      value,
      'creatorLoginId',
      'must not contain control characters',
    );
  }
}
