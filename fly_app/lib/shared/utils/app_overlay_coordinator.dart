/// Lightweight coordinator for app-level [OverlayEntry] lifecycles.
///
/// It deliberately does not own presentation or navigation. Each overlay type
/// keeps its own widget/animation; this coordinator only guarantees that a
/// channel has at most one live entry and that stale dismissal callbacks cannot
/// remove a newer replacement.
library;

import 'package:flutter/widgets.dart';

enum AppOverlayChannel { inAppNotification, toast }

class AppOverlayCoordinator {
  AppOverlayCoordinator._();

  static final AppOverlayCoordinator instance = AppOverlayCoordinator._();

  final Map<AppOverlayChannel, OverlayEntry> _entries =
      <AppOverlayChannel, OverlayEntry>{};

  bool isActive(AppOverlayChannel channel) => _entries.containsKey(channel);

  OverlayEntry? entryFor(AppOverlayChannel channel) => _entries[channel];

  /// Inserts [entry] as the current entry for [channel].
  ///
  /// Any older entry in the same channel is removed first. Removal is guarded
  /// by identity, so a delayed callback from the old widget cannot remove the
  /// newly inserted entry.
  bool show({
    required AppOverlayChannel channel,
    required OverlayState overlay,
    required OverlayEntry entry,
  }) {
    if (!overlay.mounted) return false;

    remove(channel);
    _entries[channel] = entry;
    try {
      overlay.insert(entry);
      return true;
    } catch (_) {
      if (identical(_entries[channel], entry)) {
        _entries.remove(channel);
      }
      return false;
    }
  }

  /// Removes the current entry for [channel].
  ///
  /// When [expected] is supplied, the call is ignored unless it is still the
  /// active entry. This is important for asynchronously animated overlays.
  void remove(AppOverlayChannel channel, {OverlayEntry? expected}) {
    final current = _entries[channel];
    if (current == null) return;
    if (expected != null && !identical(current, expected)) return;

    _entries.remove(channel);
    // OverlayEntry may already be inserted but not yet mounted during the
    // current frame. It is still removable at that point; checking `mounted`
    // here would leave a stale entry scheduled for insertion.
    try {
      current.remove();
    } catch (_) {
      // Keep coordinator state authoritative even if an external owner already
      // detached the entry unexpectedly.
    }
  }
}
