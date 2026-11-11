import 'package:flutter_test/flutter_test.dart';
import 'package:tidy/media/clutter_group.dart';
import 'package:tidy/media/grouping.dart';
import 'package:tidy/media/grouping_options.dart';
import 'package:tidy/media/media_item.dart';

import 'test_helpers.dart';

const _mb = GroupingOptions.megabyte;

void main() {
  const options = GroupingOptions();

  group('findDuplicates', () {
    test('groups equal size + content hash and keeps the oldest copy', () {
      final a = photo(1, size: 500, hash: 'h1', added: 300);
      final b = photo(2, size: 500, hash: 'h1', added: 100, path: '/storage/emulated/0/Download/copy.jpg');
      final c = photo(3, size: 500, hash: 'h1', added: 200);
      final other = photo(4, size: 500, hash: 'h2');
      final noHash = photo(5, size: 500);
      final clusters = findDuplicates([a, b, c, other, noHash]);
      expect(clusters, hasLength(1));
      expect(clusters.single.items.map((i) => i.id), unorderedEquals([1, 2, 3]));
      expect(clusters.single.best.id, 2);
      expect(totalBytes(clusters.single.extras), 1000);
    });

    test('same hash but different size is not a duplicate', () {
      expect(findDuplicates([photo(1, size: 10, hash: 'h'), photo(2, size: 11, hash: 'h')]), isEmpty);
    });

    test('a photo and a video with the same hash are both found (ids may collide)', () {
      final p = photo(1, size: 9, hash: 'x');
      final v = MediaItem(id: 1, isVideo: true, path: '/v.mp4', size: 9, contentHash: 'x');
      expect(findDuplicates([p, v]).single.items, hasLength(2));
      expect(p.key, isNot(v.key));
    });
  });

  group('findSimilar', () {
    test('clusters near-identical hashes within the time window and keeps the sharpest', () {
      final a = photo(1, taken: 100, dHash: 0, blur: 80);
      final b = photo(2, taken: 110, dHash: 0x3, blur: 400); // 2 bits away
      final c = photo(3, taken: 125, dHash: 0x7, blur: 120); // 1 bit from b, 3 from a
      final clusters = findSimilar([a, b, c], options);
      expect(clusters, hasLength(1));
      expect(clusters.single.items, hasLength(3));
      expect(clusters.single.best.id, 2);
    });

    test('does not merge photos further apart than the Hamming limit', () {
      final a = photo(1, taken: 100, dHash: 0);
      final b = photo(2, taken: 101, dHash: 0xFF); // 8 bits > 6
      expect(findSimilar([a, b], options), isEmpty);
      expect(findSimilar([a, b], options.copyWith(similarity: Sensitivity.high)), hasLength(1)); // limit 10
    });

    test('does not merge photos taken outside the window', () {
      final a = photo(1, taken: 100, dHash: 0);
      final b = photo(2, taken: 100 + 121, dHash: 0); // 2 min + 1 s
      expect(findSimilar([a, b], options), isEmpty);
      final within = photo(3, taken: 100 + 119, dHash: 0);
      expect(findSimilar([a, within], options), hasLength(1));
    });

    test('ignores screenshots, videos and photos without a hash', () {
      final shot = photo(1, taken: 100, dHash: 0, path: '/Pictures/Screenshots/a.png');
      final shot2 = photo(2, taken: 101, dHash: 0, path: '/Pictures/Screenshots/b.png');
      final v = video(3);
      final noHash = photo(4, taken: 100, dHash: null);
      final real = photo(5, taken: 100, dHash: 0);
      expect(findSimilar([shot, shot2, v, noHash, real], options), isEmpty);
    });

    test('keeps the higher resolution when it is much bigger', () {
      final small = photo(1, taken: 100, dHash: 0, w: 1000, h: 750, blur: 900);
      final big = photo(2, taken: 101, dHash: 0, w: 4000, h: 3000, blur: 300);
      expect(findSimilar([small, big], options).single.best.id, 2);
    });

    test('excluded keys (exact duplicate extras) are left out', () {
      final a = photo(1, taken: 100, dHash: 0);
      final b = photo(2, taken: 101, dHash: 0);
      expect(findSimilar([a, b], options, exclude: {b.key}), isEmpty);
    });
  });

  group('findBlurry', () {
    test('flags photos under the threshold, blurriest first', () {
      final items = [photo(1, blur: 20), photo(2, blur: 59), photo(3, blur: 61), photo(4, blur: 5)];
      expect(findBlurry(items, options).map((i) => i.id), [4, 1, 2]);
    });

    test('sensitivity moves the threshold', () {
      final items = [photo(1, blur: 45), photo(2, blur: 80)];
      expect(findBlurry(items, options.copyWith(blurriness: Sensitivity.low)), isEmpty);
      expect(findBlurry(items, options.copyWith(blurriness: Sensitivity.high)), hasLength(2));
    });

    test('skips screenshots, tiny images, videos and unscored photos', () {
      final items = [
        photo(1, blur: 1, path: '/Pictures/Screenshots/a.png'),
        photo(2, blur: 1, w: 200, h: 200),
        video(3),
        photo(4, blur: null),
      ];
      expect(findBlurry(items, options), isEmpty);
    });
  });

  group('large videos and old downloads', () {
    test('large videos: at or above the threshold, biggest first, images never', () {
      final items = [
        video(1, size: 99 * _mb),
        video(2, size: 100 * _mb),
        video(3, size: 400 * _mb),
        photo(4, size: 900 * _mb),
      ];
      expect(findLargeVideos(items, options).map((i) => i.id), [3, 2]);
      expect(findLargeVideos(items, options.copyWith(largeVideoBytes: 50 * _mb)), hasLength(3));
    });

    test('old downloads: only images in Download older than 90 days', () {
      const now = 200 * 86400;
      final items = [
        photo(1, path: '/storage/emulated/0/Download/old.jpg', added: now - 91 * 86400),
        photo(2, path: '/storage/emulated/0/Download/new.jpg', added: now - 10 * 86400),
        photo(3, path: '/storage/emulated/0/DCIM/Camera/old.jpg', added: now - 500 * 86400),
        video(4, path: '/storage/emulated/0/Download/old.mp4', added: now - 500 * 86400),
      ];
      expect(findOldDownloads(items, options, nowSec: now).map((i) => i.id), [1]);
    });
  });

  group('buildGroups and totals', () {
    test('builds every group and counts a file once in the summary', () {
      const now = 400 * 86400;
      final dup1 = photo(1, size: 4000, hash: 'd', added: 10, taken: 5000, dHash: 0x00FF, path: '/Pictures/Screenshots/a.png');
      final dup2 = photo(2, size: 4000, hash: 'd', added: 20, taken: 6000, dHash: 0x00FF, path: '/Pictures/Screenshots/a (1).png');
      final s1 = photo(3, size: 100, taken: 100, dHash: 0xF0F0F0F0, blur: 10, added: now - 5);
      final s2 = photo(4, size: 200, taken: 105, dHash: 0xF0F0F0F0, blur: 700, added: now - 5);
      final wa = photo(5, size: 300, path: '/storage/emulated/0/WhatsApp/Media/WhatsApp Images/IMG-1.jpg', dHash: 0x1234567, taken: 9000, blur: 400);
      final big = video(6, size: 300 * _mb);
      final old = photo(7, size: 50, path: '/storage/emulated/0/Download/o.jpg', added: now - 120 * 86400, dHash: 0x76543210, taken: 8000, blur: 400);

      final groups = buildGroups([dup1, dup2, s1, s2, wa, big, old], options, nowSec: now);
      final kinds = groups.map((g) => g.kind).toList();
      expect(kinds, [
        GroupKind.duplicates,
        GroupKind.similar,
        GroupKind.blurry,
        GroupKind.screenshots,
        GroupKind.messaging,
        GroupKind.largeVideos,
        GroupKind.oldDownloads,
      ]);

      final similar = groups.firstWhere((g) => g.kind == GroupKind.similar);
      expect(similar.clusters.single.best.id, 4); // sharper of s1 / s2
      expect(similar.reclaimable.map((i) => i.id), [3]);

      // Distinct reclaimable files: dup1 and dup2 (both screenshots), s1 (similar and blurry,
      // counted once), wa, big and old. s2 is the best of its cluster and is not reclaimable.
      final summary = ClutterSummary.of(groups);
      expect(summary.count, 6);
      expect(summary.bytes, 4000 + 4000 + 100 + 300 + 50 + 300 * _mb);
    });

    test('group totals use the files to remove, not the whole cluster', () {
      final a = photo(1, size: 700, hash: 'h', added: 1);
      final b = photo(2, size: 700, hash: 'h', added: 2);
      final g = buildGroups([a, b], options, nowSec: 1000000).single;
      expect(g.kind, GroupKind.duplicates);
      expect(g.items, hasLength(2));
      expect(g.reclaimableCount, 1);
      expect(g.reclaimableBytes, 700);
    });

    test('leaves out empty groups', () {
      expect(buildGroups([photo(1)], options, nowSec: 1000000), isEmpty);
    });
  });
}
