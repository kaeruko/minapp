import 'girls_authoring_contract_api.dart';

class GirlsAuthoringResolver {
  const GirlsAuthoringResolver._();

  static List<GirlsAuthoringAppContract> editorsFor(
    Iterable<GirlsAuthoringAppContract> apps,
    String contentFormat,
  ) {
    _validateContentFormat(contentFormat);
    return List<GirlsAuthoringAppContract>.unmodifiable(
      apps.where(
        (GirlsAuthoringAppContract app) => app.editsFormat(contentFormat),
      ),
    );
  }

  static List<GirlsAuthoringAppContract> playersFor(
    Iterable<GirlsAuthoringAppContract> apps,
    String contentFormat,
  ) {
    _validateContentFormat(contentFormat);
    return List<GirlsAuthoringAppContract>.unmodifiable(
      apps.where(
        (GirlsAuthoringAppContract app) => app.acceptsFormat(contentFormat),
      ),
    );
  }

  static GirlsAuthoringAppContract requireEditor({
    required Iterable<GirlsAuthoringAppContract> apps,
    required String appId,
    required String contentFormat,
  }) {
    _validateAppId(appId);
    _validateContentFormat(contentFormat);
    final List<GirlsAuthoringAppContract> matching = apps
        .where((GirlsAuthoringAppContract app) => app.appId == appId)
        .toList(growable: false);
    if (matching.length != 1) {
      throw StateError(
        'Selected Authoring Editor app must appear exactly once in the group contract list.',
      );
    }
    final GirlsAuthoringAppContract editor = matching.single;
    if (!editor.editsFormat(contentFormat)) {
      throw StateError(
        'Selected Authoring Editor does not declare support for $contentFormat.',
      );
    }
    return editor;
  }
}

final RegExp _contentFormatPattern = RegExp(
  r'^[a-z0-9][a-z0-9._-]{0,63}/[a-z0-9][a-z0-9._-]{0,63}@[1-9][0-9]{0,5}$',
);
final RegExp _appIdPattern = RegExp(r'^[0-9a-f]{32}$');

void _validateContentFormat(String contentFormat) {
  if (!_contentFormatPattern.hasMatch(contentFormat)) {
    throw ArgumentError.value(
      contentFormat,
      'contentFormat',
      'must be a namespaced versioned content format',
    );
  }
}

void _validateAppId(String appId) {
  if (!_appIdPattern.hasMatch(appId)) {
    throw ArgumentError.value(
      appId,
      'appId',
      'must be a 32-character lowercase hexadecimal ID',
    );
  }
}
