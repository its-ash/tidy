/// One photo or video from MediaStore, plus what the native scan computed for it.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.isVideo,
    required this.path,
    required this.size,
    this.bucket = '',
    this.addedSec = 0,
    this.modifiedSec = 0,
    this.takenMs = 0,
    this.width = 0,
    this.height = 0,
    this.durationMs = 0,
    this.mime = '',
    this.dHash,
    this.blur,
    this.contentHash,
  });

  /// Builds an item from the map sent by `MainActivity.kt` (`startScan`).
  factory MediaItem.fromMap(Map<Object?, Object?> m) => MediaItem(
        id: (m['id']! as num).toInt(),
        isVideo: m['video'] == true,
        path: (m['path'] as String?) ?? '',
        bucket: (m['bucket'] as String?) ?? '',
        size: (m['size'] as num?)?.toInt() ?? 0,
        addedSec: (m['added'] as num?)?.toInt() ?? 0,
        modifiedSec: (m['modified'] as num?)?.toInt() ?? 0,
        takenMs: (m['taken'] as num?)?.toInt() ?? 0,
        width: (m['width'] as num?)?.toInt() ?? 0,
        height: (m['height'] as num?)?.toInt() ?? 0,
        durationMs: (m['duration'] as num?)?.toInt() ?? 0,
        mime: (m['mime'] as String?) ?? '',
        dHash: (m['dhash'] as num?)?.toInt(),
        blur: (m['blur'] as num?)?.toDouble(),
        contentHash: m['hash'] as String?,
      );

  /// MediaStore id. Unique per item, but images and videos have separate id spaces: see [key].
  final int id;
  final bool isVideo;

  /// Absolute file path (lower-cased copies are used for matching, see `classifier.dart`).
  final String path;
  final String bucket;
  final int size;

  /// `date_added` and `date_modified` in seconds, `date_taken` in milliseconds.
  final int addedSec;
  final int modifiedSec;
  final int takenMs;
  final int width;
  final int height;
  final int durationMs;
  final String mime;

  /// 64-bit difference hash of a photo, or null for videos and unreadable files.
  final int? dHash;

  /// Variance of the Laplacian on a 256 px grayscale copy. Low is blurry. Null for videos.
  final double? blur;

  /// SHA-256 of the whole file. Only set for files that could be exact duplicates.
  final String? contentHash;

  bool get isImage => !isVideo;
  int get pixels => width * height;
  DateTime get taken => DateTime.fromMillisecondsSinceEpoch(takenMs);

  /// Unique across photos and videos (their MediaStore ids can collide).
  int get key => isVideo ? -id - 1 : id;

  @override
  bool operator ==(Object other) => other is MediaItem && other.key == key;

  @override
  int get hashCode => key;
}

/// Total size in bytes of [items].
int totalBytes(Iterable<MediaItem> items) => items.fold(0, (sum, i) => sum + i.size);
