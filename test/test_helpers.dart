import 'package:tidy/media/media_item.dart';

/// A photo with sensible defaults for tests. [taken] is in seconds to keep tests short.
MediaItem photo(
  int id, {
  String path = '/storage/emulated/0/DCIM/Camera/IMG.jpg',
  int size = 1000,
  int taken = 1000,
  int added = 1000,
  int w = 4000,
  int h = 3000,
  int? dHash = 0,
  double? blur = 500,
  String? hash,
}) =>
    MediaItem(
      id: id,
      isVideo: false,
      path: path,
      size: size,
      takenMs: taken * 1000,
      addedSec: added,
      width: w,
      height: h,
      dHash: dHash,
      blur: blur,
      contentHash: hash,
    );

MediaItem video(int id, {String path = '/storage/emulated/0/DCIM/Camera/VID.mp4', int size = 1000, int added = 1000}) =>
    MediaItem(id: id, isVideo: true, path: path, size: size, addedSec: added, takenMs: added * 1000, durationMs: 60000);
