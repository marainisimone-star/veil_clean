import 'dart:io';

class ExternalLinkService {
  ExternalLinkService._();

  static Future<bool> openUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', url], runInShell: true);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [url]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [url]);
        return true;
      }
    } catch (_) {}
    return false;
  }
}
