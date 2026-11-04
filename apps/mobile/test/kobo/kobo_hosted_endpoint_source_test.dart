import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/kobo_hosted_endpoint_source.dart';

void main() {
  test('Kobo endpoint accepts an explicitly configured HTTPS origin', () async {
    final Uri endpoint = await loadKoboHostedBaseUri(
      directBaseUri: 'https://kobo-api.example.com',
      googleDriveFileId: '',
    );

    expect(endpoint, Uri.parse('https://kobo-api.example.com'));
  });

  test('Kobo endpoint fails fast instead of falling back to Girls', () {
    expect(
      () => loadKoboHostedBaseUri(
        directBaseUri: '',
        googleDriveFileId: '',
      ),
      throwsStateError,
    );
  });

  test('Kobo endpoint uses only its configured Drive file', () async {
    const String fileId = 'koboEndpointFile123';
    final MockClient client = MockClient((http.Request request) async {
      expect(request.url.queryParameters['id'], fileId);
      return http.Response('https://kobo-api.example.com\n', 200);
    });
    addTearDown(client.close);

    final Uri endpoint = await loadKoboHostedBaseUri(
      client: client,
      directBaseUri: '',
      googleDriveFileId: fileId,
    );

    expect(endpoint, Uri.parse('https://kobo-api.example.com'));
  });
}
