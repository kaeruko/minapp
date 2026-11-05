import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final String? root = Platform.environment['MINAPP_STORE_SHOTS_DIR'];
  if (root == null || root.isEmpty) {
    throw StateError('MINAPP_STORE_SHOTS_DIR must be set explicitly');
  }
  final Directory directory = Directory(root);
  if (!directory.existsSync()) {
    throw StateError('Screenshot output directory does not exist: $root');
  }

  await integrationDriver(
    onScreenshot: (
      String name,
      List<int> bytes, [
      Map<String, Object?>? args,
    ]) async {
      const Set<String> expected = <String>{
        '01-home',
        '02-code-editor',
      };
      if (!expected.contains(name)) {
        throw StateError('Unexpected screenshot name: $name');
      }
      if (bytes.length < 1024) {
        throw StateError('Screenshot $name is unexpectedly small: ${bytes.length}');
      }
      final File image = File('${directory.path}/$name.png');
      if (image.existsSync()) {
        throw StateError('Refusing to overwrite screenshot: ${image.path}');
      }
      await image.writeAsBytes(bytes, flush: true);
      return true;
    },
  );
}
