import 'package:http/http.dart' as http;

import '../hosted_consumer_api.dart';
import '../hosted_edition.dart';
import 'girls_session_store.dart';

export '../hosted_api.dart';

/// Girls compatibility name for the edition-neutral hosted consumer API.
class HostedGirlsApi extends HostedConsumerApi {
  HostedGirlsApi({
    required super.baseUri,
    http.Client? client,
    GirlsSessionStore? sessionStore,
  }) : super(
          edition: HostedEditions.girls,
          client: client,
          sessionStore: sessionStore,
        );
}
