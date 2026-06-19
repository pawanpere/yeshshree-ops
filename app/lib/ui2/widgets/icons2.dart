import 'package:flutter/material.dart';

/// The ui2 icon set — one place that maps semantic names to Material icons, so
/// every screen uses the same glyphs instead of faked text characters
/// (▾ ‹ › ✓ → ● ↻ ✕). Material icons ship with Flutter (uses-material-design),
/// so no new dependency or asset is needed.
class I2 {
  I2._();

  // Bottom nav
  static const home = Icons.home_outlined;
  static const homeActive = Icons.home_rounded;
  static const tasks = Icons.checklist_rounded;
  static const sync = Icons.sync_rounded;
  static const alerts = Icons.notifications_none_rounded;
  static const alertsActive = Icons.notifications_rounded;
  static const me = Icons.person_outline_rounded;
  static const meActive = Icons.person_rounded;

  // Affordances
  static const back = Icons.chevron_left_rounded;
  static const chevronDown = Icons.expand_more_rounded;
  static const chevronRight = Icons.chevron_right_rounded;
  static const arrowForward = Icons.arrow_forward_rounded;
  static const edit = Icons.edit_outlined;
  static const search = Icons.search_rounded;
  static const close = Icons.close_rounded;

  // Status / results
  static const check = Icons.check_rounded;
  static const checkCircle = Icons.check_circle_rounded;
  static const warning = Icons.warning_amber_rounded;
  static const error = Icons.error_outline_rounded;
  static const queued = Icons.cloud_queue_rounded;
  static const syncPending = Icons.cloud_off_rounded;
  static const refresh = Icons.refresh_rounded;
  static const online = Icons.cloud_done_outlined;

  // Domain
  static const store = Icons.inventory_2_outlined;
  static const gate = Icons.sensor_door_outlined;
  static const truck = Icons.local_shipping_outlined;
  static const factory = Icons.precision_manufacturing_outlined;
  static const invoice = Icons.receipt_long_outlined;
  static const inbox = Icons.inbox_outlined;
  static const allClear = Icons.check_circle_outline_rounded;

  // Status bar
  static const signal = Icons.signal_cellular_alt_rounded;
  static const wifi = Icons.wifi_rounded;
  static const battery = Icons.battery_full_rounded;
}
