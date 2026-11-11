import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:theme/theme.dart';

import '../media/media_item.dart';
import '../media/tidy_store.dart';

/// Confirm, delete (or move to trash), then report how much space was freed.
///
/// Android shows its own confirmation dialog for the batch, so a dismissed dialog means nothing
/// was deleted.
Future<void> confirmAndDelete(BuildContext context, TidyStore store, List<MediaItem> items) async {
  if (items.isEmpty) return;
  final trash = store.settings.moveToTrash && (store.device?.supportsTrash ?? false);
  final n = items.length;
  final noun = n == 1 ? 'file' : 'files';
  final size = UiFormat.bytes(totalBytes(items));

  final ok = await UiDialog.confirm(
    context,
    title: trash ? 'Move $n $noun to Trash?' : 'Delete $n $noun?',
    message: trash
        ? 'This frees $size. Android keeps them in Trash for 30 days, and you can restore them from your gallery.'
        : 'This frees $size. They are deleted from this phone and cannot be recovered.',
    confirmLabel: trash ? 'Move to Trash' : 'Delete',
    destructive: true,
    icon: Icons.delete_rounded,
  );
  if (!ok || !context.mounted) return;

  try {
    final outcome = await store.delete(items);
    if (!context.mounted) return;
    if (outcome.count == 0) {
      context.showToast('Nothing was deleted.', status: UiStatus.warning);
      return;
    }
    final c = outcome.count;
    final verb = outcome.trashed ? 'Moved' : 'Deleted';
    context.showToast(
      '$verb $c ${c == 1 ? 'file' : 'files'}. Freed ${UiFormat.bytes(outcome.bytes)}.',
      status: UiStatus.success,
    );
  } on PlatformException catch (e) {
    if (context.mounted) {
      context.showToast(e.message ?? 'The delete failed.', title: 'Could not delete', status: UiStatus.danger);
    }
  }
}
