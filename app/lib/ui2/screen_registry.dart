import 'package:flutter/material.dart';

import 'nav.dart';
import 'screens/coming_soon_screen.dart';
import 'screens/home_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/cockpit_screen.dart';
import 'screens/sync_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/signin_screen.dart';
import 'screens/confirm_form_screen.dart';
import 'screens/confirm_syncing_screen.dart';
import 'screens/confirm_synced_screen.dart';
import 'screens/confirm_queued_screen.dart';
import 'screens/issue_form_screen.dart';
import 'screens/issue_overlimit_screen.dart';
import 'screens/issue_waiting_screen.dart';
import 'screens/issue_approved_screen.dart';
import 'screens/issue_done_screen.dart';
import 'screens/gate_arrivals_screen.dart';
import 'screens/gate_match_screen.dart';
import 'screens/quality_worklist_screen.dart';
import 'screens/gate_qc_screen.dart';
import 'screens/gate_grn_screen.dart';
import 'screens/gate_received_screen.dart';
import 'screens/dispatch_list_screen.dart';
import 'screens/dispatch_detail_screen.dart';
import 'screens/gate_pass_screen.dart';
import 'screens/sale_form_screen.dart';
import 'screens/sale_done_screen.dart';
import 'screens/issue_history_screen.dart';
import 'screens/conf_history_screen.dart';
import 'screens/unmatched_screen.dart';
import 'screens/offline_gate_screen.dart';
import 'screens/offline_gate_saved_screen.dart';
import 'screens/force_update_screen.dart';
import 'screens/v_home_screen.dart';
import 'screens/v_alert_screen.dart';
import 'screens/v_stock_screen.dart';
import 'screens/v_login_screen.dart';
import 'screens/v_otp_screen.dart';

