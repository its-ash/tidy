import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'grouping_options.dart';

/// User settings, persisted in `shared_preferences`.
class TidySettings extends ChangeNotifier {
  TidySettings({SharedPreferences? prefs}) {
    _prefs = prefs;
  }

  static const _kTrash = 'moveToTrash';
  static const _kLargeVideo = 'largeVideoBytes';
  static const _kSimilarity = 'similarity';
  static const _kBlur = 'blurriness';

  /// Sizes offered for "large video", in MB.
  static const largeVideoChoicesMb = [50, 100, 250, 500, 1000];

  SharedPreferences? _prefs;

  bool _moveToTrash = true;
  GroupingOptions _options = const GroupingOptions();

  /// Move deleted files to the trash (Android 11+) instead of deleting them permanently.
  bool get moveToTrash => _moveToTrash;
  GroupingOptions get options => _options;

  Future<void> load() async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    _moveToTrash = p.getBool(_kTrash) ?? true;
    _options = GroupingOptions(
      largeVideoBytes: p.getInt(_kLargeVideo) ?? GroupingOptions.defaultLargeVideoBytes,
      similarity: _level(p.getString(_kSimilarity)),
      blurriness: _level(p.getString(_kBlur)),
    );
    notifyListeners();
  }

  Sensitivity _level(String? name) => Sensitivity.values.asNameMap()[name] ?? Sensitivity.medium;

  Future<void> setMoveToTrash(bool value) async {
    _moveToTrash = value;
    notifyListeners();
    await _prefs?.setBool(_kTrash, value);
  }

  Future<void> setLargeVideoMb(int mb) async {
    _options = _options.copyWith(largeVideoBytes: mb * GroupingOptions.megabyte);
    notifyListeners();
    await _prefs?.setInt(_kLargeVideo, _options.largeVideoBytes);
  }

  Future<void> setSimilarity(Sensitivity level) async {
    _options = _options.copyWith(similarity: level);
    notifyListeners();
    await _prefs?.setString(_kSimilarity, level.name);
  }

  Future<void> setBlurriness(Sensitivity level) async {
    _options = _options.copyWith(blurriness: level);
    notifyListeners();
    await _prefs?.setString(_kBlur, level.name);
  }
}
