import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:theme/theme.dart';

import '../media/clutter_group.dart';
import '../media/media_platform.dart';
import '../media/tidy_store.dart';
import '../widgets/group_style.dart';
import 'group_screen.dart';
import 'settings_screen.dart';

/// Storage, a Scan button with progress, and the clutter groups.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final TidyStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppLifecycleListener _lifecycle;

  TidyStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.init();
    // Back from the permission dialog or Android settings.
    _lifecycle = AppLifecycleListener(onResume: store.refreshDevice);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _allowFullAccess() async {
    final access = await store.requestAccess();
    if (access == MediaAccess.partial) await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => UiScaffold(
        appBar: UiAppBar(
          title: 'Tidy',
          actions: [UiIconButton(Icons.settings_rounded, tooltip: 'Settings', onPressed: () => _push(SettingsScreen(store: store)))],
        ),
        padding: EdgeInsets.zero,
        body: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (store.status) {
      case TidyStatus.loading:
        return const Center(child: UiSpinner(size: 28));
      case TidyStatus.needsPermission:
        return UiEmptyState(
          icon: Icons.photo_library_rounded,
          title: 'Allow gallery access',
          message:
              'Tidy looks through your photos and videos to find duplicates, blurry shots and other clutter. '
              'Everything is checked on this phone and nothing is uploaded.',
          action: UiButton('Allow access', icon: Icons.lock_open_rounded, onPressed: store.requestAccess),
        );
      case TidyStatus.permanentlyDenied:
        return const UiEmptyState(
          icon: Icons.no_photography_rounded,
          title: 'Gallery access is off',
          message: 'Turn on Photos and videos for Tidy in Android settings, then come back.',
          action: UiButton('Open app settings', icon: Icons.open_in_new_rounded, onPressed: openAppSettings),
        );
      case TidyStatus.error:
        return UiErrorState(message: store.error ?? 'The scan failed.', onRetry: store.scan);
      case TidyStatus.idle:
      case TidyStatus.scanning:
      case TidyStatus.ready:
        return _dashboard(context);
    }
  }

  Widget _dashboard(BuildContext context) {
    final pad = UiContent.pagePadding(context);
    final scanning = store.status == TidyStatus.scanning;
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, UiSpace.lg, pad, UiSpace.xl),
      children: [
        if (store.partialAccess) ...[
          UiBanner(
            'Tidy can only see the photos you selected, so the results are incomplete. Allow all photos and videos for a full scan.',
            status: UiStatus.warning,
            actionLabel: 'Allow all',
            onAction: _allowFullAccess,
          ),
          const UiGap(UiSpace.lg),
        ],
        _summaryCard(context),
        const UiGap(UiSpace.lg),
        if (scanning) _progress(context) else _scanButton(),
        const UiGap(UiSpace.lg),
        if (!scanning && store.status == TidyStatus.ready) _groups(context),
      ],
    );
  }

  Widget _summaryCard(BuildContext context) {
    final text = context.text;
    final colors = context.colors;
    final summary = store.summary;
    final device = store.device;
    final ready = store.status == TidyStatus.ready;
    return UiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ready ? UiFormat.bytes(summary.bytes) : '—',
            style: text.displaySmall?.copyWith(color: ready && summary.bytes > 0 ? colors.accent : colors.text),
          ),
          const UiGap(UiSpace.xs),
          Text(
            ready
                ? summary.count == 0
                    ? 'Nothing to clean up. Your gallery is tidy.'
                    : '${UiFormat.compact(summary.count)} files you can clear'
                : 'Scan to find clutter in your gallery',
            style: text.bodyMedium?.copyWith(color: colors.textMuted),
          ),
          if (device != null && device.totalBytes > 0) ...[
            const UiGap(UiSpace.lg),
            UiProgressBar(device.usedFraction, label: 'Storage', showPercent: true),
            const UiGap(UiSpace.xs),
            Text(
              '${UiFormat.bytes(device.usedBytes)} used of ${UiFormat.bytes(device.totalBytes)} · ${UiFormat.bytes(device.freeBytes)} free',
              style: text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _scanButton() {
    final scanned = store.status == TidyStatus.ready;
    return UiButton(
      scanned ? 'Scan again' : 'Scan gallery',
      icon: Icons.radar_rounded,
      variant: scanned ? UiButtonVariant.soft : UiButtonVariant.primary,
      expand: true,
      onPressed: store.scan,
    );
  }

  Widget _progress(BuildContext context) {
    final p = store.progress;
    final (label, detail) = switch (p?.phase) {
      'analyzing' => ('Analysing photos', '${UiFormat.compact(p!.done)} of ${UiFormat.compact(p.total)}'),
      'hashing' => ('Looking for duplicates', p!.total == 0 ? '' : '${UiFormat.compact(p.done)} of ${UiFormat.compact(p.total)}'),
      _ => ('Reading your gallery', ''),
    };
    return UiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiProgressBar(p?.fraction, label: detail.isEmpty ? label : '$label · $detail', showPercent: p?.fraction != null),
          const UiGap(UiSpace.xs),
          Text(
            'The first scan of a big gallery takes a while. Later scans only check new photos.',
            style: context.text.bodySmall,
          ),
          const UiGap(UiSpace.md),
          UiButton('Cancel', variant: UiButtonVariant.ghost, onPressed: store.cancelScan),
        ],
      ),
    );
  }

  Widget _groups(BuildContext context) {
    final groups = store.groups;
    if (groups.isEmpty) {
      return const UiEmptyState(
        icon: Icons.check_circle_rounded,
        title: 'All tidy',
        message: 'No duplicates, blurry photos or other clutter found.',
        compact: true,
      );
    }
    return UiListGroup(
      header: 'Clutter',
      children: [for (final g in groups) _tile(g)],
    );
  }

  Widget _tile(ClutterGroup g) => UiListTile(
        g.kind.title,
        subtitle: '${g.summary} · ${g.kind.description}',
        icon: g.kind.icon,
        iconStatus: g.kind.status,
        value: UiFormat.bytes(g.reclaimableBytes),
        chevron: true,
        onTap: () => _push(GroupScreen(store: store, kind: g.kind)),
      );
}
