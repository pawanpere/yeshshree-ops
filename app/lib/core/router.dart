/// Route table — THE contract between foundation and feature agents: every screen
/// class named here must exist at the stated import path. Role-based redirect sends
/// each login to its station's home (app map role cards).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/pin_switch_screen.dart';
import '../features/auth/otp_screen.dart';
import '../features/auth/force_update_screen.dart';
import '../features/home/home_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/gate/scans_pending_screen.dart';
import '../features/gate/gate_entry_screen.dart';
import '../features/gate/unmatched_screen.dart';
import '../features/gate/backfill_screen.dart';
import '../features/qc/gr_form_screen.dart';
import '../features/store/issue_screen.dart';
import '../features/store/dispatch_screen.dart';
import '../features/store/billing_screen.dart';
import '../features/supervisor/supervisor_home_screen.dart';
import '../features/supervisor/confirm_sheet_screen.dart';
import '../features/supervisor/confirm_history_screen.dart';
import '../features/supervisor/holds_screen.dart';
import '../features/planning/planning_home_screen.dart';
import '../features/planning/schedule_screen.dart';
import '../features/planning/config_screen.dart';
import '../features/management/dashboards_screen.dart';
import '../features/management/approvals_screen.dart';
import '../features/management/anomalies_screen.dart';
import 'auth_state.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final loggingIn = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/otp') ||
          state.matchedLocation.startsWith('/pin') ||
          state.matchedLocation.startsWith('/force-update');
      if (!auth.loggedIn) return loggingIn ? null : '/login';
      if (loggingIn && !state.matchedLocation.startsWith('/force-update')) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/pin', builder: (_, __) => const PinSwitchScreen()),
      GoRoute(path: '/otp', builder: (_, __) => const OtpScreen()),
      GoRoute(path: '/force-update', builder: (_, __) => const ForceUpdateScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      // gate
      GoRoute(path: '/gate/scans', builder: (_, __) => const ScansPendingScreen()),
      GoRoute(path: '/gate/entry', builder: (_, state) =>
          GateEntryScreen(scanSuggestions: state.extra as Map<String, dynamic>?)),
      GoRoute(path: '/gate/unmatched', builder: (_, __) => const UnmatchedScreen()),
      GoRoute(path: '/gate/backfill', builder: (_, __) => const BackfillScreen()),
      // qc
      GoRoute(path: '/qc/gr', builder: (_, state) =>
          GrFormScreen(gateEntry: state.extra as Map<String, dynamic>?)),
      // store
      GoRoute(path: '/store/issue', builder: (_, __) => const IssueScreen()),
      GoRoute(path: '/store/dispatch', builder: (_, __) => const DispatchScreen()),
      GoRoute(path: '/store/billing', builder: (_, __) => const BillingScreen()),
      // supervisor
      GoRoute(path: '/supervisor', builder: (_, __) => const SupervisorHomeScreen()),
      GoRoute(path: '/supervisor/confirm', builder: (_, state) =>
          ConfirmSheetScreen(context_: state.extra as Map<String, dynamic>?)),
      GoRoute(path: '/supervisor/history',
          builder: (_, __) => const ConfirmHistoryScreen()),
      GoRoute(path: '/supervisor/holds', builder: (_, __) => const HoldsScreen()),
      // planning
      GoRoute(path: '/planning', builder: (_, __) => const PlanningHomeScreen()),
      GoRoute(path: '/planning/schedule', builder: (_, __) => const ScheduleScreen()),
      GoRoute(path: '/planning/config', builder: (_, __) => const ConfigScreen()),
      // management
      GoRoute(path: '/mgmt', builder: (_, __) => const DashboardsScreen()),
      GoRoute(path: '/mgmt/approvals', builder: (_, __) => const ApprovalsScreen()),
      GoRoute(path: '/mgmt/anomalies', builder: (_, __) => const AnomaliesScreen()),
    ],
  );
});
