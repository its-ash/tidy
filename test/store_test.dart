import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidy/media/clutter_group.dart';
import 'package:tidy/media/media_item.dart';
import 'package:tidy/media/media_platform.dart';
import 'package:tidy/media/tidy_settings.dart';
import 'package:tidy/media/tidy_store.dart';

import 'test_helpers.dart';

class FakePlatform implements MediaPlatform {
  FakePlatform(this.items, {this.access = MediaAccess.full, this.sdk = 34});

  final List<MediaItem> items;
  MediaAccess access;
  final int sdk;
  bool? lastTrash;
  bool dialogCancelled = false;
  final _progress = StreamController<ScanProgress>.broadcast();

  @override
  Future<DeviceInfo> deviceInfo() async =>
      DeviceInfo(sdk: sdk, access: access, freeBytes: 40, totalBytes: 100);

  @override
  Future<bool> requestAccess(int sdk) async {
    access = MediaAccess.full;
    return false;
  }

  @override
  Stream<ScanProgress> get progress => _progress.stream;

  @override
  Future<List<MediaItem>> scan({bool force = false}) async => List.of(items);

  @override
  Future<void> cancelScan() async {}

  @override
  Future<Uint8List?> thumbnail(int id, {required bool video, int size = 256}) async => null;

  @override
  Future<DeleteResult> delete(List<MediaItem> toDelete, {required bool trash}) async {
    lastTrash = trash;
    if (dialogCancelled) return const DeleteResult(deleted: [], cancelled: true);
    final keys = toDelete.map((i) => i.key).toSet();
    items.removeWhere((i) => keys.contains(i.key));
    return DeleteResult(deleted: keys.toList(), cancelled: false);
  }

  @override
  Future<bool> open(MediaItem item) async => true;
}

void main() {
  final dupA = photo(1, size: 500, hash: 'h', added: 1);
  final dupB = photo(2, size: 500, hash: 'h', added: 2);
  final dupC = photo(3, size: 500, hash: 'h', added: 3);
  final shot = photo(4, size: 70, path: '/Pictures/Screenshots/s.png', dHash: 5, taken: 9999);

  Future<(TidyStore, FakePlatform)> ready({MediaAccess access = MediaAccess.full}) async {
    final platform = FakePlatform([dupA, dupB, dupC, shot], access: access);
    final store = TidyStore(platform: platform, settings: TidySettings());
    await store.refreshDevice();
    return (store, platform);
  }

  test('without access it asks for permission and does not scan', () async {
    final (store, _) = await ready(access: MediaAccess.none);
    expect(store.status, TidyStatus.needsPermission);
    expect(store.groups, isEmpty);
  });

  test('granting access scans and builds groups with totals', () async {
    final (store, _) = await ready(access: MediaAccess.none);
    await store.requestAccess();
    expect(store.status, TidyStatus.ready);
    expect(store.groups.map((g) => g.kind), [GroupKind.duplicates, GroupKind.screenshots]);
    expect(store.summary.count, 3); // two extra duplicates + the screenshot
    expect(store.summary.bytes, 500 + 500 + 70);
  });

  test('partial access is reported', () async {
    final (store, _) = await ready(access: MediaAccess.partial);
    expect(store.partialAccess, isTrue);
    expect(store.status, TidyStatus.ready);
  });

  test('opening a duplicates group selects all but the best; keepBest resets it', () async {
    final (store, _) = await ready();
    final group = store.group(GroupKind.duplicates)!;
    store.seed(group);
    expect(store.selectedIn(group.items).map((i) => i.id), unorderedEquals([2, 3]));
    expect(store.selectionState(group.items), isNull);

    store.setAll(group.items, true);
    expect(store.selectionState(group.items), isTrue);
    store.keepBest(group);
    expect(store.selectedIn(group.items).map((i) => i.id), unorderedEquals([2, 3]));
    store.setAll(group.items, false);
    expect(store.selectionState(group.items), isFalse);
  });

  test('delete reports freed bytes, updates groups and honours the trash setting', () async {
    final (store, platform) = await ready();
    final group = store.group(GroupKind.duplicates)!;
    final outcome = await store.delete([dupB, dupC]);
    expect(outcome.count, 2);
    expect(outcome.bytes, 1000);
    expect(outcome.trashed, isTrue); // default setting, Android 14
    expect(platform.lastTrash, isTrue);
    expect(store.group(GroupKind.duplicates), isNull); // one copy left, no longer a duplicate
    expect(store.summary.count, 1);
    expect(group.items, hasLength(3)); // old snapshot untouched
  });

  test('permanent delete when trash is off or unsupported', () async {
    final (store, platform) = await ready();
    await store.settings.setMoveToTrash(false);
    final outcome = await store.delete([shot]);
    expect(outcome.trashed, isFalse);
    expect(platform.lastTrash, isFalse);

    final old = FakePlatform([photo(9)], sdk: 29);
    final oldStore = TidyStore(platform: old, settings: TidySettings());
    await oldStore.refreshDevice();
    await oldStore.delete([photo(9)]);
    expect(old.lastTrash, isFalse);
  });

  test('a dismissed system dialog deletes nothing', () async {
    final (store, platform) = await ready();
    platform.dialogCancelled = true;
    final outcome = await store.delete([dupB]);
    expect(outcome.cancelled, isTrue);
    expect(outcome.count, 0);
    expect(store.group(GroupKind.duplicates)!.items, hasLength(3));
  });
}
