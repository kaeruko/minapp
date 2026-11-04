import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../hosted_edition.dart';
import '../hosted_session_store.dart';

typedef GirlsSessionStore = HostedSessionStore;

/// Backward-compatible Girls storage name with an edition-scoped key.
class SecureGirlsSessionStore extends SecureHostedSessionStore {
  SecureGirlsSessionStore({FlutterSecureStorage? storage})
      : super(
          refreshTokenStorageKey: HostedEditions.girls.refreshTokenStorageKey,
          storage: storage,
        );
}