/// Maps a [ScreenId] to its widget. The single place that knows about every
/// screen class, so screens stay decoupled from one another.
Widget buildScreen(ScreenId id, PhoneNav nav) => switch (id) {
    ScreenId.home => Ui2HomeScreen(nav: nav),
    ScreenId.tasks => Ui2TasksScreen(nav: nav),
    ScreenId.cockpit => Ui2CockpitScreen(nav: nav),
    ScreenId.sync => Ui2SyncScreen(nav: nav),
    ScreenId.notifications => Ui2NotificationsScreen(nav: nav),
    ScreenId.profile => Ui2ProfileScreen(nav: nav),
    ScreenId.signin => Ui2SigninScreen(nav: nav),
    ScreenId.confirmForm => Ui2ConfirmFormScreen(nav: nav),
    ScreenId.confirmSyncing => Ui2ConfirmSyncingScreen(nav: nav),
    ScreenId.confirmSynced => Ui2ConfirmSyncedScreen(nav: nav),
    ScreenId.confirmQueued => Ui2ConfirmQueuedScreen(nav: nav),
    ScreenId.issueForm => Ui2IssueFormScreen(nav: nav),
    ScreenId.issueOverlimit => Ui2IssueOverlimitScreen(nav: nav),
    ScreenId.issueWaiting => Ui2IssueWaitingScreen(nav: nav),
    ScreenId.issueApproved => Ui2IssueApprovedScreen(nav: nav),
    ScreenId.issueDone => Ui2IssueDoneScreen(nav: nav),
    ScreenId.gateArrivals => Ui2GateArrivalsScreen(nav: nav),
    ScreenId.gateMatch => Ui2GateMatchScreen(nav: nav),
    ScreenId.gateQc => Ui2GateQcScreen(nav: nav),
    ScreenId.gateGrn => Ui2GateGrnScreen(nav: nav),
    ScreenId.gateReceived => Ui2GateReceivedScreen(nav: nav),
    ScreenId.dispatchList => Ui2DispatchListScreen(nav: nav),
    ScreenId.dispatchDetail => Ui2DispatchDetailScreen(nav: nav),
    ScreenId.gatePass => Ui2GatePassScreen(nav: nav),
    ScreenId.saleForm => Ui2SaleFormScreen(nav: nav),
    ScreenId.saleDone => Ui2SaleDoneScreen(nav: nav),
    ScreenId.issueHistory => Ui2IssueHistoryScreen(nav: nav),
    ScreenId.confHistory => Ui2ConfHistoryScreen(nav: nav),
    ScreenId.unmatched => Ui2UnmatchedScreen(nav: nav),
    ScreenId.offlineGate => Ui2OfflineGateScreen(nav: nav),
    ScreenId.offlineGateSaved => Ui2OfflineGateSavedScreen(nav: nav),
    ScreenId.forceUpdate => Ui2ForceUpdateScreen(nav: nav),
    ScreenId.vHome => Ui2VHomeScreen(nav: nav),
    ScreenId.vAlert => Ui2VAlertScreen(nav: nav),
    ScreenId.vStock => Ui2VStockScreen(nav: nav),
    ScreenId.vLogin => Ui2VLoginScreen(nav: nav),
    ScreenId.vOtp => Ui2VOtpScreen(nav: nav),
    // ---- Later-phase role screens (placeholdered in Phase 0) ----
    ScreenId.qualityWorklist => Ui2QualityWorklistScreen(nav: nav),
    ScreenId.productionHolds => ComingSoonScreen(
        nav: nav, titleEn: 'Parked holds', titleMr: 'पार्क केलेले होल्ड',
        phase: 'Phase 6', icon: Icons.pause_circle_outline),
    ScreenId.storeStock => ComingSoonScreen(
        nav: nav, titleEn: 'Stock browse', titleMr: 'स्टॉक पहा',
        phase: 'Phase 6', icon: Icons.inventory_2_outlined),
    ScreenId.planToday => ComingSoonScreen(
        nav: nav, titleEn: "Today's plan", titleMr: 'आजची योजना',
        phase: 'Phase 6', icon: Icons.event_note_outlined),
    ScreenId.planHolds => ComingSoonScreen(
        nav: nav, titleEn: 'Resolve holds', titleMr: 'होल्ड सोडवा',
        phase: 'Phase 6', icon: Icons.pause_circle_outline),
    ScreenId.mgmtDashboards => ComingSoonScreen(
        nav: nav, titleEn: 'Dashboards', titleMr: 'डॅशबोर्ड',
        phase: 'Phase 6', icon: Icons.dashboard_outlined),
    ScreenId.mgmtApprovals => ComingSoonScreen(
        nav: nav, titleEn: 'Approvals inbox', titleMr: 'मंजुरी इनबॉक्स',
        phase: 'Phase 6', icon: Icons.approval_outlined),
    ScreenId.mgmtAnomalies => ComingSoonScreen(
        nav: nav, titleEn: 'Anomaly register', titleMr: 'विसंगती नोंदवही',
        phase: 'Phase 6', icon: Icons.report_outlined),
    ScreenId.adminUsers => ComingSoonScreen(
        nav: nav, titleEn: 'Users', titleMr: 'वापरकर्ते',
        phase: 'Phase 5', icon: Icons.people_outline),
    ScreenId.adminDevices => ComingSoonScreen(
        nav: nav, titleEn: 'Devices', titleMr: 'उपकरणे',
        phase: 'Phase 5', icon: Icons.devices_outlined),
    ScreenId.adminMaster => ComingSoonScreen(
        nav: nav, titleEn: 'Master data', titleMr: 'मास्टर डेटा',
        phase: 'Phase 6', icon: Icons.storage_outlined),
    ScreenId.adminSettings => ComingSoonScreen(
        nav: nav, titleEn: 'Settings', titleMr: 'सेटिंग्ज',
        phase: 'Phase 6', icon: Icons.settings_outlined),
    ScreenId.vOrders => ComingSoonScreen(
        nav: nav, titleEn: 'Orders & call-offs', titleMr: 'ऑर्डर व कॉल-ऑफ',
        phase: 'Phase 6', icon: Icons.receipt_long_outlined),
    ScreenId.vFinance => ComingSoonScreen(
        nav: nav, titleEn: 'Financial position', titleMr: 'आर्थिक स्थिती',
        phase: 'Phase 6', icon: Icons.payments_outlined),
    };

