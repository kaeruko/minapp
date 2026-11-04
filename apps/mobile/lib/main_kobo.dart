import 'package:flutter/material.dart';

import 'kobo/hosted_kobo_api.dart';
import 'kobo/kobo_persistent_app.dart';
import 'kobo_hosted_endpoint_source.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final Uri hostedApiBaseUri = await loadKoboHostedBaseUri();

  runApp(
    KoboPersistentApp(
      api: HostedKoboApi(baseUri: hostedApiBaseUri),
    ),
  );
}
