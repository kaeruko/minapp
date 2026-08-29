import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/directory_bootstrap.dart';

void main() {
  test('explicit Directory override is used without contacting Google Drive', () async {
    final MockClient client = MockClient((http.Request request) async {
      throw StateError('Google Drive must not be contacted for explicit override');
    });

    final Uri result = await resolveDirectoryBaseUri(
      explicitBaseUrl: 'https://directory.example.com',
      client: client,
    );

    expect(result, Uri.parse('https://directory.example.com'));
  });

  test('loads exactly one Directory URL from the configured Google Drive file', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'drive.google.com');
      expect(request.url.path, '/uc');
      expect(request.url.queryParameters['export'], 'download');
      expect(
        request.url.queryParameters['id'],
        minAppDirectoryGoogleDriveFileId,
      );
      expect(request.url.queryParameters['t'], '1787968800000');
      expect(request.headers['Accept'], 'text/plain');
      return http.Response(
        'https://directory.example.com\n',
        200,
      );
    });

    final Uri result = await resolveDirectoryBaseUri(
      client: client,
      now: () => DateTime.fromMillisecondsSinceEpoch(
        1787968800000,
        isUtc: true,
      ),
    );

    expect(result, Uri.parse('https://directory.example.com'));
  });

  test('rejects non-200 Google Drive response without fallback', () async {
    final MockClient client = MockClient(
      (http.Request request) async => http.Response('unavailable', 503),
    );

    await expectLater(
      resolveDirectoryBaseUri(client: client),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          'Google Drive Directory config returned HTTP 503.',
        ),
      ),
    );
  });

  test('rejects empty Google Drive config', () async {
    final MockClient client = MockClient(
      (http.Request request) async => http.Response('\n\r\n', 200),
    );

    await expectLater(
      resolveDirectoryBaseUri(client: client),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects multiple non-empty Google Drive config lines', () async {
    final MockClient client = MockClient(
      (http.Request request) async => http.Response(
        'https://one.example.com\nhttps://two.example.com\n',
        200,
      ),
    );

    await expectLater(
      resolveDirectoryBaseUri(client: client),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects invalid or local Directory endpoint from Google Drive', () async {
    final MockClient client = MockClient(
      (http.Request request) async => http.Response('https://127.0.0.1\n', 200),
    );

    await expectLater(
      resolveDirectoryBaseUri(client: client),
      throwsArgumentError,
    );
  });

  test('unconfigured Drive marker is rejected instead of falling back', () async {
    final MockClient client = MockClient(
      (http.Request request) async =>
          http.Response('UNCONFIGURED_MINAPP_DIRECTORY_API_BASE_URL\n', 200),
    );

    await expectLater(
      resolveDirectoryBaseUri(client: client),
      throwsArgumentError,
    );
  });
}
