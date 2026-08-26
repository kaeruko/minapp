import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

const String minAppSupportEmail = 'mail@cloxs.jp';

abstract interface class CreatorSafetyStore {
  Future<Set<String>> loadHiddenCreatorUserIds();

  Future<void> hideCreator(String creatorUserId);

  Future<void> unhideCreator(String creatorUserId);
}

class MemoryCreatorSafetyStore implements CreatorSafetyStore {
  MemoryCreatorSafetyStore([Set<String>? initial])
      : _hiddenCreatorUserIds = <String>{...?initial};

  final Set<String> _hiddenCreatorUserIds;

  @override
  Future<Set<String>> loadHiddenCreatorUserIds() async =>
      Set<String>.unmodifiable(_hiddenCreatorUserIds);

  @override
  Future<void> hideCreator(String creatorUserId) async {
    _validateCreatorUserId(creatorUserId);
    _hiddenCreatorUserIds.add(creatorUserId);
  }

  @override
  Future<void> unhideCreator(String creatorUserId) async {
    _validateCreatorUserId(creatorUserId);
    _hiddenCreatorUserIds.remove(creatorUserId);
  }
}

class SharedPreferencesCreatorSafetyStore implements CreatorSafetyStore {
  static const String _key = 'ugc_hidden_creator_user_ids_v1';

  @override
  Future<Set<String>> loadHiddenCreatorUserIds() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<String> values = preferences.getStringList(_key) ?? <String>[];
    for (final String value in values) {
      _validateCreatorUserId(value);
    }
    return values.toSet();
  }

  @override
  Future<void> hideCreator(String creatorUserId) async {
    _validateCreatorUserId(creatorUserId);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final Set<String> values = (preferences.getStringList(_key) ?? <String>[]).toSet();
    values.add(creatorUserId);
    final bool saved = await preferences.setStringList(
      _key,
      values.toList(growable: false)..sort(),
    );
    if (!saved) {
      throw StateError('Could not persist the hidden creator list.');
    }
  }

  @override
  Future<void> unhideCreator(String creatorUserId) async {
    _validateCreatorUserId(creatorUserId);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final Set<String> values = (preferences.getStringList(_key) ?? <String>[]).toSet();
    values.remove(creatorUserId);
    final bool saved = await preferences.setStringList(
      _key,
      values.toList(growable: false)..sort(),
    );
    if (!saved) {
      throw StateError('Could not persist the hidden creator list.');
    }
  }
}

Future<void> openAppReportEmail({
  required PublishedApp app,
  required String reason,
}) async {
  if (reason.isEmpty || reason != reason.trim() || reason.length > 80) {
    throw ArgumentError.value(reason, 'reason', 'must be 1-80 trimmed characters');
  }
  final Uri uri = Uri(
    scheme: 'mailto',
    path: minAppSupportEmail,
    queryParameters: <String, String>{
      'subject': 'みんアプ 不適切な作品の報告',
      'body': <String>[
        '報告理由: $reason',
        '作品名: ${app.title}',
        '作成者: ${app.ownerLoginId}',
        'owner_user_id: ${app.ownerUserId}',
        'app_id: ${app.appId}',
        'version_id: ${app.versionId}',
        'group_id: ${app.groupId}',
        '',
        '必要に応じて詳しい状況をご記入のうえ送信してください。',
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

void _validateCreatorUserId(String value) {
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'creatorUserId',
      'must be a 32-character lowercase hexadecimal user id',
    );
  }
}
