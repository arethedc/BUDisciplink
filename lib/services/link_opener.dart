import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkOpener {
  const LinkOpener._();

  static Future<bool> openExternal(Uri uri) {
    return launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
  }

  static Future<bool> openInternalInNewTab(String appPath) {
    if (!kIsWeb) return Future<bool>.value(false);
    final normalized = appPath.trim();
    if (!normalized.startsWith('/')) return Future<bool>.value(false);
    final uri = Uri.parse(normalized);
    final absolute = Uri.base.resolveUri(uri);
    return launchUrl(
      absolute,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
  }
}
