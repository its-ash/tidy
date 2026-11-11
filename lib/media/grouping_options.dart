/// How eagerly a detector flags files. Higher flags more.
enum Sensitivity {
  low('Low'),
  medium('Medium'),
  high('High');

  const Sensitivity(this.label);

  final String label;
}

/// Thresholds used to build the clutter groups. Plain data so it can cross isolates.
class GroupingOptions {
  const GroupingOptions({
    this.largeVideoBytes = defaultLargeVideoBytes,
    this.similarity = Sensitivity.medium,
    this.blurriness = Sensitivity.medium,
    this.oldDownloadDays = 90,
  });

  static const int megabyte = 1024 * 1024;
  static const int defaultLargeVideoBytes = 100 * megabyte;

  /// Videos at least this big are "large".
  final int largeVideoBytes;
  final Sensitivity similarity;
  final Sensitivity blurriness;

  /// Images in Download older than this many days are "old downloads".
  final int oldDownloadDays;

  /// Max Hamming distance between two dHashes to call photos similar.
  ///
  /// 64-bit dHash: identical shots are 0-2 bits apart, a burst with small motion 3-6, and unrelated
  /// photos are about 32 apart on average, so even 10 leaves a wide margin.
  int get maxHamming => switch (similarity) {
        Sensitivity.low => 4,
        Sensitivity.medium => 6,
        Sensitivity.high => 10,
      };

  /// Photos must be taken within this window to be compared (bursts, retakes).
  Duration get similarWindow => switch (similarity) {
        Sensitivity.low => const Duration(minutes: 1),
        Sensitivity.medium => const Duration(minutes: 2),
        Sensitivity.high => const Duration(minutes: 10),
      };

  /// Photos with a Laplacian variance below this (on a 256 px grayscale copy) are blurry.
  ///
  /// Chosen empirically: at 256 px a sharp, detailed photo scores in the hundreds, a normal photo
  /// of a plain scene 60-150, and a clearly out-of-focus or motion-blurred one under about 40.
  /// Medium (60) flags clear blur while leaving soft but intentional shots (sky, bokeh) alone.
  double get blurThreshold => switch (blurriness) {
        Sensitivity.low => 30,
        Sensitivity.medium => 60,
        Sensitivity.high => 100,
      };

  /// Photos smaller than this on the long side (icons, stickers, thumbnails) are never "blurry".
  static const int minBlurSide = 300;

  GroupingOptions copyWith({
    int? largeVideoBytes,
    Sensitivity? similarity,
    Sensitivity? blurriness,
  }) =>
      GroupingOptions(
        largeVideoBytes: largeVideoBytes ?? this.largeVideoBytes,
        similarity: similarity ?? this.similarity,
        blurriness: blurriness ?? this.blurriness,
        oldDownloadDays: oldDownloadDays,
      );
}
