import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'media_item.dart';

/// How much of the gallery Tidy may read.
enum MediaAccess {
  /// All photos and videos.
  full,

  /// Android 14 "selected photos" (or only photos or only videos). Scanning works but is incomplete.
  partial,
  none,
}

class DeviceInfo {
  const DeviceInfo({required this.sdk, required this.access, required this.freeBytes, required this.totalBytes});

  final int sdk;
  final MediaAccess access;
  final int freeBytes;
  final int totalBytes;

  int get usedBytes => totalBytes - freeBytes;
  double get usedFraction => totalBytes <= 0 ? 0 : usedBytes / totalBytes;

  /// Trash (`createTrashRequest`) exists from Android 11.
  bool get supportsTrash => sdk >= 30;
}

class ScanProgress {
  const ScanProgress(this.phase, this.done, this.total);

  /// `listing`, `analyzing` or `hashing`.
  final String phase;
  final int done;
  final int total;

  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);
}

class DeleteResult {
  const DeleteResult({required this.deleted, required this.cancelled});

  /// `MediaItem.key` of every file that was removed.
  final List<int> deleted;

  /// The user dismissed the system confirmation.
  final bool cancelled;
}

/// Everything Tidy needs from Android. [ChannelMediaPlatform] is the real one; tests use fakes.
abstract class MediaPlatform {
  Future<DeviceInfo> deviceInfo();

  /// Asks for gallery access. Returns true when the user chose "don't ask again" (open settings).
  Future<bool> requestAccess(int sdk);

  Stream<ScanProgress> get progress;
  /// Scans the gallery. [force] ignores the analysis cache.
  Future<List<MediaItem>> scan({bool force = false});
  Future<void> cancelScan();
  Future<Uint8List?> thumbnail(int id, {required bool video, int size = 256});
  Future<DeleteResult> delete(List<MediaItem> items, {required bool trash});
  Future<bool> open(MediaItem item);
}

/// MethodChannel `com.itsash.tidy/media` and EventChannel `com.itsash.tidy/progress`
/// (see `MainActivity.kt`).
class ChannelMediaPlatform implements MediaPlatform {
  static const _method = MethodChannel('com.itsash.tidy/media');
  static const _events = EventChannel('com.itsash.tidy/progress');

  @override
  Future<DeviceInfo> deviceInfo() async {
    final m = (await _method.invokeMapMethod<String, Object?>('deviceInfo'))!;
    return DeviceInfo(
      sdk: m['sdk']! as int,
      access: MediaAccess.values.asNameMap()[m['access']] ?? MediaAccess.none,
      freeBytes: (m['freeBytes']! as num).toInt(),
      totalBytes: (m['totalBytes']! as num).toInt(),
    );
  }

  @override
  Future<bool> requestAccess(int sdk) async {
    final permissions = sdk >= 33 ? [Permission.photos, Permission.videos] : [Permission.storage];
    final results = await permissions.request();
    return results.values.any((s) => s.isPermanentlyDenied);
  }

  @override
  Stream<ScanProgress> get progress => _events.receiveBroadcastStream().map((e) {
        final m = e as Map<Object?, Object?>;
        return ScanProgress(m['phase']! as String, (m['done']! as num).toInt(), (m['total']! as num).toInt());
      });

  @override
  Future<List<MediaItem>> scan({bool force = false}) async {
    final rows = await _method.invokeListMethod<Map<Object?, Object?>>('startScan', {'force': force});
    return [for (final m in rows ?? const <Map<Object?, Object?>>[]) MediaItem.fromMap(m)];
  }

  @override
  Future<void> cancelScan() => _method.invokeMethod<void>('cancelScan');

  @override
  Future<Uint8List?> thumbnail(int id, {required bool video, int size = 256}) =>
      _method.invokeMethod<Uint8List>('thumbnail', {'id': id, 'video': video, 'size': size});

  @override
  Future<DeleteResult> delete(List<MediaItem> items, {required bool trash}) async {
    final m = (await _method.invokeMapMethod<String, Object?>('delete', {
      'items': [for (final i in items) {'id': i.id, 'video': i.isVideo}],
      'trash': trash,
    }))!;
    return DeleteResult(
      deleted: [for (final id in m['deleted']! as List<Object?>) (id! as num).toInt()],
      cancelled: m['cancelled'] == true,
    );
  }

  @override
  Future<bool> open(MediaItem item) async =>
      await _method.invokeMethod<bool>('open', {'id': item.id, 'video': item.isVideo}) ?? false;
}
