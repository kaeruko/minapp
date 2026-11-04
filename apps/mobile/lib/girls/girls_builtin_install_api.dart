import 'package:http/http.dart' as http;

import '../hosted_builtin_install_api.dart';

export '../hosted_builtin_install_api.dart';

/// Backwards-compatible Girls name for edition-neutral built-in installation.
class GirlsBuiltinInstallApi extends HostedBuiltinInstallApi {
  GirlsBuiltinInstallApi({required super.baseUri, http.Client? client})
      : super(client: client);
}
