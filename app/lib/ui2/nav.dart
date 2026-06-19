import 'package:flutter/widgets.dart';

/// Navigation contract for the ui2 phone app. Screens are decoupled: they never
/// import each other — they call [PhoneNav] with a [ScreenId], and the registry
/// (screen_registry.dart) maps the id to a widget. This lets every screen be
/// built in isolation.
enum ScreenId {
  home, tasks, cockpit, sync, notifications, profile, signin,
  confirmForm, confirmSyncing, confirmSynced, confirmQueued,
  issueForm, issueOverlimit, issueWaiting, issueApproved, issueDone,
  gateArrivals, gateScan, gateScanned, gateMatch, gateQc, gateGrn, gateReceived,
  dispatchList, dispatchDetail, gatePass, saleForm, saleDone,
  issueHistory, confHistory, unmatched, offlineGate, offlineGateSaved,
  forceUpdate, vHome, vAlert, vStock, vLogin, vOtp,
  // ---- Role-screens built in later phases. Placeholdered in Phase 0 so the
  // role→screens map is complete now; each is implemented in the phase noted.
  qualityWorklist, // P3
  productionHolds, // P6 (confirmations/holds)
  storeStock, // P6 (stock browse)
  planToday, planHolds, // P6 (planning)
  mgmtDashboards, mgmtApprovals, mgmtAnomalies, // P6 (management)
  adminUsers, adminDevices, adminMaster, adminSettings, // P5/P6 (admin)
  vOrders, vFinance, // P6 (vendor orders + financials)
}

/// Modal bottom sheets that float over the current screen, inside the frame.
enum SheetId { correction }

abstract class PhoneNav {
  /// Push a screen onto the current tab's stack.
  void go(ScreenId id);

  /// Replace the top of the stack (forward flow steps, no back-stack growth).
  void replace(ScreenId id);

  /// Pop the top screen; no-op at a tab root.
  void pop();

  /// Switch bottom tab (0=Home 1=Tasks 2=Sync 3=Alerts 4=Me), resetting its stack.
  void tab(int index);

  /// Jump to the Home tab root, clearing any drill-down.
  void home();

  /// Show a modal sheet over the current screen.
  void sheet(SheetId id);

  /// Dismiss the current modal sheet.
  void closeSheet();

  /// Show an arbitrary bottom-anchored overlay (pickers, menus) inside the
  /// phone frame. Tapping the scrim or calling [hideOverlay] dismisses it.
  void overlay(Widget child);

  /// Dismiss the current overlay.
  void hideOverlay();
}
