import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/girls/girls_source_zip.dart';

void main() {
  test('source archive roundtrip edits text and preserves binary files', () {
    final GirlsSourceArchive source = GirlsSourceArchive.fromEntries(
      <String, Uint8List>{
        'index.html': Uint8List.fromList(utf8.encode('<h1>before</h1>')),
        'app.js': Uint8List.fromList(utf8.encode('console.log("ok");')),
        'image.png': Uint8List.fromList(<int>[0, 1, 2, 3, 254, 255]),
      },
    );

    final GirlsSourceArchive decoded = GirlsSourceArchive.decode(source.encode());
    expect(decoded.textPaths, <String>['app.js', 'index.html']);
    expect(decoded.readText('index.html'), '<h1>before</h1>');

    decoded.writeText('index.html', '<h1>after</h1>');
    final GirlsSourceArchive saved = GirlsSourceArchive.decode(decoded.encode());
    expect(saved.readText('index.html'), '<h1>after</h1>');
    expect(saved.readText('app.js'), 'console.log("ok");');
  });

  test('source archive requires root index.html', () {
    expect(
      () => GirlsSourceArchive.fromEntries(<String, Uint8List>{
        'nested/index.html': Uint8List.fromList(utf8.encode('nested')),
      }),
      throwsFormatException,
    );
  });

  test('source archive rejects traversal paths instead of normalizing them', () {
    expect(
      () => GirlsSourceArchive.fromEntries(<String, Uint8List>{
        'index.html': Uint8List.fromList(utf8.encode('ok')),
        '../escape.js': Uint8List.fromList(utf8.encode('bad')),
      }),
      throwsFormatException,
    );
  });
}
