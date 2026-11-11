import 'classifier.dart';
import 'clutter_group.dart';
import 'grouping_options.dart';
import 'hashing.dart';
import 'media_item.dart';

/// Max photos each photo is compared with inside the time window. Keeps a bulk import that
/// shares one timestamp from becoming O(n^2).
const int _maxNeighbors = 150;

/// Builds every clutter group from the scanned [items]. Pure and synchronous: run it in an
/// isolate for big libraries. Groups with nothing in them are left out.
List<ClutterGroup> buildGroups(List<MediaItem> items, GroupingOptions options, {required int nowSec}) {
  final duplicates = findDuplicates(items);
  final dupExtras = {for (final c in duplicates) ...c.extras.map((i) => i.key)};

  final groups = <ClutterGroup>[
    if (duplicates.isNotEmpty) ClutterGroup(GroupKind.duplicates, [for (final c in duplicates) ...c.items], clusters: duplicates),
    ..._clustered(GroupKind.similar, findSimilar(items, options, exclude: dupExtras)),
    _flat(GroupKind.blurry, findBlurry(items, options)),
    _flat(GroupKind.screenshots, items.where(Classifier.isScreenshot).toList()..sort(_newestFirst)),
    _flat(GroupKind.messaging, items.where(Classifier.isMessagingMedia).toList()..sort(_newestFirst)),
    _flat(GroupKind.largeVideos, findLargeVideos(items, options)),
    _flat(GroupKind.oldDownloads, findOldDownloads(items, options, nowSec: nowSec)),
  ];
  return [for (final g in groups) if (g.items.isNotEmpty) g];
}

Iterable<ClutterGroup> _clustered(GroupKind kind, List<MediaCluster> clusters) =>
    clusters.isEmpty ? const [] : [ClutterGroup(kind, [for (final c in clusters) ...c.items], clusters: clusters)];

ClutterGroup _flat(GroupKind kind, List<MediaItem> items) => ClutterGroup(kind, items);

int _newestFirst(MediaItem a, MediaItem b) => b.takenMs.compareTo(a.takenMs);

/// Exact duplicates: files with the same size and the same content hash. The oldest copy
/// (earliest `date_added`, then the shortest path) is the one to keep.
List<MediaCluster> findDuplicates(List<MediaItem> items) {
  final byContent = <String, List<MediaItem>>{};
  for (final i in items) {
    final h = i.contentHash;
    if (h == null || i.size <= 0) continue;
    byContent.putIfAbsent('${i.size}:$h', () => []).add(i);
  }
  final clusters = <MediaCluster>[
    for (final list in byContent.values)
      if (list.length > 1) MediaCluster(list, _oldest(list)),
  ];
  clusters.sort((a, b) => totalBytes(b.extras).compareTo(totalBytes(a.extras)));
  return clusters;
}

MediaItem _oldest(List<MediaItem> list) => list.reduce((a, b) {
      if (a.addedSec != b.addedSec) return a.addedSec < b.addedSec ? a : b;
      return a.path.length <= b.path.length ? a : b;
    });

/// Similar photos: dHash Hamming distance <= `options.maxHamming` between photos taken within
/// `options.similarWindow` of each other, merged into clusters (union-find, so A~B and B~C give
/// one cluster). Screenshots, videos and photos without a hash are ignored, as are the
/// [exclude]d keys (extra copies of exact duplicates, which have their own group).
List<MediaCluster> findSimilar(List<MediaItem> items, GroupingOptions options, {Set<int> exclude = const {}}) {
  final photos = [
    for (final i in items)
      if (i.isImage && i.dHash != null && !exclude.contains(i.key) && !Classifier.isScreenshot(i)) i,
  ]..sort((a, b) => a.takenMs.compareTo(b.takenMs));

  final parent = List<int>.generate(photos.length, (i) => i);
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  final windowMs = options.similarWindow.inMilliseconds;
  final maxBits = options.maxHamming;
  for (var i = 0; i < photos.length; i++) {
    final a = photos[i];
    final last = i + _maxNeighbors < photos.length ? i + _maxNeighbors : photos.length - 1;
    for (var j = i + 1; j <= last; j++) {
      final b = photos[j];
      if (b.takenMs - a.takenMs > windowMs) break;
      if (hamming(a.dHash!, b.dHash!) <= maxBits) parent[find(j)] = find(i);
    }
  }

  final byRoot = <int, List<MediaItem>>{};
  for (var i = 0; i < photos.length; i++) {
    byRoot.putIfAbsent(find(i), () => []).add(photos[i]);
  }
  final clusters = <MediaCluster>[
    for (final list in byRoot.values)
      if (list.length > 1) MediaCluster(list, pickBest(list)),
  ];
  clusters.sort((a, b) => totalBytes(b.extras).compareTo(totalBytes(a.extras)));
  return clusters;
}

/// The photo to keep from a cluster: the sharpest among those with (nearly) the highest
/// resolution; ties go to the larger file.
MediaItem pickBest(List<MediaItem> cluster) {
  final maxPixels = cluster.fold(0, (m, i) => i.pixels > m ? i.pixels : m);
  final sizable = cluster.where((i) => i.pixels >= maxPixels * 0.9).toList();
  return sizable.reduce((a, b) {
    final sa = a.blur ?? 0;
    final sb = b.blur ?? 0;
    if (sa != sb) return sa > sb ? a : b;
    return a.size >= b.size ? a : b;
  });
}

/// Photos whose blur score is under `options.blurThreshold`, blurriest first. Screenshots and
/// tiny images are skipped (flat UI and icons always score low).
List<MediaItem> findBlurry(List<MediaItem> items, GroupingOptions options) {
  final out = [
    for (final i in items)
      if (i.isImage &&
          i.blur != null &&
          i.blur! < options.blurThreshold &&
          (i.width >= GroupingOptions.minBlurSide || i.height >= GroupingOptions.minBlurSide) &&
          !Classifier.isScreenshot(i))
        i,
  ];
  out.sort((a, b) => a.blur!.compareTo(b.blur!));
  return out;
}

/// Videos of at least `options.largeVideoBytes`, biggest first.
List<MediaItem> findLargeVideos(List<MediaItem> items, GroupingOptions options) {
  final out = [for (final i in items) if (i.isVideo && i.size >= options.largeVideoBytes) i];
  out.sort((a, b) => b.size.compareTo(a.size));
  return out;
}

/// Photos in the Download folder added more than `options.oldDownloadDays` days ago, oldest first.
List<MediaItem> findOldDownloads(List<MediaItem> items, GroupingOptions options, {required int nowSec}) {
  final cutoff = nowSec - options.oldDownloadDays * 86400;
  final out = [
    for (final i in items)
      if (i.isImage && Classifier.isDownload(i) && !Classifier.isMessagingMedia(i) && i.addedSec > 0 && i.addedSec < cutoff) i,
  ];
  out.sort((a, b) => a.addedSec.compareTo(b.addedSec));
  return out;
}
