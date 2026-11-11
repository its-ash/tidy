# Tidy

Clean your gallery: duplicates, similar shots, blurry photos, screenshots and big videos.

**[Website](https://tidy.itsash.in)** · **[Download APK](https://github.com/its-ash/tidy/releases/latest/download/tidy.apk)** · Get it in **[Ash Store](https://store.itsash.in)**

## Features

- **Finds clutter** in your photos and videos and groups it:
  - **Duplicates**: identical files (same size and same content hash), keeping the oldest copy.
  - **Similar photos**: bursts and retakes taken within minutes of each other. Tidy keeps the sharpest, highest resolution shot and pre-selects the rest.
  - **Blurry photos**: out-of-focus or shaky shots.
  - **Screenshots**: screenshots and screen recordings.
  - **WhatsApp & messaging**: WhatsApp, WhatsApp Business, Telegram and Signal photos, videos and GIFs.
  - **Large videos**: videos over a size you choose (100 MB by default), biggest first.
  - **Old downloads**: images in Downloads older than 90 days.
- **Review before you delete**: every group opens a grid with checkboxes, Select all, "Keep best" for similar sets, and a full-screen preview. The bottom bar shows "Delete N (X MB)".
- **One confirmation**: Android 11+ asks once for the whole batch. Files can go to **Trash** (restorable for 30 days) or be deleted permanently.
- **Fast on big galleries**: analysis runs natively on background threads and is cached, so a 20,000 photo library is only fully analysed once.
- **Private**: everything is analysed on your phone. The only network call is the update check in Settings.

## Install

- **Ash Store**: install [Ash Store](https://store.itsash.in) once, then install and update Tidy from it.
- **APK**: download the [latest APK](https://github.com/its-ash/tidy/releases/latest/download/tidy.apk) on your phone and open it. Allow your browser to install unknown apps if Android asks.

Requires Android 8.0 (API 26) or later. Tidy asks for access to photos and videos. On Android 14 you can share only selected photos, but then Tidy sees just those, so choose "Allow all" for a full scan.

## Develop

Needs Flutter ≥ 3.44 and the shared theme package at `../theme`.

```bash
make run          # run on a connected device
make test         # flutter analyze + flutter test
make test-native  # Kotlin JVM tests (image metrics, content hashes)
make build        # release APK
make deploy       # bump version, build, tag, push, GitHub release (see store.mk)
```

## Release

`make deploy` follows the Ash Store kit (`store.mk`, `store.json`): it bumps the
version in `pubspec.yaml`, builds, commits, tags `vX.Y.Z`, pushes, and publishes
a GitHub release with `tidy.apk`. Ash Store and the website pick up the new
version from that release.

## Project layout

```
lib/
├── main.dart                     # UiApp + HomeScreen
├── media/
│   ├── media_item.dart           # one photo/video + native analysis results
│   ├── classifier.dart           # screenshot / messaging / download path rules
│   ├── hashing.dart              # Hamming distance of 64-bit dHashes
│   ├── grouping.dart             # duplicates, similar, blurry, large, old (pure)
│   ├── grouping_options.dart     # thresholds and sensitivities
│   ├── clutter_group.dart        # groups, clusters, totals
│   ├── media_platform.dart       # MethodChannel / EventChannel to MainActivity.kt
│   ├── tidy_store.dart           # access, scan, groups, selection, delete
│   └── tidy_settings.dart        # persisted settings
├── screens/
│   ├── home_screen.dart          # storage, Scan, progress, groups
│   ├── group_screen.dart         # review grid, selection, Delete bar
│   ├── delete_flow.dart          # confirm → delete / trash → freed space
│   └── settings_screen.dart
└── widgets/                      # thumbnail provider, tile, group icons and text
android/app/src/main/kotlin/com/itsash/tidy/
├── MainActivity.kt               # channels
├── MediaQuery.kt                 # MediaStore listing
├── Scanner.kt                    # analysis + duplicate hashing pipeline
├── ImageMetrics.kt               # dHash, blur score (pure, tested)
├── ContentHash.kt                # partial and full file hashes (pure, tested)
├── AnalysisCache.kt              # SQLite cache keyed by id + date_modified
├── Thumbnails.kt                 # loadThumbnail / decode fallbacks
└── DeleteCoordinator.kt          # createDeleteRequest / createTrashRequest / legacy delete
```

See `CLAUDE.md` for details.

## License

No license file is included yet.

Built by [itsash.in](https://itsash.in).
