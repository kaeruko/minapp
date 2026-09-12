import 'package:flutter/material.dart';

import 'girls/girls_persistent_app.dart';
import 'girls/hosted_girls_api.dart';
import 'girls_hosted_endpoint_source.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final Uri hostedApiBaseUri = await loadGirlsHostedBaseUriFromGoogleDrive();

  runApp(
    GirlsPersistentApp(
      api: HostedGirlsApi(baseUri: hostedApiBaseUri),
    ),
  );
}
