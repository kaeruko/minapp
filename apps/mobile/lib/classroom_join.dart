import 'endpoint_validation.dart';

const String classroomCodeAlphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
const int classroomCodeLength = 12;

class InvalidClassroomJoinInput implements Exception {
  const InvalidClassroomJoinInput(this.message);

  final String message;

  @override
  String toString() => message;
}

String normalizeClassroomJoinInput(
  String rawInput, {
  Uri? officialJoinBaseUri,
}) {
  final String input = rawInput.trim();
  if (input.isEmpty) {
    throw const InvalidClassroomJoinInput('教室コードを入力してください。');
  }

  final Uri? parsedUri = Uri.tryParse(input);
  if (parsedUri != null && parsedUri.hasScheme) {
    final Uri? configuredJoinBase = officialJoinBaseUri;
    if (configuredJoinBase == null) {
      throw const InvalidClassroomJoinInput(
        'このアプリでは教室リンクを受け付けていません。教室コードを入力してください。',
      );
    }
    final Uri joinBase = validatePublicHttpsBaseUri(
      configuredJoinBase,
      argumentName: 'officialJoinBaseUri',
    );
    if (parsedUri.scheme != joinBase.scheme ||
        parsedUri.host.toLowerCase() != joinBase.host.toLowerCase() ||
        parsedUri.port != joinBase.port ||
        parsedUri.userInfo.isNotEmpty ||
        parsedUri.hasQuery ||
        parsedUri.hasFragment ||
        parsedUri.pathSegments.length != 2 ||
        parsedUri.pathSegments.first != 'c') {
      throw const InvalidClassroomJoinInput('公式のみんアプ教室リンクではありません。');
    }
    return normalizeClassroomCode(parsedUri.pathSegments[1]);
  }

  return normalizeClassroomCode(input);
}

String normalizeClassroomCode(String rawCode) {
  if (rawCode.length > 64) {
    throw const InvalidClassroomJoinInput('教室コードの形式が正しくありません。');
  }
  final String normalized = rawCode.replaceAll('-', '').toUpperCase();
  if (normalized.length != classroomCodeLength ||
      normalized.codeUnits.any(
        (int unit) => !classroomCodeAlphabet.contains(String.fromCharCode(unit)),
      )) {
    throw const InvalidClassroomJoinInput('教室コードの形式が正しくありません。');
  }
  return '${normalized.substring(0, 4)}-'
      '${normalized.substring(4, 8)}-'
      '${normalized.substring(8, 12)}';
}
