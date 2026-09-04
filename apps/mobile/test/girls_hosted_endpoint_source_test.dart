import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls_hosted_endpoint_source.dart';

void main() {
  test('loads and validates Girls Hosted endpoint from Google Drive', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'drive.google.com');
      expect(request.url.path, '/uc');
      expect(request.url.queryParameters['export'], 'download');
      expect(
        request.url.queryParameters['id'],
        minAppGirlsHostedGoogleDriveFileId,
      );
      expect(request.url.queryParameters['t'], '1234');
      return http.Response(
        'https://7ptvf2blw7.execute-api.us-west-2.amazonaws.com\n',
        200,
      );
    });

    final Uri result = await loadGirlsHostedBaseUriFromGoogleDrive(
      client: client,
      now: DateTime.fromMillisecondsSinceEpoch(1234),
    );

    expect(
      result,
      Uri.parse('https://7ptvf2blw7.execute-api.us-west-2.amazonaws.com'),
    );
  });

  test('fails on non-200 Google Drive response', () async {
    final MockClient client = MockClient(
      (http.Request request) async => http.Response('missing', 404),
    );

    await expectLater(
      loadGirlsHostedBaseUriFromGoogleDrive(client: client),
      throwsA(isA<StateError>()),
    );
  });

  test('fails when endpoint file contains multiple non-empty lines', () async {
    final MockClient client = MockClient(
      (http.Request request) async => http.Response(
        'https://example.com\nhttps://example.org\n',
        200,
      ),
    );

    await expectLater(
      loadGirlsHostedBaseUriFromGoogleDrive(client: client),
      throwsA(isA<StateError>()),
    );
  });

  test('fails when endpoint is not an allowed public HTTPS base URL', () async {
    final MockClient client = MockClient(
      (http.Request request) async => http.Response(
        'http://localhost:8000\n',
        200,
      ),
    );

    await expectLater(
      loadGirlsHostedBaseUriFromGoogleDrive(client: client),
      throwsA(isA<ArgumentError>()),
    );
  });
}
