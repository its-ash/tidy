import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../media/clutter_group.dart';

/// Title, icon and wording of each kind of clutter.
extension GroupKindStyle on GroupKind {
  String get title => switch (this) {
        GroupKind.duplicates => 'Duplicates',
        GroupKind.similar => 'Similar photos',
        GroupKind.blurry => 'Blurry photos',
        GroupKind.screenshots => 'Screenshots',
        GroupKind.messaging => 'WhatsApp & messaging',
        GroupKind.largeVideos => 'Large videos',
        GroupKind.oldDownloads => 'Old downloads',
      };

  String get description => switch (this) {
        GroupKind.duplicates => 'Identical files, keeping the oldest copy',
        GroupKind.similar => 'Bursts and retakes, keeping the best shot',
        GroupKind.blurry => 'Out-of-focus or shaky shots',
        GroupKind.screenshots => 'Screenshots and screen recordings',
        GroupKind.messaging => 'Photos, videos and GIFs from chats',
        GroupKind.largeVideos => 'The biggest videos, largest first',
        GroupKind.oldDownloads => 'Images in Downloads older than 90 days',
      };

  IconData get icon => switch (this) {
        GroupKind.duplicates => Icons.content_copy_rounded,
        GroupKind.similar => Icons.burst_mode_rounded,
        GroupKind.blurry => Icons.blur_on_rounded,
        GroupKind.screenshots => Icons.screenshot_rounded,
        GroupKind.messaging => Icons.chat_rounded,
        GroupKind.largeVideos => Icons.movie_rounded,
        GroupKind.oldDownloads => Icons.download_rounded,
      };

  UiStatus get status => switch (this) {
        GroupKind.duplicates => UiStatus.danger,
        GroupKind.similar => UiStatus.warning,
        GroupKind.blurry => UiStatus.info,
        GroupKind.screenshots => UiStatus.accent,
        GroupKind.messaging => UiStatus.success,
        GroupKind.largeVideos => UiStatus.warning,
        GroupKind.oldDownloads => UiStatus.neutral,
      };
}

extension ClutterGroupText on ClutterGroup {
  /// "12 files" or "5 sets, 12 extra files".
  String get summary {
    final n = reclaimableCount;
    final files = n == 1 ? '1 file' : '$n files';
    if (!isClustered) return files;
    final sets = clusters.length == 1 ? '1 set' : '${clusters.length} sets';
    return '$sets, $files to remove';
  }
}
