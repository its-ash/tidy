import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'clutter_group.dart';
import 'grouping.dart';
import 'media_item.dart';
import 'media_platform.dart';
import 'tidy_settings.dart';

enum TidyStatus { loading, needsPermission, permanentlyDenied, idle, scanning, ready, error }

/// What a delete did, for the confirmation message.
class DeleteOutcome {
  const DeleteOutcome({required this.count, required this.bytes, required this.cancelled, required this.trashed});

  final int count;
  final int bytes;
  final bool cancelled;
  final bool trashed;
}

/// App state: gallery access, the scan, the clutter groups and the selection.
class TidyStore extends ChangeNotifier {
  TidyStore({required this.platform, required this.settings}) {
    settings.addListener(_onSettings);
  }

  final MediaPlatform platform;
  final TidySettings settings;

  TidyStatus status = TidyStatus.loading;
  DeviceInfo? device;
  ScanProgress? progress;
  String? error;

  List<MediaItem> _items = const [];
  List<ClutterGroup> _groups = const [];
  ClutterSummary _summary = const ClutterSummary(0, 0);

  final Set<int> _selected = {};
  final Set<GroupKind> _seeded = {};
  bool deleting = false;
  int _regroupRun = 0;
  MediaAccess? _lastAccess;

  List<ClutterGroup> get groups => _groups;
  ClutterSummary get summary => _summary;
  int get itemCount => _items.length;
  bool get hasScanned => status == TidyStatus.ready;

  /// True when only some photos are readable (Android 14 "selected photos").
  bool get partialAccess => device?.access == MediaAccess.partial;

  ClutterGroup? group(GroupKind kind) {
    for (final g in _groups) {
      if (g.kind == kind) return g;
    }
    return null;
  }

  // ---- access and scan ----

  Future<void> init() async {
    await settings.load();
    await refreshDevice();
  }

  /// Re-reads storage and permission state; scans when access has just been granted or widened.
  Future<void> refreshDevice() async {
    final info = await platform.deviceInfo();
    device = info;
    final widened = _lastAccess != null && _lastAccess != info.access && info.access == MediaAccess.full;
    _lastAccess = info.access;
    if (info.access == MediaAccess.none) {
      if (status != TidyStatus.permanentlyDenied && status != TidyStatus.scanning) status = TidyStatus.needsPermission;
    } else if (status == TidyStatus.loading || status == TidyStatus.needsPermission || status == TidyStatus.permanentlyDenied) {
      notifyListeners();
      await scan();
      return;
    } else if (widened && status == TidyStatus.ready) {
      notifyListeners();
      await scan();
      return;
    }
    notifyListeners();
  }

  /// Shows the system permission dialog. Returns the access level afterwards.
  Future<MediaAccess> requestAccess() async {
    final permanent = await platform.requestAccess(device?.sdk ?? 0);
    await refreshDevice();
    if (device?.access == MediaAccess.none && permanent) {
      status = TidyStatus.permanentlyDenied;
      notifyListeners();
    }
    return device?.access ?? MediaAccess.none;
  }

  Future<void> scan({bool force = false}) async {
    if (status == TidyStatus.scanning) return;
    status = TidyStatus.scanning;
    progress = null;
    error = null;
    _selected.clear();
    notifyListeners();
    final sub = platform.progress.listen((p) {
      progress = p;
      notifyListeners();
    });
    try {
      _items = await platform.scan(force: force);
      await _regroup();
      status = TidyStatus.ready;
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') {
        status = _items.isEmpty ? TidyStatus.idle : TidyStatus.ready;
      } else {
        error = e.message ?? 'The scan failed.';
        status = TidyStatus.error;
      }
    } finally {
      await sub.cancel();
      progress = null;
      unawaited(_refreshStorage());
      notifyListeners();
    }
  }

  Future<void> cancelScan() => platform.cancelScan();

  Future<void> _refreshStorage() async {
    try {
      device = await platform.deviceInfo();
      notifyListeners();
    } on PlatformException {
      // Storage numbers are cosmetic.
    }
  }

  // ---- groups ----

  void _onSettings() {
    if (_items.isNotEmpty) unawaited(_regroup().then((_) => notifyListeners()));
  }

  /// Rebuilds the groups from the scanned items in a background isolate.
  Future<void> _regroup() async {
    final run = ++_regroupRun;
    final items = _items;
    final options = settings.options;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final groups = await Isolate.run(() => buildGroups(items, options, nowSec: now));
    if (run != _regroupRun) return;
    _groups = groups;
    _summary = ClutterSummary.of(groups);
    _seeded.clear();
    final present = {for (final i in _items) i.key};
    _selected.removeWhere((k) => !present.contains(k));
  }

  // ---- selection ----

  bool isSelected(MediaItem item) => _selected.contains(item.key);

  List<MediaItem> selectedIn(Iterable<MediaItem> items) => [for (final i in items) if (_selected.contains(i.key)) i];

  /// For a tristate checkbox: true = all selected, false = none, null = some.
  bool? selectionState(Iterable<MediaItem> items) {
    var n = 0;
    var picked = 0;
    for (final i in items) {
      n++;
      if (_selected.contains(i.key)) picked++;
    }
    if (picked == 0) return false;
    return picked == n ? true : null;
  }

  void toggle(MediaItem item) {
    if (!_selected.remove(item.key)) _selected.add(item.key);
    notifyListeners();
  }

  void setAll(Iterable<MediaItem> items, bool selected) {
    for (final i in items) {
      selected ? _selected.add(i.key) : _selected.remove(i.key);
    }
    notifyListeners();
  }

  /// Selects everything but the best file of each cluster in [group], and nothing else in it.
  void keepBest(ClutterGroup group) {
    for (final i in group.items) {
      _selected.remove(i.key);
    }
    for (final i in group.reclaimable) {
      _selected.add(i.key);
    }
    notifyListeners();
  }

  /// Selects everything but the best file of one [cluster].
  void keepBestOf(MediaCluster cluster) {
    for (final i in cluster.items) {
      _selected.remove(i.key);
    }
    for (final i in cluster.extras) {
      _selected.add(i.key);
    }
    notifyListeners();
  }

  /// Pre-selects the suggested files of a clustered group, once per scan.
  void seed(ClutterGroup group) {
    if (!group.isClustered || !_seeded.add(group.kind)) return;
    for (final i in group.reclaimable) {
      _selected.add(i.key);
    }
  }

  // ---- delete ----

  /// Deletes (or trashes, per the setting) [items] and updates the groups.
  /// Throws [PlatformException] when Android refuses.
  Future<DeleteOutcome> delete(List<MediaItem> items) async {
    final trash = settings.moveToTrash && (device?.supportsTrash ?? false);
    deleting = true;
    notifyListeners();
    try {
      final result = await platform.delete(items, trash: trash);
      final removed = result.deleted.toSet();
      final bytes = totalBytes(items.where((i) => removed.contains(i.key)));
      if (removed.isNotEmpty) {
        _items = [for (final i in _items) if (!removed.contains(i.key)) i];
        _selected.removeAll(removed);
        await _regroup();
        unawaited(_refreshStorage());
      }
      return DeleteOutcome(count: removed.length, bytes: bytes, cancelled: result.cancelled, trashed: trash);
    } finally {
      deleting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    super.dispose();
  }
}
