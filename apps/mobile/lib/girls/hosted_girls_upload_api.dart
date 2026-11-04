import 'package:http/http.dart' as http;

import '../hosted_upload_api.dart';

export '../hosted_upload_api.dart';

const int maxGirlsZipUploadBytes = maxHostedZipUploadBytes;

/// Backwards-compatible Girls name for the edition-neutral upload API.
class HostedGirlsUploadApi extends HostedUploadApi {
  HostedGirlsUploadApi({required super.baseUri, http.Client? client})
      : super(client: client);
}
