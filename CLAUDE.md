# Tidy (package: tidy / com.itsash.tidy)

Android gallery cleaner. Scans photos and videos from MediaStore, groups the clutter
(duplicates, similar photos, blurry, screenshots, messaging media, large videos, old
downloads) and deletes it by group after review. Everything runs on the phone.

## How it works

1. **Native scan** (`Scanner.kt`, on background threads, 2 to 4 workers): `MediaQuery` lists
   every image and video row; new or changed images (not in the cache) get a thumbnail
   (`loadThumbnail` on API 29+, `inSampleSize` decode below), scaled to at most 256 px,
   converted to gray, and scored: 64-bit **dHash** (9x8 box average) and **blur score**
   (variance of the 3x3 Laplacian). Duplicate hashing runs for files with the same size:
   SHA-1 of size + first/last 64 KB, then SHA-256 of the whole file only for those that
   still collide. Results are cached in SQLite (`AnalysisCache`, key = MediaStore id,
   valid while `date_modified` and `size` match), so a rescan only touches new files.
2. **Grouping** (`lib/media/grouping.dart`, pure Dart, run in `Isolate.run`): builds the
   groups from the scanned items. Settings changes regroup instantly without a rescan.
3. **Review** (`group_screen.dart`): clustered groups (duplicates, similar) show one card per
   set with the best file marked and the others pre-selected; flat groups are a grid.
   Tap = select, long-press or corner button = preview (`UiImageViewer`; videos open in the gallery app).
4. **Delete** (`DeleteCoordinator.kt`): Android 11+ `MediaStore.createDeleteRequest` or
   `createTrashRequest` (setting "Move to Trash"), one system dialog per chunk of 1000 files;
   Android 10 and below `ContentResolver.delete` (with `RecoverableSecurityException`
   handling; `requestLegacyExternalStorage` is on so Android 10 deletes without prompts).

## Thresholds (`lib/media/grouping_options.dart`)

| Setting | Low / Medium (default) / High |
|---|---|
| Similar: max Hamming distance | 4 / **6** / 10 bits of 64 |
| Similar: time window | 1 / **2** / 10 min between photos taken |
| Blurry: Laplacian variance below | 30 / **60** / 100 (on 256 px gray) |
| Large videos | 50 / **100** / 250 / 500 / 1000 MB |
| Old downloads | images in `/Download/` older than 90 days (by `date_added`) |

Blur threshold choice: at 256 px a detailed sharp photo scores in the hundreds and a plain
scene 60 to 150; clear out-of-focus or motion blur is under about 40. 60 flags clear blur and
leaves soft but intentional shots alone. Screenshots and images with both sides under 300 px
are never "blurry". Screenshots are never "similar". Extra copies of exact duplicates are left
out of "similar". Each photo is compared with at most 150 neighbours in the window.
Best of a cluster: the sharpest among photos with at least 90% of the top resolution, then the
larger file. Best of duplicates: earliest `date_added`, then the shortest path.

## Channel contract

MethodChannel `com.itsash.tidy/media` (`lib/media/media_platform.dart` <-> `MainActivity.kt`):

- `deviceInfo()` -> `{sdk, access: full|partial|none, freeBytes, totalBytes}`. `partial` = Android 14
  "selected photos" or only one of images/videos granted.
- `startScan({force})` -> list of `{id, video, path, bucket, size, added(s), modified(s), taken(ms),
  width, height, duration(ms), mime, dhash (int64|null), blur (double|null), hash (sha256|null)}`.
  Error code `cancelled` after `cancelScan()`. `force` clears the cache first.
- `cancelScan()`; `thumbnail({id, video, size})` -> JPEG bytes or null; `open({id, video})`.
- `delete({items: [{id, video}], trash})` -> `{deleted: [keys], cancelled}`. A key is `id` for photos
  and `-id-1` for videos (`MediaItem.key`), because photo and video ids can collide.

EventChannel `com.itsash.tidy/progress`: `{phase: listing|analyzing|hashing, done, total}`.

Permissions are requested from Dart with `permission_handler` (`Permission.photos` + `videos` on
API 33+, `storage` below); the manifest also declares `READ_MEDIA_VISUAL_USER_SELECTED`.

## Code layout

See the tree in `README.md`. Pure logic (`grouping.dart`, `classifier.dart`, `hashing.dart`,
`ImageMetrics.kt`, `ContentHash.kt`) has no Android or Flutter dependencies and is unit-tested.
`TidyStore` takes a `MediaPlatform`, so tests use a fake.

## Commands

- `make run`, `make build` (release APK), `make test` (`flutter analyze` + `flutter test`),
  `make test-native` (Kotlin JVM tests with Flutter's JDK), `make clean`.
- Icon: SVG sources in `assets/icon/` (`logo`, `logo_foreground`, `logo_background`) ->
  `rsvg-convert -w 1024 -h 1024` to `*-1024.png`, then `dart run flutter_launcher_icons`.

## Conventions

- minSdk 26. UI only from the shared `theme` package (`../theme`, read `../theme/COMPONENTS.md`);
  no hardcoded colors.
- Only network use: `UiUpdateSection` in Settings (needs `INTERNET`). No analytics or telemetry.
- Settings ends with `UiUpdateSection(storeId: 'tidy')` then `UiDeveloperSection()`.

## Release (Ash Store)

- `store.json` (id `tidy`, repo its-ash/tidy), `store.mk`, `index.html` + `CNAME`
  (`tidy.itsash.in`). See `../ash-store/store-kit/STORE.md`.
- `make deploy` = bump version -> build -> commit, tag `vX.Y.Z`, push -> GitHub release with
  `tidy.apk` -> topics, homepage, Pages. Never create releases, tags or asset names by hand.
- Do not edit `store.mk` here. Edit `../ash-store/store-kit/store.mk`, then run
  `make store-sync` at the workspace root.
