import 'dart:convert';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// رقم هذه النسخة كما بُنيت على GitHub (build-N). صفر في البناء المحلي.
const appBuild = int.fromEnvironment('BUILD_NUMBER');

/// نسخة Google Play: المتجر وحده يحدّث التطبيق (سياسة جوجل تمنع التحديث من خارجه)، فنُطفئ فحص GitHub.
const playStore = bool.fromEnvironment('PLAY_STORE');

class UpdateInfo {
  final int build;
  final String url;
  final String notes;
  const UpdateInfo(this.build, this.url, this.notes);
}

/// يسأل صفحة الإصدارات في GitHub عن أحدث نسخة. التطبيق يعمل دون إنترنت، وهذا الفحص وحده يحتاجه.
class Updates {
  static const _api = 'https://api.github.com/repos/madarekmatbaa-bit/Dhikra/releases/latest';

  /// أحدث نسخة منشورة، أو null إن تعذر الاتصال.
  static Future<UpdateInfo?> latest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(_api));
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final m = jsonDecode(body) as Map<String, dynamic>;
      final tag = m['tag_name'] as String? ?? '';
      final n = int.tryParse(tag.replaceFirst('build-', ''));
      if (n == null) return null;
      final assets = (m['assets'] as List?) ?? const [];
      final apk = assets.cast<Map>().where((a) => (a['name'] as String? ?? '').endsWith('.apk')).firstOrNull;
      final url = apk?['browser_download_url'] as String? ??
          'https://github.com/madarekmatbaa-bit/Dhikra/releases/tag/$tag';
      return UpdateInfo(n, url, (m['body'] as String?) ?? '');
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// نسخة أحدث من المثبّتة، إن وُجدت.
  static Future<UpdateInfo?> available() async {
    if (playStore) return null;
    final l = await latest();
    if (l == null || appBuild == 0 || l.build <= appBuild) return null;
    return l;
  }

  static Future<bool> download(UpdateInfo u) =>
      launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication);
}
