import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/hosted_app_webview.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  test('Hosted WebView accepts microphone-only permission requests', () {
    expect(
      isHostedMicrophoneOnlyPermissionRequest(
        const <WebViewPermissionResourceType>{
          WebViewPermissionResourceType.microphone,
        },
      ),
      isTrue,
    );
  });

  test('Hosted WebView rejects empty and non-microphone permission requests', () {
    expect(
      isHostedMicrophoneOnlyPermissionRequest(
        const <WebViewPermissionResourceType>{},
      ),
      isFalse,
    );
    expect(
      isHostedMicrophoneOnlyPermissionRequest(
        const <WebViewPermissionResourceType>{
          WebViewPermissionResourceType.camera,
        },
      ),
      isFalse,
    );
    expect(
      isHostedMicrophoneOnlyPermissionRequest(
        const <WebViewPermissionResourceType>{
          WebViewPermissionResourceType.microphone,
          WebViewPermissionResourceType.camera,
        },
      ),
      isFalse,
    );
  });
}
