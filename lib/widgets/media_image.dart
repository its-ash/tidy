import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../media/media_item.dart';
import '../media/media_platform.dart';

/// A photo or video thumbnail loaded through the platform channel. Flutter's image cache keeps
/// the decoded bitmaps, so scrolling back is instant, and off-screen tiles never load.
@immutable
class MediaImage extends ImageProvider<MediaImage> {
  const MediaImage(this.platform, this.item, {this.size = 256});

  final MediaPlatform platform;
  final MediaItem item;

  /// Longest side in px.
  final int size;

  @override
  Future<MediaImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<MediaImage>(this);

  @override
  ImageStreamCompleter loadImage(MediaImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1,
      debugLabel: 'MediaImage(${item.key}, $size)',
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await platform.thumbnail(item.id, video: item.isVideo, size: size);
    if (bytes == null || bytes.isEmpty) throw StateError('No thumbnail for ${item.key}');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is MediaImage && other.item.key == item.key && other.size == size;

  @override
  int get hashCode => Object.hash(item.key, size);
}
