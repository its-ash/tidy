import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../media/grouping_options.dart';
import '../media/tidy_settings.dart';
import '../media/tidy_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});

  final TidyStore store;

  TidySettings get settings => store.settings;

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: const UiAppBar(title: 'Settings'),
      scrollable: true,
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, store]),
        builder: (context, _) {
          final canTrash = store.device?.supportsTrash ?? false;
          final options = settings.options;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiListGroup(
                header: 'Deleting',
                footer: canTrash
                    ? 'Trash keeps deleted files for 30 days so you can restore them from your gallery. Either way Android asks you to confirm.'
                    : 'Trash needs Android 11 or later. On this phone deleted files are removed permanently.',
                children: [
                  UiSwitchTile(
                    'Move to Trash',
                    subtitle: 'Instead of deleting permanently',
                    icon: Icons.delete_sweep_rounded,
                    value: canTrash && settings.moveToTrash,
                    onChanged: canTrash ? settings.setMoveToTrash : null,
                  ),
                ],
              ),
              const UiGap(UiSpace.lg),
              UiListGroup(
                header: 'Detection',
                footer: 'Changes apply right away, no rescan needed. Higher sensitivity flags more files.',
                children: [
                  UiListTile(
                    'Large videos',
                    subtitle: 'Videos at least this big',
                    icon: Icons.movie_rounded,
                    value: _mb(options.largeVideoBytes),
                    chevron: true,
                    onTap: () => _pickLargeVideo(context),
                  ),
                  UiListTile(
                    'Similar photos',
                    subtitle: 'Matches within ${_window(options.similarWindow)}',
                    icon: Icons.burst_mode_rounded,
                    value: options.similarity.label,
                    chevron: true,
                    onTap: () => _pickLevel(context, 'Similar photo sensitivity', options.similarity, settings.setSimilarity),
                  ),
                  UiListTile(
                    'Blurry photos',
                    subtitle: 'How soft a photo must be',
                    icon: Icons.blur_on_rounded,
                    value: options.blurriness.label,
                    chevron: true,
                    onTap: () => _pickLevel(context, 'Blur sensitivity', options.blurriness, settings.setBlurriness),
                  ),
                ],
              ),
              const UiGap(UiSpace.lg),
              UiListGroup(
                header: 'Library',
                footer: 'Tidy remembers what it learned about each photo, so rescans are fast. A full rescan ignores that memory.',
                children: [
                  UiListTile(
                    'Rescan everything',
                    icon: Icons.refresh_rounded,
                    chevron: true,
                    enabled: store.status != TidyStatus.scanning,
                    onTap: () => _rescan(context),
                  ),
                ],
              ),
              const UiGap(UiSpace.lg),
              const UiListGroup(
                header: 'Privacy',
                children: [
                  UiListTile(
                    'Your photos stay on this phone',
                    subtitle: 'Everything is analysed on the device. Tidy uses the internet only to check for app updates.',
                    icon: Icons.lock_rounded,
                    iconStatus: UiStatus.success,
                  ),
                ],
              ),
              const UiGap(UiSpace.lg),
              const UiUpdateSection(storeId: 'tidy'),
              const UiGap(UiSpace.lg),
              const UiDeveloperSection(),
            ],
          );
        },
      ),
    );
  }

  static String _mb(int bytes) {
    final mb = bytes ~/ GroupingOptions.megabyte;
    return mb >= 1000 ? '${mb ~/ 1000} GB' : '$mb MB';
  }

  static String _window(Duration d) => d.inMinutes == 1 ? '1 minute' : '${d.inMinutes} minutes';

  Future<void> _pickLargeVideo(BuildContext context) async {
    final mb = await UiActionSheet.show<int>(
      context,
      title: 'Large videos',
      message: 'Show videos at least this big',
      actions: [
        for (final v in TidySettings.largeVideoChoicesMb) UiSheetAction(_mb(v * GroupingOptions.megabyte), value: v),
      ],
    );
    if (mb != null) await settings.setLargeVideoMb(mb);
  }

  Future<void> _pickLevel(
    BuildContext context,
    String title,
    Sensitivity current,
    Future<void> Function(Sensitivity) apply,
  ) async {
    final level = await UiActionSheet.show<Sensitivity>(
      context,
      title: title,
      actions: [
        for (final l in Sensitivity.values)
          UiSheetAction(l.label, value: l, icon: l == current ? Icons.check_rounded : null),
      ],
    );
    if (level != null) await apply(level);
  }

  Future<void> _rescan(BuildContext context) async {
    final ok = await UiDialog.confirm(
      context,
      title: 'Rescan everything?',
      message: 'Tidy forgets what it learned and analyses every photo again. This can take a few minutes.',
      confirmLabel: 'Rescan',
      icon: Icons.refresh_rounded,
    );
    if (!ok || !context.mounted) return;
    Navigator.of(context).pop();
    await store.scan(force: true);
  }
}
