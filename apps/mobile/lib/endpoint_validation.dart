import 'dart:io';

Uri validatePublicHttpsBaseUri(Uri uri, {required String argumentName}) {
  if (uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.port != 443) {
    throw ArgumentError.value(
      uri,
      argumentName,
      'must be an absolute HTTPS base URL using the default port and no path, credentials, query, or fragment',
    );
  }

  String host = uri.host;
  if (host.endsWith('.')) {
    host = host.substring(0, host.length - 1);
  }
  if (host.isEmpty || host.length > 253) {
    throw ArgumentError.value(uri, argumentName, 'host is invalid');
  }
  if (host.codeUnits.any((int unit) => unit > 0x7f)) {
    throw ArgumentError.value(uri, argumentName, 'host must be ASCII');
  }
  if (InternetAddress.tryParse(host) != null) {
    throw ArgumentError.value(uri, argumentName, 'IP literals are not allowed');
  }

  final String lowered = host.toLowerCase();
  if (lowered == 'localhost' ||
      lowered.endsWith('.localhost') ||
      lowered.endsWith('.local') ||
      lowered.endsWith('.internal') ||
      lowered.endsWith('.lan') ||
      lowered.endsWith('.home') ||
      !lowered.contains('.')) {
    throw ArgumentError.value(uri, argumentName, 'host must be a public DNS name');
  }

  final RegExp labelPattern = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$');
  for (final String label in lowered.split('.')) {
    if (!labelPattern.hasMatch(label)) {
      throw ArgumentError.value(uri, argumentName, 'host is malformed');
    }
  }

  return Uri(scheme: 'https', host: lowered);
}
