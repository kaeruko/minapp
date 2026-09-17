import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/builtin_webview.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  test('built-in WebView only accepts microphone-only permission requests', () {
    expect(
      isBuiltInMicrophoneOnlyPermissionRequest(
        const <WebViewPermissionResourceType>{
          WebViewPermissionResourceType.microphone,
        },
      ),
      isTrue,
    );
    expect(
      isBuiltInMicrophoneOnlyPermissionRequest(
        const <WebViewPermissionResourceType>{
          WebViewPermissionResourceType.camera,
        },
      ),
      isFalse,
    );
    expect(
      isBuiltInMicrophoneOnlyPermissionRequest(
        const <WebViewPermissionResourceType>{
          WebViewPermissionResourceType.microphone,
          WebViewPermissionResourceType.camera,
        },
      ),
      isFalse,
    );
    expect(
      isBuiltInMicrophoneOnlyPermissionRequest(
        const <WebViewPermissionResourceType>{},
      ),
      isFalse,
    );
  });
}
