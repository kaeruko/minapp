import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Builds MinApp WebViews with Android Hybrid Composition.
///
/// The default Android implementation uses Texture Layer Hybrid Composition.
/// Girls frequently destroys a Player WebView and immediately creates an Editor
/// WebView. On some Android/emulator WebView renderers that rapid SurfaceTexture
/// lifecycle can crash the renderer, so MinApp uses the more conservative
/// Hybrid Composition path on Android.
Widget buildMinAppWebViewWidget(WebViewController controller) {
  final platform = controller.platform;
  if (platform is AndroidWebViewController) {
    return WebViewWidget.fromPlatformCreationParams(
      params: AndroidWebViewWidgetCreationParams(
        controller: platform,
        displayWithHybridComposition: true,
      ),
    );
  }
  return WebViewWidget(controller: controller);
}
