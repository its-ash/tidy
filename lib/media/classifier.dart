import 'media_item.dart';

/// Path based rules that decide which clutter group a file can belong to.
/// All matching is on the lower-cased path, so `Screenshots` and `screenshots` are the same.
class Classifier {
  const Classifier._();

  static const _messagingFolders = [
    '/whatsapp/media/',
    '/whatsapp business/media/',
    '/android/media/com.whatsapp/',
    '/android/media/com.whatsapp.w4b/',
    '/telegram/',
    '/android/media/org.telegram.messenger/',
    '/signal/',
  ];

  /// Screenshots and screen recordings, by folder or file name.
  static bool isScreenshot(MediaItem item) {
    final p = item.path.toLowerCase();
    final b = item.bucket.toLowerCase();
    return p.contains('screenshot') ||
        p.contains('screen shot') ||
        p.contains('screenrecord') ||
        p.contains('screen recording') ||
        b.contains('screenshot');
  }

  /// WhatsApp, WhatsApp Business, Telegram and Signal media (received and sent, including GIFs and stickers).
  static bool isMessagingMedia(MediaItem item) {
    final p = item.path.toLowerCase();
    for (final folder in _messagingFolders) {
      if (p.contains(folder)) return true;
    }
    return false;
  }

  /// A file saved to the Download folder.
  static bool isDownload(MediaItem item) {
    final p = item.path.toLowerCase();
    return p.contains('/download/') || p.contains('/downloads/');
  }

  /// Which messaging app a path belongs to, for display. Null when [isMessagingMedia] is false.
  static String? messagingApp(MediaItem item) {
    final p = item.path.toLowerCase();
    if (p.contains('whatsapp')) return 'WhatsApp';
    if (p.contains('telegram')) return 'Telegram';
    if (p.contains('signal')) return 'Signal';
    return null;
  }
}
