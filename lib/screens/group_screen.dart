import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../media/clutter_group.dart';
import '../media/media_item.dart';
import '../media/tidy_store.dart';
import '../widgets/group_style.dart';
import '../widgets/media_image.dart';
import '../widgets/media_tile.dart';
import 'delete_flow.dart';

/// Review one kind of clutter: a grid with selection, preview and a Delete bar.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.store, required this.kind});

  final TidyStore store;
  final GroupKind kind;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  TidyStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    final group = store.group(widget.kind);
    if (group != null) store.seed(group);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final group = store.group(widget.kind);
        final kind = widget.kind;
        if (group == null) {
          return UiScaffold(
            appBar: UiAppBar(title: kind.title),
            body: UiEmptyState(icon: kind.icon, title: 'All clear', message: 'Nothing left in this group.'),
          );
        }
        final picked = store.selectedIn(group.items);
        return UiScaffold(
          appBar: UiAppBar(
            title: kind.title,
            subtitle: '${group.summary} · ${UiFormat.bytes(group.reclaimableBytes)}',
            actions: [
              if (group.isClustered)
                UiIconButton(
                  Icons.auto_fix_high_rounded,
                  tooltip: 'Keep the best of each set',
                  onPressed: () => store.keepBest(group),
                ),
            ],
          ),
          padding: EdgeInsets.zero,
          body: group.isClustered ? _clusters(context, group) : _grid(context, group),
          bottomBar: UiBottomBar(
            children: [
              UiCheckbox(
                store.selectionState(group.items),
                tristate: true,
                label: 'Select all',
                onChanged: (_) => store.setAll(group.items, store.selectionState(group.items) != true),
              ),
              UiButton(
                picked.isEmpty ? 'Delete' : 'Delete ${picked.length} (${UiFormat.bytes(totalBytes(picked))})',
                icon: Icons.delete_rounded,
                variant: UiButtonVariant.danger,
                loading: store.deleting,
                onPressed: picked.isEmpty ? null : () => confirmAndDelete(context, store, picked),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(List<MediaItem> list, MediaItem item, {bool isBest = false}) => MediaTile(
        platform: store.platform,
        item: item,
        selected: store.isSelected(item),
        isBest: isBest,
        onToggle: () => store.toggle(item),
        onPreview: () => _preview(list, item),
      );

  Widget _grid(BuildContext context, ClutterGroup group) {
    final items = group.items;
    return GridView.builder(
      padding: const EdgeInsets.all(UiSpace.xs),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 124,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _tile(items, items[i]),
    );
  }

  Widget _clusters(BuildContext context, ClutterGroup group) {
    final clusters = group.clusters;
    final text = context.text;
    final colors = context.colors;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(UiSpace.sm, UiSpace.sm, UiSpace.sm, UiSpace.xl),
      itemCount: clusters.length,
      itemBuilder: (context, i) {
        final cluster = clusters[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: UiSpace.sm),
          child: UiCard(
            padding: const EdgeInsets.all(UiSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: UiSpace.xs),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: 'Set ${i + 1}', style: text.titleSmall),
                              TextSpan(
                                text: '  ${cluster.items.length} files, frees ${UiFormat.bytes(totalBytes(cluster.extras))}',
                                style: text.bodySmall?.copyWith(color: colors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    UiButton(
                      'Keep best',
                      size: UiSize.sm,
                      variant: UiButtonVariant.ghost,
                      onPressed: () => store.keepBestOf(cluster),
                    ),
                  ],
                ),
                const UiGap(UiSpace.xs),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: 3,
                  crossAxisSpacing: 3,
                  children: [for (final item in cluster.items) _tile(cluster.items, item, isBest: item == cluster.best)],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Photos open in the full-screen viewer (swipe through the list); videos open in the gallery app.
  void _preview(List<MediaItem> list, MediaItem item) {
    if (item.isVideo) {
      store.platform.open(item);
      return;
    }
    final photos = [for (final i in list) if (i.isImage) i];
    UiImageViewer.show(
      context,
      images: [for (final i in photos) MediaImage(store.platform, i, size: 1600)],
      initialIndex: photos.indexOf(item),
    );
  }
}
