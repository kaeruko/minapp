import 'package:http/http.dart' as http;

import '../hosted_consumer_api.dart';
import '../hosted_edition.dart';
import '../hosted_session_store.dart';

/// Kobo compatibility name for the edition-neutral hosted consumer API.
class HostedKoboApi extends HostedConsumerApi {
  HostedKoboApi({
    required Uri baseUri,
    http.Client? client,
    HostedSessionStore? sessionStore,
  }) : super(
          baseUri: baseUri,
          edition: HostedEditions.kobo,
          client: client,
          sessionStore: sessionStore,
        );
}
