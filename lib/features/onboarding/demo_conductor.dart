import 'dart:async';

import 'package:flutter/widgets.dart';

/// Shared state for a running guided tour. The demo controller drives the data
/// (through the normal repositories) and sets [target] to whatever should be
/// highlighted next; the live screens attach these [GlobalKey]s to their real
/// widgets so the overlay can read each one's on-screen rect; the overlay's
/// Next button drives the [waitForNext] gate that paces the whole thing.
///
/// Present (non-null [activeDemoProvider]) means a tour is running; the screens
/// only wire themselves to the conductor while it is.
class DemoConductor {
  /// Highlight targets attached on the real screens.
  final newZoneFabKey = GlobalKey();
  final searchFieldKey = GlobalKey();
  final addTileKey = GlobalKey();
  final completeKey = GlobalKey();
  final bannerKey = GlobalKey();

  /// Highlight targets inside the overlay's own faux new-zone dialog — a real
  /// modal can't be cut into reliably because of route/overlay layering, so the
  /// dialog is drawn in the overlay where the spotlight can reach it.
  final zoneNameFieldKey = GlobalKey();
  final zoneConfirmKey = GlobalKey();

  final _checkboxKeys = <int, GlobalKey>{};

  /// A stable key per list entry so a specific checkbox can be highlighted.
  GlobalKey checkboxKey(int entryId) =>
      _checkboxKeys.putIfAbsent(entryId, () => GlobalKey());

  /// Visible inputs the UI binds to in demo mode, so typed text actually shows.
  final searchController = TextEditingController();
  final zoneNameController = TextEditingController();

  /// Which widget the overlay highlights right now (null = dim everything).
  final target = ValueNotifier<GlobalKey?>(null);

  /// Whether the overlay shows its faux new-zone dialog.
  final zoneDialogVisible = ValueNotifier<bool>(false);

  /// True on the final step so the button reads Finish instead of Next.
  final isLast = ValueNotifier<bool>(false);

  /// Tests pass true so the gate never blocks (no real button to tap).
  final bool autoAdvance;

  DemoConductor({this.autoAdvance = false});

  /// Next gate: the controller awaits [waitForNext]; the overlay's button
  /// calls [advance] to release the current step and arm the next.
  Completer<void> _gate = Completer<void>();
  bool _aborted = false;

  bool get aborted => _aborted;

  Future<void> waitForNext() =>
      autoAdvance ? Future<void>.value() : _gate.future;

  void advance() {
    if (!_gate.isCompleted) _gate.complete();
    _gate = Completer<void>();
  }

  /// Skip: release the gate and tell the controller to stop at the next check.
  void abort() {
    _aborted = true;
    advance();
  }

  void dispose() {
    searchController.dispose();
    zoneNameController.dispose();
    target.dispose();
    zoneDialogVisible.dispose();
    isLast.dispose();
  }
}