/// A catalog entry for the dev jump-nav and URL deep-linking.
class ScreenEntry {
  const ScreenEntry(this.id, this.title, this.group, this.tab);
  final ScreenId id;
  final String title;
  final String group;
  final int? tab;
}

const List<ScreenEntry> kScreens = [
  ScreenEntry(ScreenId.home, 'Home', 'tab', 0),
  ScreenEntry(ScreenId.tasks, 'Tasks', 'tab', 1),
  ScreenEntry(ScreenId.cockpit, 'Cockpit', 'tab', 1),
  ScreenEntry(ScreenId.sync, 'Sync queue', 'tab', 2),
  ScreenEntry(ScreenId.notifications, 'Alerts', 'tab', 3),
  ScreenEntry(ScreenId.profile, 'Profile', 'tab', 4),
  ScreenEntry(ScreenId.signin, 'Sign in', 'misc', null),
  ScreenEntry(ScreenId.confirmForm, 'Record output', 'confirm', null),
  ScreenEntry(ScreenId.confirmSyncing, 'Confirm syncing', 'confirm', null),
  ScreenEntry(ScreenId.confirmSynced, 'Confirm synced', 'confirm', null),
  ScreenEntry(ScreenId.confirmQueued, 'Confirm queued', 'confirm', null),
  ScreenEntry(ScreenId.issueForm, 'Issue material', 'store', null),
  ScreenEntry(ScreenId.issueOverlimit, 'Issue over-limit', 'store', null),
  ScreenEntry(ScreenId.issueWaiting, 'Issue waiting', 'store', null),
  ScreenEntry(ScreenId.issueApproved, 'Issue approved', 'store', null),
  ScreenEntry(ScreenId.issueDone, 'Issue done', 'store', null),
  ScreenEntry(ScreenId.gateArrivals, 'Gate arrivals', 'gate', null),
  ScreenEntry(ScreenId.qualityWorklist, 'Quality worklist', 'gate', null),
  ScreenEntry(ScreenId.gateMatch, 'Gate match', 'gate', null),
  ScreenEntry(ScreenId.gateQc, 'Gate QC', 'gate', null),
  ScreenEntry(ScreenId.gateGrn, 'Gate GRN', 'gate', null),
  ScreenEntry(ScreenId.gateReceived, 'Gate received', 'gate', null),
  ScreenEntry(ScreenId.dispatchList, 'Dispatch', 'dispatch', null),
  ScreenEntry(ScreenId.dispatchDetail, 'Dispatch detail', 'dispatch', null),
  ScreenEntry(ScreenId.gatePass, 'Gate pass', 'dispatch', null),
  ScreenEntry(ScreenId.saleForm, 'Scrap sale', 'sale', null),
  ScreenEntry(ScreenId.saleDone, 'Sale invoiced', 'sale', null),
  ScreenEntry(ScreenId.issueHistory, 'My issues', 'history', null),
  ScreenEntry(ScreenId.confHistory, 'Confirmation history', 'history', null),
  ScreenEntry(ScreenId.unmatched, 'Unmatched vehicle', 'gate', null),
  ScreenEntry(ScreenId.offlineGate, 'Offline gate entry', 'gate', null),
  ScreenEntry(ScreenId.offlineGateSaved, 'Offline gate saved', 'gate', null),
  ScreenEntry(ScreenId.forceUpdate, 'Force update', 'misc', null),
  ScreenEntry(ScreenId.vHome, 'Vendor home', 'vendor', null),
  ScreenEntry(ScreenId.vAlert, 'Vendor call-off', 'vendor', null),
  ScreenEntry(ScreenId.vStock, 'Vendor stock', 'vendor', null),
  ScreenEntry(ScreenId.vLogin, 'Vendor sign in', 'vendor', null),
  ScreenEntry(ScreenId.vOtp, 'Vendor OTP', 'vendor', null),
];

/// Resolve a URL ?screen= slug (the enum name) to a [ScreenId].
ScreenId? screenIdFromSlug(String slug) {
  for (final e in kScreens) {
    if (e.id.name.toLowerCase() == slug.toLowerCase()) return e.id;
  }
  return null;
}
