import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../media/media_item.dart';
import '../media/media_platform.dart';
import 'media_image.dart';

/// One thumbnail in a review grid: tap to select, long-press or the corner button to preview.
class MediaTile extends StatelessWidget {
  const MediaTile({
    super.key,
    required this.platform,
    required this.item,
    required this.selected,
    required this.onToggle,
    required this.onPreview,
    this.isBest = false,
    this.caption,
  });

  final MediaPlatform platform;
  final MediaItem item;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onPreview;

  /// Marks the file Tidy suggests keeping.
  final bool isBest;

  /// Small text at the bottom, e.g. the file size. Defaults to the size.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      label: '${item.isVideo ? 'Video' : 'Photo'}, ${UiFormat.bytes(item.size)}',
      child: GestureDetector(
        onTap: onToggle,
        onLongPress: onPreview,
        child: ClipRRect(
          borderRadius: UiRadius.all(UiRadius.xs),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: colors.surfaceMuted),
              Image(
                image: MediaImage(platform, item),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, sync) => frame == null && !sync ? const SizedBox.shrink() : child,
                errorBuilder: (context, _, _) => Icon(
                  item.isVideo ? Icons.videocam_off_rounded : Icons.broken_image_rounded,
                  color: colors.textSubtle,
                ),
              ),
              if (selected) ColoredBox(color: colors.accent.withValues(alpha: 0.28)),
              Positioned(
                left: 6,
                top: 6,
                child: IgnorePointer(child: UiCheckbox(selected)),
              ),
              Positioned(
                right: 2,
                top: 2,
                child: _CornerButton(onPressed: onPreview),
              ),
              Positioned(
                left: 4,
                bottom: 4,
                child: _Pill(
                  icon: item.isVideo ? Icons.play_arrow_rounded : null,
                  text: item.isVideo && item.durationMs > 0
                      ? '${UiFormat.duration(Duration(milliseconds: item.durationMs))}  ${caption ?? UiFormat.bytes(item.size)}'
                      : caption ?? UiFormat.bytes(item.size),
                ),
              ),
              if (isBest) const Positioned(right: 4, bottom: 4, child: UiStatusPill('Best', status: UiStatus.success)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceInverse.withValues(alpha: 0.78),
        borderRadius: UiRadius.all(UiRadius.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 12, color: colors.onSurfaceInverse),
            Text(text, style: context.text.labelSmall?.copyWith(color: colors.onSurfaceInverse)),
          ],
        ),
      ),
    );
  }
}

class _CornerButton extends StatelessWidget {
  const _CornerButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkResponse(
      onTap: onPressed,
      radius: 18,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.surfaceInverse.withValues(alpha: 0.6), shape: BoxShape.circle),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(Icons.open_in_full_rounded, size: 14, color: colors.onSurfaceInverse),
          ),
        ),
      ),
    );
  }
}
