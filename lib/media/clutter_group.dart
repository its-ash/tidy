import 'media_item.dart';

/// The kinds of clutter Tidy finds, in the order they are listed.
enum GroupKind { duplicates, similar, blurry, screenshots, messaging, largeVideos, oldDownloads }

/// Files that are the same or near-same. [best] is the one to keep.
class MediaCluster {
  const MediaCluster(this.items, this.best);

  final List<MediaItem> items;
  final MediaItem best;

  /// Everything except [best].
  Iterable<MediaItem> get extras => items.where((i) => i != best);
}

/// One card on the home screen: a kind of clutter and the files in it.
///
/// Groups of [clusters] (duplicates, similar photos) suggest deleting all but the best of each
/// cluster. Flat groups suggest nothing: the user picks.
class ClutterGroup {
  const ClutterGroup(this.kind, this.items, {this.clusters = const []});

  final GroupKind kind;

  /// Every file shown for this group.
  final List<MediaItem> items;

  /// Empty for flat groups.
  final List<MediaCluster> clusters;

  bool get isClustered => clusters.isNotEmpty;

  /// Files worth deleting: all of a flat group, all but the best of each cluster.
  Iterable<MediaItem> get reclaimable => isClustered ? clusters.expand((c) => c.extras) : items;

  int get reclaimableBytes => totalBytes(reclaimable);
  int get reclaimableCount => reclaimable.length;

}

/// Totals over all groups, counting a file once even when it is in several groups.
class ClutterSummary {
  const ClutterSummary(this.count, this.bytes);

  factory ClutterSummary.of(Iterable<ClutterGroup> groups) {
    final seen = <int>{};
    var bytes = 0;
    for (final g in groups) {
      for (final i in g.reclaimable) {
        if (seen.add(i.key)) bytes += i.size;
      }
    }
    return ClutterSummary(seen.length, bytes);
  }

  final int count;
  final int bytes;
}
