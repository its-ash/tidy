import 'package:flutter_test/flutter_test.dart';
import 'package:tidy/media/classifier.dart';

import 'test_helpers.dart';

void main() {
  group('screenshots', () {
    test('matches the Screenshots folder and file names, any case', () {
      expect(Classifier.isScreenshot(photo(1, path: '/storage/emulated/0/Pictures/Screenshots/a.png')), isTrue);
      expect(Classifier.isScreenshot(photo(2, path: '/storage/emulated/0/DCIM/Screenshots/b.jpg')), isTrue);
      expect(Classifier.isScreenshot(photo(3, path: '/storage/emulated/0/DCIM/Camera/Screenshot_2024.png')), isTrue);
      expect(Classifier.isScreenshot(photo(4, path: '/storage/emulated/0/DCIM/SCREENSHOTS/c.png')), isTrue);
    });

    test('includes screen recordings', () {
      expect(Classifier.isScreenshot(video(5, path: '/storage/emulated/0/Movies/ScreenRecords/r.mp4')), isTrue);
    });

    test('ignores normal camera photos', () {
      expect(Classifier.isScreenshot(photo(6)), isFalse);
    });
  });

  group('messaging media', () {
    test('matches WhatsApp, Business, Telegram and scoped-storage paths', () {
      for (final p in [
        '/storage/emulated/0/WhatsApp/Media/WhatsApp Images/Sent/IMG-1.jpg',
        '/storage/emulated/0/WhatsApp/Media/WhatsApp Animated Gifs/x.mp4',
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/v.mp4',
        '/storage/emulated/0/WhatsApp Business/Media/WhatsApp Business Images/a.jpg',
        '/storage/emulated/0/Pictures/Telegram/photo.jpg',
        '/storage/emulated/0/Telegram/Telegram Video/v.mp4',
        '/storage/emulated/0/Android/media/org.telegram.messenger/Telegram/Telegram Images/i.jpg',
      ]) {
        expect(Classifier.isMessagingMedia(photo(1, path: p)), isTrue, reason: p);
      }
    });

    test('ignores camera, downloads and WhatsApp databases', () {
      expect(Classifier.isMessagingMedia(photo(1)), isFalse);
      expect(Classifier.isMessagingMedia(photo(2, path: '/storage/emulated/0/Download/a.jpg')), isFalse);
      expect(Classifier.isMessagingMedia(photo(3, path: '/storage/emulated/0/Android/media/com.example/x.jpg')), isFalse);
    });

    test('names the app', () {
      expect(Classifier.messagingApp(photo(1, path: '/x/WhatsApp/Media/a.jpg')), 'WhatsApp');
      expect(Classifier.messagingApp(photo(2, path: '/x/Telegram/a.jpg')), 'Telegram');
      expect(Classifier.messagingApp(photo(3)), isNull);
    });
  });

  test('downloads', () {
    expect(Classifier.isDownload(photo(1, path: '/storage/emulated/0/Download/a.jpg')), isTrue);
    expect(Classifier.isDownload(photo(2, path: '/storage/emulated/0/Download/sub/b.jpg')), isTrue);
    expect(Classifier.isDownload(photo(3)), isFalse);
  });
}
