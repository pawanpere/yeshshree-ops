import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'nav.dart';
import 'widgets/icons2.dart';

/// Which shell a role runs in. Floor + vendor roles use the phone shell; the
/// management/planning/admin roles use the wider responsive office shell.
enum ShellKind { phone, office }

/// The eight pilot roles.
enum Role { gate, quality, production, store, planning, management, admin, vendor }

/// One navigation destination for a role (a bottom tab or a sidebar item).
class RoleTab {
  const RoleTab(this.id, this.icon, this.en, this.mr);
  final ScreenId id;
  final IconData icon;
  final String en;
  final String mr;
}

/// Everything a role's scoped shell needs: which shell, its nav destinations,
/// and a display name. The first tab is the role's home. Built as a const map so
/// the role→screens mapping lives in code (a role can later be locked to the
/// account instead of picked).
class RoleSpec {
  const RoleSpec({
    required this.shell,
    required this.tabs,
    required this.en,
    required this.mr,
    required this.icon,
  });
  final ShellKind shell;
  final List<RoleTab> tabs;
  final String en;
  final String mr;
  final IconData icon;

  ScreenId get home => tabs.first.id;
  bool get isOffice => shell == ShellKind.office;
}

const Map<Role, RoleSpec> kRoles = {
  Role.gate: RoleSpec(
    shell: ShellKind.phone,
    en: 'Gate', mr: 'गेट', icon: I2.gate,
    tabs: [
      RoleTab(ScreenId.gateArrivals, I2.inbox, 'Inbox', 'इनबॉक्स'),
      RoleTab(ScreenId.gateMatch, I2.gate, 'Review', 'तपासणी'),
      RoleTab(ScreenId.unmatched, I2.warning, 'Unmatched', 'जुळत नाही'),
    ],
  ),
  Role.quality: RoleSpec(
    shell: ShellKind.phone,
    en: 'Quality', mr: 'गुणवत्ता', icon: Icons.verified_outlined,
    tabs: [
      RoleTab(ScreenId.qualityWorklist, I2.tasks, 'Worklist', 'कार्यसूची'),
      RoleTab(ScreenId.gateQc, Icons.science_outlined, 'Quality', 'गुणवत्ता'),
      RoleTab(ScreenId.gateGrn, I2.invoice, 'Receipt', 'पावती'),
    ],
  ),
  Role.production: RoleSpec(
    shell: ShellKind.phone,
    en: 'Production', mr: 'उत्पादन', icon: I2.factory,
    tabs: [
      RoleTab(ScreenId.cockpit, I2.factory, 'Cockpit', 'कॉकपिट'),
      RoleTab(ScreenId.confirmForm, I2.edit, 'Record', 'नोंदवा'),
      RoleTab(ScreenId.productionHolds, I2.warning, 'Holds', 'होल्ड'),
      RoleTab(ScreenId.confHistory, Icons.history, 'History', 'इतिहास'),
    ],
  ),
  Role.store: RoleSpec(
    shell: ShellKind.phone,
    en: 'Store', mr: 'स्टोअर', icon: I2.store,
    tabs: [
      RoleTab(ScreenId.issueForm, I2.store, 'Issue', 'जारी'),
      RoleTab(ScreenId.dispatchList, I2.truck, 'Dispatch', 'डिस्पॅच'),
      RoleTab(ScreenId.storeStock, Icons.inventory_2_outlined, 'Stock', 'स्टॉक'),
    ],
  ),
  Role.planning: RoleSpec(
    shell: ShellKind.office,
    en: 'Planning', mr: 'नियोजन', icon: Icons.event_note_outlined,
    tabs: [
      RoleTab(ScreenId.planToday, Icons.event_note_outlined, "Today's plan", 'आजची योजना'),
      RoleTab(ScreenId.planHolds, I2.warning, 'Resolve holds', 'होल्ड सोडवा'),
    ],
  ),
  Role.management: RoleSpec(
    shell: ShellKind.office,
    en: 'Management', mr: 'व्यवस्थापन', icon: Icons.dashboard_outlined,
    tabs: [
      RoleTab(ScreenId.mgmtDashboards, Icons.dashboard_outlined, 'Dashboards', 'डॅशबोर्ड'),
      RoleTab(ScreenId.mgmtApprovals, Icons.approval_outlined, 'Approvals', 'मंजुरी'),
      RoleTab(ScreenId.mgmtAnomalies, I2.warning, 'Anomalies', 'विसंगती'),
    ],
  ),
  Role.admin: RoleSpec(
    shell: ShellKind.office,
    en: 'Admin', mr: 'अ‍ॅडमिन', icon: Icons.admin_panel_settings_outlined,
    tabs: [
      RoleTab(ScreenId.adminUsers, Icons.people_outline, 'Users', 'वापरकर्ते'),
      RoleTab(ScreenId.adminDevices, Icons.devices_outlined, 'Devices', 'उपकरणे'),
      RoleTab(ScreenId.adminMaster, Icons.storage_outlined, 'Master data', 'मास्टर डेटा'),
      RoleTab(ScreenId.adminSettings, Icons.settings_outlined, 'Settings', 'सेटिंग्ज'),
    ],
  ),
  Role.vendor: RoleSpec(
    shell: ShellKind.phone,
    en: 'Vendor', mr: 'विक्रेता', icon: I2.truck,
    tabs: [
      RoleTab(ScreenId.vHome, I2.home, 'Home', 'मुख्य'),
      RoleTab(ScreenId.vAlert, I2.alerts, 'Alerts', 'सूचना'),
      RoleTab(ScreenId.vStock, I2.store, 'Stock', 'स्टॉक'),
      RoleTab(ScreenId.vOrders, I2.invoice, 'Orders', 'ऑर्डर'),
      RoleTab(ScreenId.vFinance, Icons.payments_outlined, 'Money', 'पैसे'),
    ],
  ),
};

/// The role the user picked at login (pilot). Null until picked. Admin can later
/// be locked to the account's own role instead of free-picking.
final activeRoleProvider = StateProvider<Role?>((ref) => null);

/// Which pilot roles an account may pick, derived from the server role on the
/// session (`session.role`). The picker shows only these; when exactly one is
/// allowed it is auto-selected (the "role locked to the account" path). Admin
/// is the only role that sees everything.
List<Role> rolesForAccount(String? serverRole) {
  switch (serverRole) {
    case 'admin':
      return Role.values;
    case 'management':
      return const [Role.management];
    case 'planning':
      return const [Role.planning];
    case 'supervisor':
      return const [Role.production];
    case 'plant_ops':
      return const [Role.gate, Role.quality, Role.store];
    case 'vendor':
      return const [Role.vendor];
    default:
      // Unknown/legacy role: don't trap the user — let them pick (pilot only).
      return Role.values;
  }
}
