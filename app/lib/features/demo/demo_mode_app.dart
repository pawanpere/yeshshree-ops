import 'package:flutter/material.dart';

import '../../core/theme.dart';

class DemoModeApp extends StatefulWidget {
  const DemoModeApp({super.key});

  @override
  State<DemoModeApp> createState() => _DemoModeAppState();
}

class _DemoModeAppState extends State<DemoModeApp> {
  String _screen = 'roleSelect';
  String _role = 'ops';

  bool get _authFlow => const {'login', 'otp', 'roleSelect'}.contains(_screen);

  void _go(String screen) {
    final role = _roleForScreen(screen);
    setState(() {
      if (role != null) _role = role;
      _screen = screen;
    });
  }

  void _pickRole(String role) {
    setState(() {
      _role = role;
      _screen = _roleHome[role] ?? 'opsHome';
    });
  }

  void _showJumpSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          minChildSize: 0.35,
          maxChildSize: 0.94,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Screen gallery',
                      style: TextStyle(
                        color: YColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              for (final group in _jumpGroups) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: Text(
                    group.title.toUpperCase(),
                    style: const TextStyle(
                      color: YColors.muted,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: .5,
                    ),
                  ),
                ),
                for (final item in group.items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 17,
                      backgroundColor: item.color.withValues(alpha: .12),
                      foregroundColor: item.color,
                      child: Icon(item.icon, size: 18),
                    ),
                    title: Text(
                      item.label,
                      style: const TextStyle(
                        color: YColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    trailing: _screen == item.id
                        ? const Icon(Icons.check, color: YColors.green)
                        : const Icon(Icons.chevron_right, color: YColors.muted),
                    onTap: () {
                      Navigator.pop(context);
                      _go(item.id);
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final framed = constraints.maxWidth >= 720;
      final shell = _PhoneShell(
        role: _role,
        screen: _screen,
        showTabs: !_authFlow,
        onTab: _go,
        child: _screenWidget(),
      );

      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFE9EDF5)],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: framed
                  ? Container(
                      width: 430,
                      height: 900,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(34),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x330F172A),
                            blurRadius: 40,
                            offset: Offset(0, 20),
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: shell,
                      ),
                    )
                  : shell,
            ),
            if (framed)
              const Positioned(
                top: 24,
                left: 24,
                child: _BrandPlate(),
              ),
            Positioned(
              right: framed ? 28 : 12,
              bottom: framed ? 28 : 96,
              child: SafeArea(
                child: FloatingActionButton.small(
                  heroTag: 'demo-screen-jump',
                  tooltip: 'Screens',
                  backgroundColor: YColors.navy,
                  foregroundColor: Colors.white,
                  onPressed: _showJumpSheet,
                  child: const Icon(Icons.grid_view_rounded),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _screenWidget() {
    switch (_screen) {
      case 'login':
        return DemoLoginScreen(onNext: () => _go('otp'));
      case 'otp':
        return DemoOtpScreen(
          onBack: () => _go('login'),
          onNext: () => _go('roleSelect'),
        );
      case 'roleSelect':
        return DemoRoleSelectScreen(onPick: _pickRole);
      case 'opsHome':
        return DemoOpsHome(onOpen: _go);
      case 'gateScan':
        return DemoGateScan(onOpen: _go);
      case 'gateConfirm':
        return DemoGateConfirm(onOpen: _go);
      case 'qcReceipt':
        return DemoQcReceipt(onOpen: _go);
      case 'issue':
        return DemoIssueScreen();
      case 'planningHome':
        return DemoPlanningHome(onOpen: _go);
      case 'millDetail':
        return DemoMillDetail();
      case 'scheduleDiff':
        return DemoScheduleDiff();
      case 'drift':
        return DemoDriftScreen();
      case 'vendorHome':
        return DemoVendorHome(onOpen: _go);
      case 'vendorAlert':
        return DemoVendorAlert();
      case 'vendorPOs':
        return DemoVendorPos();
      case 'vendorFinance':
        return DemoVendorFinance();
      case 'vendorStock':
        return DemoVendorStock();
      case 'mgmtHome':
        return DemoMgmtHome(onOpen: _go);
      case 'approvals':
        return DemoApprovals(onOpen: _go);
      case 'approvalDetail':
        return DemoApprovalDetail();
      case 'vendorPerf':
        return DemoVendorPerf();
      case 'notifications':
        return DemoNotifications();
      case 'profile':
        return DemoProfile(
          role: _role,
          onSwitchRole: () => _go('roleSelect'),
          onSignOut: () => _go('login'),
        );
      default:
        return DemoOpsHome(onOpen: _go);
    }
  }
}

class _PhoneShell extends StatelessWidget {
  const _PhoneShell({
    required this.role,
    required this.screen,
    required this.showTabs,
    required this.onTab,
    required this.child,
  });

  final String role;
  final String screen;
  final bool showTabs;
  final ValueChanged<String> onTab;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tabs = _tabsByRole[role] ?? _tabsByRole['ops']!;
    final active = _activeTab(role, screen);
    return Material(
      color: YColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(child: child),
            if (showTabs)
              _DemoTabBar(
                tabs: tabs,
                active: active,
                onTap: (tab) => onTab(tab.screen),
              ),
          ],
        ),
      ),
    );
  }
}

class _DemoTabBar extends StatelessWidget {
  const _DemoTabBar({
    required this.tabs,
    required this.active,
    required this.onTap,
  });

  final List<_DemoTab> tabs;
  final String active;
  final ValueChanged<_DemoTab> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: YColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 10),
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: InkWell(
                onTap: () => onTap(tab),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tab.icon,
                        size: tab.center ? 25 : 21,
                        color: tab.id == active ? YColors.blue : YColors.muted,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tab.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color:
                              tab.id == active ? YColors.blue : YColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BrandPlate extends StatelessWidget {
  const _BrandPlate();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _YMark(size: 26, color: YColors.navy),
        SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YESHSHREE OPERATIONS',
              style: TextStyle(
                color: YColors.navy,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
              ),
            ),
            Text(
              'Flutter demo mode',
              style: TextStyle(color: YColors.muted, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class DemoLoginScreen extends StatelessWidget {
  const DemoLoginScreen({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: YColors.navy,
      padding: const EdgeInsets.fromLTRB(24, 38, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _YMark(size: 38, color: Colors.white),
              SizedBox(width: 12),
              Text(
                'YESHSHREE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 64),
          const Text(
            'Operations,\nconnected.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              height: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'One mobile platform across planning, plant, and vendors - powered by SAP.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.45),
          ),
          const Spacer(),
          const Text(
            'MOBILE NUMBER',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: .6,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .08),
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Text(
                  '+91',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                SizedBox(width: 10),
                SizedBox(
                  height: 20,
                  child: VerticalDivider(color: Colors.white24),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '98220 14523',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: YColors.navy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onNext,
              child: const Text(
                'Send OTP',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, color: Colors.white54, size: 15),
                SizedBox(width: 6),
                Text(
                  'Secured by Yeshshree - SAP-backed',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DemoOtpScreen extends StatelessWidget {
  const DemoOtpScreen({
    super.key,
    required this.onBack,
    required this.onNext,
  });

  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _DemoPage(
      background: Colors.white,
      header: _DemoTopBar(title: '', onBack: onBack),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the 6-digit code',
              style: TextStyle(
                color: YColors.ink,
                fontSize: 25,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sent to +91 98220 14523',
              style: TextStyle(color: YColors.muted, fontSize: 14),
            ),
            const SizedBox(height: 34),
            Row(
              children: [
                for (final digit in ['4', '8', '2', '1', '', ''])
                  Expanded(
                    child: Container(
                      height: 56,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: YColors.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: digit.isEmpty ? YColors.line : YColors.navy,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        digit,
                        style: const TextStyle(
                          color: YColors.ink,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Row(
              children: [
                Text('Resend in 00:28',
                    style: TextStyle(color: YColors.muted, fontSize: 13)),
                Spacer(),
                Text(
                  'Try a call instead',
                  style: TextStyle(
                    color: YColors.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: onNext,
                child: const Text('Verify & continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DemoRoleSelectScreen extends StatelessWidget {
  const DemoRoleSelectScreen({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return _DemoPage(
      background: Colors.white,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
        children: [
          const _YMark(size: 30, color: YColors.navy),
          const SizedBox(height: 20),
          const Text(
            'Welcome, Rajesh.',
            style: TextStyle(
              color: YColors.ink,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'You have access to multiple roles. Pick one to continue.',
            style: TextStyle(color: YColors.muted, fontSize: 14),
          ),
          const SizedBox(height: 18),
          for (final role in _roleCards)
            _ActionCard(
              icon: role.icon,
              iconColor: role.color,
              title: role.title,
              subtitle: role.subtitle,
              onTap: () => onPick(role.id),
            ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'Signed in as Rajesh Kulkarni - YS-0428 - Plant 1, Chakan',
              textAlign: TextAlign.center,
              style: TextStyle(color: YColors.muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class DemoOpsHome extends StatelessWidget {
  const DemoOpsHome({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return _ScrollableScreen(
      header: _HeroHeader(
        eyebrow: 'PLANT OPS - LINE B',
        title: "Today's plan",
        subtitle: '12 Jun 2026 - Plant 1, Chakan',
        notificationCount: 5,
        onBell: () => onOpen('notifications'),
        stats: const [
          _HeaderStat('CRITICAL', '1', YColors.red),
          _HeaderStat('WATCH', '2', YColors.amber),
          _HeaderStat('ON TRACK', '3', YColors.green),
        ],
      ),
      children: [
        _QuickGrid(actions: [
          _QuickAction(Icons.qr_code_scanner, 'Gate scan', () => onOpen('gateScan')),
          _QuickAction(Icons.fact_check_outlined, 'QC inward', () => onOpen('qcReceipt')),
          _QuickAction(Icons.call_made, 'Issue', () => onOpen('issue')),
          _QuickAction(Icons.flag_outlined, 'Flag', () {}),
        ]),
        const _SectionTitle('Production plan - 6 parts'),
        _PlanCard(
          code: 'BJ-FRM-2104',
          title: 'Brake flange rough machined',
          done: '820',
          plan: '1,200 pcs',
          due: '14:00',
          cover: '0.8 d',
          status: 'red',
        ),
        _PlanCard(
          code: 'BJ-ARM-4410',
          title: 'Control arm LH',
          done: '410',
          plan: '620 pcs',
          due: '16:00',
          cover: '2.4 d',
          status: 'amber',
        ),
        _PlanCard(
          code: 'BJ-HUB-1188',
          title: 'Wheel hub final',
          done: '960',
          plan: '1,000 pcs',
          due: '18:00',
          cover: '5.1 d',
          status: 'green',
        ),
      ],
    );
  }
}

class DemoGateScan extends StatelessWidget {
  const DemoGateScan({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          _DemoTopBar(
            title: 'Gate entry - Scan invoice QR',
            dark: true,
            action: const Icon(Icons.bolt, color: Colors.white),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, .25),
                        radius: .9,
                        colors: [Colors.grey.shade800, Colors.black],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 2),
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                        const Positioned(
                          left: 14,
                          right: 14,
                          top: 108,
                          child: Divider(color: YColors.green, thickness: 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 24,
                  left: 24,
                  right: 24,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.qr_code, color: Colors.white),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Align QR inside the box',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Geofence verified - Plant 1, Gate 2',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        _MiniBadge('GEO OK', color: YColors.green),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: _DetectedCard(onTap: () => onOpen('gateConfirm')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DemoGateConfirm extends StatelessWidget {
  const DemoGateConfirm({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return _ScrollableScreen(
      topBar: const _DemoTopBar(
        title: 'Gate entry',
        subtitle: 'Step 2 of 2 - Confirm details',
      ),
      children: [
        const _DarkCard(
          eyebrow: 'MATCHED TO OPEN PO',
          title: 'PO 4500218812',
          body: 'Shakti Forge Pvt Ltd - BJ-FRM-2104 - 1,240 pcs expected',
        ),
        const _SectionTitle('Vehicle & driver'),
        const _InfoCard(rows: [
          _InfoRow('Vehicle', 'MH12-AB-4421'),
          _InfoRow('Driver', 'Suresh Kale'),
          _InfoRow('Invoice', 'INV-2026-2841'),
        ]),
        const _SectionTitle('PO match'),
        _ActionCard(
          icon: Icons.inventory_2_outlined,
          iconColor: YColors.green,
          title: 'Invoice pre-arrived',
          subtitle: 'Qty, vendor and material match the SAP open PO.',
          trailing: const _MiniBadge('OK', color: YColors.green),
          onTap: () {},
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => onOpen('qcReceipt'),
          child: const Text('Create gate pass & notify QC'),
        ),
      ],
    );
  }
}

class DemoQcReceipt extends StatelessWidget {
  const DemoQcReceipt({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return _ScrollableScreen(
      topBar: const _DemoTopBar(
        title: 'QC inward receipt',
        subtitle: 'Gate pass GE-240611-0042',
      ),
      children: const [
        _AlertCard(
          kind: 'warn',
          title: 'Shortage check triggered',
          body: 'Received 1,190 pcs against 1,240 expected. Within soft tolerance.',
        ),
        _InfoCard(rows: [
          _InfoRow('Material', 'BJ-FRM-2104 - Brake flange'),
          _InfoRow('Vendor', 'Shakti Forge Pvt Ltd'),
          _InfoRow('Expected qty', '1,240 pcs'),
          _InfoRow('Received qty', '1,190 pcs'),
          _InfoRow('QC result', 'Accepted with shortage note'),
        ]),
        _SectionTitle('System action'),
        _ActionCard(
          icon: Icons.receipt_long_outlined,
          iconColor: YColors.blue,
          title: 'GR draft ready',
          subtitle: 'Debit note suggestion: shortage 50 pcs at 5x policy.',
        ),
      ],
    );
  }
}

class DemoIssueScreen extends StatelessWidget {
  const DemoIssueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ScrollableScreen(
      topBar: _DemoTopBar(title: 'Material issue', subtitle: 'RM store - Line B'),
      children: [
        _DarkCard(
          eyebrow: 'ISSUE TO LINE',
          title: 'BJ-FRM-2104 - 400 pcs',
          body: 'Stock after issue: 1.6 days cover. Within safety threshold.',
        ),
        _InfoCard(rows: [
          _InfoRow('Source', 'RM Store'),
          _InfoRow('Destination', 'Line B'),
          _InfoRow('Operator', 'Rajesh Kulkarni'),
          _InfoRow('SAP mode', 'Parallel run - queued for sync'),
        ]),
        _AlertCard(
          kind: 'ok',
          title: 'Issue can proceed',
          body: 'Ledger movement and SAP outbox row will be created together.',
        ),
      ],
    );
  }
}

class DemoPlanningHome extends StatelessWidget {
  const DemoPlanningHome({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return _ScrollableScreen(
      header: _HeroHeader(
        eyebrow: 'PLANNING - MATERIALS HEAD',
        title: 'Mill flag inbox',
        subtitle: 'Last sweep: 09:42 - 12 Jun 2026',
        notificationCount: 3,
        onBell: () => onOpen('notifications'),
        stats: const [
          _HeaderStat('CRITICAL', '1', YColors.red),
          _HeaderStat('WARNING', '2', YColors.amber),
          _HeaderStat('IN-FLIGHT', '18', YColors.green),
        ],
      ),
      children: [
        _QuickGrid(actions: [
          _QuickAction(Icons.sync, 'Cascade run', () => onOpen('scheduleDiff')),
          _QuickAction(Icons.send_outlined, 'Release', () => onOpen('scheduleDiff')),
          _QuickAction(Icons.chat_bubble_outline, 'WA feed', () {}),
          _QuickAction(Icons.assignment_outlined, 'Digest', () => onOpen('drift')),
        ]),
        const _SectionTitle('Open mill flags'),
        _FlagCard(
          id: 'MF-2406-017',
          title: 'JSW Dolvi',
          subtitle: 'EN8D 22mm bars - single source',
          status: 'red',
          cover: '4.5 d',
          onTap: () => onOpen('millDetail'),
        ),
        _FlagCard(
          id: 'MF-2406-019',
          title: 'Mukand Steel',
          subtitle: '20MnCr5 rounds - allocation watch',
          status: 'amber',
          cover: '8.2 d',
          onTap: () => onOpen('millDetail'),
        ),
      ],
    );
  }
}

class DemoMillDetail extends StatelessWidget {
  const DemoMillDetail({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ScrollableScreen(
      topBar: _DemoTopBar(title: 'JSW Dolvi', subtitle: 'MF-2406-017'),
      children: [
        _InfoCard(rows: [
          _InfoRow('Grade', 'EN8D 22mm bars'),
          _InfoRow('Stock-only cover', '4.5 days'),
          _InfoRow('With in-flight POs', '8.2 days'),
          _InfoRow('Buffer floor', '7.0 days'),
          _InfoRow('Worst lead time', '38 days'),
        ]),
        _SectionTitle('Recommended action'),
        _AlertCard(
          kind: 'bad',
          title: 'Buffer breach on 27 Jun',
          body: 'Raise PO for 34 MT or shift allocation from Mukand by Friday.',
        ),
      ],
    );
  }
}

class DemoScheduleDiff extends StatelessWidget {
  const DemoScheduleDiff({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ScrollableScreen(
      topBar: _DemoTopBar(
        title: 'Schedule diff & release',
        subtitle: 'Bajaj feed vs last release',
      ),
      children: [
        _InfoCard(rows: [
          _InfoRow('Parts changed', '42'),
          _InfoRow('Qty increase', '+8,420 pcs'),
          _InfoRow('Qty decrease', '-3,140 pcs'),
          _InfoRow('Unmapped rows', '2'),
        ]),
        _AlertCard(
          kind: 'warn',
          title: '2 sanity checks need review',
          body: 'Part BJ-ARM-4410 exceeds line capacity for Friday shift.',
        ),
        _ActionCard(
          icon: Icons.rocket_launch_outlined,
          iconColor: YColors.green,
          title: 'Release schedule',
          subtitle: 'Publish to line supervisors and vendors after review.',
        ),
      ],
    );
  }
}

class DemoDriftScreen extends StatelessWidget {
  const DemoDriftScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ScrollableScreen(
      topBar: _DemoTopBar(title: 'Anomaly register', subtitle: '4 open - 1 hard'),
      children: [
        _AlertCard(
          kind: 'bad',
          title: 'Hard anomaly',
          body: 'Invoice quantity is 68% below PO balance. Management review needed.',
        ),
        _AlertCard(
          kind: 'warn',
          title: 'Soft anomaly',
          body: 'Shortage within tolerance. Debit suggestion waiting for confirmation.',
        ),
        _AlertCard(
          kind: 'ok',
          title: 'Resolved today',
          body: 'Vehicle photo pending case closed after gate upload.',
        ),
      ],
    );
  }
}

class DemoVendorHome extends StatelessWidget {
  const DemoVendorHome({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return _ScrollableScreen(
      header: _HeroHeader(
        eyebrow: 'COMPONENT VENDOR',
        title: 'Tirupati Metals',
        subtitle: 'POs, stock cover and finance position',
        notificationCount: 2,
        onBell: () => onOpen('notifications'),
        stats: const [
          _HeaderStat('DUE TODAY', '4', YColors.red),
          _HeaderStat('OPEN POS', '18', YColors.amber),
          _HeaderStat('COVER', '6.2 d', YColors.green),
        ],
      ),
      children: [
        _AlertCard(
          kind: 'bad',
          title: 'Critical line cover alert',
          body: 'BJ-FRM-2104 will fall below 1 day cover by tomorrow.',
          onTap: () => onOpen('vendorAlert'),
        ),
        _QuickGrid(actions: [
          _QuickAction(Icons.description_outlined, 'POs', () => onOpen('vendorPOs')),
          _QuickAction(Icons.inventory_2_outlined, 'Stock', () => onOpen('vendorStock')),
          _QuickAction(Icons.account_balance_wallet_outlined, 'Finance', () => onOpen('vendorFinance')),
          _QuickAction(Icons.warning_amber_outlined, 'Respond', () => onOpen('vendorAlert')),
        ]),
      ],
    );
  }
}

class DemoVendorAlert extends StatelessWidget {
  const DemoVendorAlert({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ScrollableScreen(
      topBar: _DemoTopBar(title: 'Alert response', subtitle: 'BJ-FRM-2104 cover'),
      children: [
        _AlertCard(
          kind: 'bad',
          title: 'Cover drops to 0.8 days',
          body: 'Confirm whether 1,200 pcs can dispatch by 16:00 today.',
        ),
        _InfoCard(rows: [
          _InfoRow('Required qty', '1,200 pcs'),
          _InfoRow('Current Yeshshree stock', '940 pcs'),
          _InfoRow('Truck cut-off', '16:00'),
        ]),
      ],
    );
  }
}

class DemoVendorPos extends StatelessWidget {
  const DemoVendorPos({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ScrollableScreen(
      topBar: _DemoTopBar(title: 'Purchase orders', subtitle: '18 open'),
      children: [
        _PoCard('PO 4500218812', 'BJ-FRM-2104', '1,240 pcs', 'Due today', 'red'),
        _PoCard('PO 4500218755', 'BJ-ARM-4410', '620 pcs', 'Due 14 Jun', 'amber'),
        _PoCard('PO 4500218701', 'BJ-HUB-1188', '1,000 pcs', 'Due 17 Jun', 'green'),
      ],
    );
  }
}

class DemoVendorFinance extends StatelessWidget {
  const DemoVendorFinance({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ScrollableScreen(
      topBar: _DemoTopBar(title: 'Financial position', subtitle: 'Tirupati Metals'),
      children: [
        _InfoCard(rows: [
          _InfoRow('Outstanding', 'INR 18.4 L'),
          _InfoRow('Debit notes open', 'INR 1.2 L'),
          _InfoRow('Credit limit used', '72%'),
          _InfoRow('Last payment', 'INR 6.0 L - 10 Jun'),
        ]),
        _AlertCard(
          kind: 'warn',
          title: 'Limit watch',
          body: 'A large vendor-sale issue may need approval if current invoices post.',
        ),
      ],
    );
  }
}

class DemoVendorStock extends StatelessWidget {
  const DemoVendorStock({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ScrollableScreen(
      topBar: _DemoTopBar(title: 'Yeshshree stock', subtitle: 'Vendor material cover'),
      children: [
        _StockCard('BJ-FRM-2104', '940 pcs', '0.8 d', 'red'),
        _StockCard('BJ-ARM-4410', '2,410 pcs', '3.5 d', 'amber'),
        _StockCard('BJ-HUB-1188', '5,880 pcs', '8.0 d', 'green'),
      ],
    );
  }
}

class DemoMgmtHome extends StatelessWidget {
  const DemoMgmtHome({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return _ScrollableScreen(
      header: _HeroHeader(
        eyebrow: 'MANAGEMENT',
        title: 'Pulse dashboard',
        subtitle: 'Plant 1 - live from SAP outbox and app events',
        notificationCount: 7,
        onBell: () => onOpen('notifications'),
        stats: const [
          _HeaderStat('ACHV', '91%', YColors.green),
          _HeaderStat('OPEN', '12', YColors.amber),
          _HeaderStat('BLOCKED', '3', YColors.red),
        ],
      ),
      children: [
        _QuickGrid(actions: [
          _QuickAction(Icons.verified_outlined, 'Approvals', () => onOpen('approvals')),
          _QuickAction(Icons.local_shipping_outlined, 'Vendors', () => onOpen('vendorPerf')),
          _QuickAction(Icons.warning_amber_outlined, 'Anomaly', () => onOpen('drift')),
          _QuickAction(Icons.notifications_outlined, 'Alerts', () => onOpen('notifications')),
        ]),
        const _SectionTitle('Today at a glance'),
        const _InfoCard(rows: [
          _InfoRow('Output achievement', '91%'),
          _InfoRow('Dispatch value', 'INR 42.6 L'),
          _InfoRow('Yield loss', '2.8%'),
          _InfoRow('SAP pending outbox', '18 rows'),
        ]),
      ],
    );
  }
}

class DemoApprovals extends StatelessWidget {
  const DemoApprovals({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return _ScrollableScreen(
      topBar: const _DemoTopBar(title: 'Approvals inbox', subtitle: '5 pending'),
      children: [
        _ApprovalCard(
          title: 'Debit waiver request',
          subtitle: 'Shortage debit INR 42,500 - Shakti Forge',
          status: 'red',
          onTap: () => onOpen('approvalDetail'),
        ),
        _ApprovalCard(
          title: 'Credit limit override',
          subtitle: 'Tirupati Metals vendor issue crosses 80%',
          status: 'amber',
          onTap: () => onOpen('approvalDetail'),
        ),
      ],
    );
  }
}

class DemoApprovalDetail extends StatelessWidget {
  const DemoApprovalDetail({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ScrollableScreen(
      topBar: _DemoTopBar(title: 'Approval detail', subtitle: 'Debit waiver'),
      children: [
        _DarkCard(
          eyebrow: 'REQUIRES MANAGEMENT',
          title: 'Shortage debit waiver',
          body: '50 pcs shortage at 5x debit policy. Vendor disputes transporter count.',
        ),
        _InfoCard(rows: [
          _InfoRow('Amount', 'INR 42,500'),
          _InfoRow('Requested by', 'QC Head'),
          _InfoRow('Vendor', 'Shakti Forge Pvt Ltd'),
          _InfoRow('Audit trail', 'Gate, QC and PO match attached'),
        ]),
      ],
    );
  }
}

class DemoVendorPerf extends StatelessWidget {
  const DemoVendorPerf({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ScrollableScreen(
      topBar: _DemoTopBar(title: 'Vendor performance', subtitle: 'Top risk suppliers'),
      children: [
        _StockCard('Shakti Forge', '92% OTIF', '2 debits', 'amber'),
        _StockCard('Tirupati Metals', '86% OTIF', '1 cover alert', 'red'),
        _StockCard('Access Weld', '98% OTIF', 'clean', 'green'),
      ],
    );
  }
}

class DemoNotifications extends StatelessWidget {
  const DemoNotifications({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ScrollableScreen(
      topBar: _DemoTopBar(title: 'Notifications', subtitle: '5 new - 23 today'),
      children: [
        _AlertCard(
          kind: 'bad',
          title: 'Line B cover below one day',
          body: 'Vendor response needed for BJ-FRM-2104.',
        ),
        _AlertCard(
          kind: 'warn',
          title: 'Schedule sanity check',
          body: 'Capacity breach on Friday shift.',
        ),
        _AlertCard(
          kind: 'ok',
          title: 'GR posted',
          body: 'GE-240611-0042 accepted and queued for SAP.',
        ),
      ],
    );
  }
}

class DemoProfile extends StatelessWidget {
  const DemoProfile({
    super.key,
    required this.role,
    required this.onSwitchRole,
    required this.onSignOut,
  });

  final String role;
  final VoidCallback onSwitchRole;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return _ScrollableScreen(
      topBar: const _DemoTopBar(title: 'Me', subtitle: 'Rajesh Kulkarni'),
      children: [
        _InfoCard(rows: [
          const _InfoRow('Employee', 'YS-0428'),
          _InfoRow('Active role', _roleLabel(role)),
          const _InfoRow('Plant', 'Plant 1, Chakan'),
          const _InfoRow('SAP sync', 'Live - 14s ago'),
          const _InfoRow('App version', 'v1.0.0-pilot'),
        ]),
        OutlinedButton.icon(
          onPressed: onSwitchRole,
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Switch role'),
        ),
        OutlinedButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout),
          style: OutlinedButton.styleFrom(foregroundColor: YColors.red),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

class _ScrollableScreen extends StatelessWidget {
  const _ScrollableScreen({
    this.header,
    this.topBar,
    required this.children,
  });

  final Widget? header;
  final Widget? topBar;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _DemoPage(
      background: YColors.bg,
      header: topBar,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (header != null) header!,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoPage extends StatelessWidget {
  const _DemoPage({
    required this.body,
    this.header,
    this.background = YColors.bg,
  });

  final Widget? header;
  final Widget body;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: background,
      child: Column(
        children: [
          if (header != null) header!,
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _DemoTopBar extends StatelessWidget {
  const _DemoTopBar({
    required this.title,
    this.subtitle,
    this.dark = false,
    this.onBack,
    this.action,
  });

  final String title;
  final String? subtitle;
  final bool dark;
  final VoidCallback? onBack;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? Colors.black : Colors.white;
    final fg = dark ? Colors.white : YColors.ink;
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: fg, size: 18),
            onPressed: onBack ?? () {},
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dark ? Colors.white60 : YColors.muted,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.stats,
    this.notificationCount,
    this.onBell,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final List<_HeaderStat> stats;
  final int? notificationCount;
  final VoidCallback? onBell;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: YColors.navy,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onBell,
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.notifications_none,
                          color: Colors.white, size: 24),
                    ),
                    if (notificationCount != null)
                      Positioned(
                        right: 2,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: YColors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$notificationCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (final stat in stats)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .08),
                      border: Border.all(color: Colors.white12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: stat.color,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                stat.label,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stat.value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStat {
  const _HeaderStat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;
}

class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.actions});

  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return _PlainCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          for (final action in actions)
            Expanded(
              child: InkWell(
                onTap: action.onTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: YColors.navy.withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(action.icon, color: YColors.navy, size: 21),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        action.label,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: YColors.ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _PlainCard extends StatelessWidget {
  const _PlainCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? YColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, child: card);
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _PlainCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: YColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: YColors.muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          trailing ??
              const Icon(Icons.chevron_right, color: YColors.muted, size: 20),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.code,
    required this.title,
    required this.done,
    required this.plan,
    required this.due,
    required this.cover,
    required this.status,
  });

  final String code;
  final String title;
  final String done;
  final String plan;
  final String due;
  final String cover;
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return _PlainCard(
      borderColor: color.withValues(alpha: .28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 88,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        code,
                        style: const TextStyle(
                          color: YColors.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _MiniBadge(status.toUpperCase(), color: color),
                  ],
                ),
                Text(title,
                    style:
                        const TextStyle(color: YColors.muted, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      done,
                      style: const TextStyle(
                        color: YColors.navy,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '/ $plan',
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: YColors.muted, fontSize: 12),
                      ),
                    ),
                    Text(
                      'Due $due - Cover $cover',
                      style: const TextStyle(
                          color: YColors.muted, fontSize: 10.5),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: status == 'green'
                        ? .96
                        : status == 'amber'
                            ? .66
                            : .48,
                    backgroundColor: YColors.line,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FlagCard extends StatelessWidget {
  const _FlagCard({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.cover,
    required this.onTap,
  });

  final String id;
  final String title;
  final String subtitle;
  final String status;
  final String cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return _PlainCard(
      onTap: onTap,
      borderColor: color.withValues(alpha: .28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_outlined, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(id,
                    style:
                        const TextStyle(color: YColors.muted, fontSize: 11)),
                Text(
                  title,
                  style: const TextStyle(
                    color: YColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(subtitle,
                    style:
                        const TextStyle(color: YColors.muted, fontSize: 12)),
                const SizedBox(height: 8),
                Text(
                  'Cover $cover - Recommend 34 MT by Friday',
                  style: const TextStyle(color: YColors.ink, fontSize: 12),
                ),
              ],
            ),
          ),
          _MiniBadge(status, color: color),
        ],
      ),
    );
  }
}

class _DetectedCard extends StatelessWidget {
  const _DetectedCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PlainCard(
      onTap: onTap,
      child: const Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: YColors.greenBg,
            foregroundColor: YColors.green,
            child: Icon(Icons.check),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QR MATCHED',
                  style: TextStyle(
                    color: YColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Shakti Forge - INV-2026-2841',
                  style: TextStyle(
                    color: YColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: YColors.muted),
        ],
      ),
    );
  }
}

class _DarkCard extends StatelessWidget {
  const _DarkCard({
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  final String eyebrow;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: YColors.navy,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(body,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.kind,
    required this.title,
    required this.body,
    this.onTap,
  });

  final String kind;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(kind);
    return _PlainCard(
      onTap: onTap,
      borderColor: color.withValues(alpha: .35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 54,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return _PlainCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : const Border(bottom: BorderSide(color: YColors.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[i].label,
                      style:
                          const TextStyle(color: YColors.muted, fontSize: 12),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      rows[i].value,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: YColors.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoRow {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;
}

class _PoCard extends StatelessWidget {
  const _PoCard(this.po, this.part, this.qty, this.due, this.status);

  final String po;
  final String part;
  final String qty;
  final String due;
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return _PlainCard(
      child: Row(
        children: [
          Icon(Icons.description_outlined, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(po,
                    style: const TextStyle(
                        color: YColors.ink, fontWeight: FontWeight.w900)),
                Text('$part - $qty',
                    style:
                        const TextStyle(color: YColors.muted, fontSize: 12)),
              ],
            ),
          ),
          _MiniBadge(due, color: color),
        ],
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard(this.title, this.value, this.meta, this.status);

  final String title;
  final String value;
  final String meta;
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return _PlainCard(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .12),
            foregroundColor: color,
            child: const Icon(Icons.inventory_2_outlined),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: YColors.ink, fontWeight: FontWeight.w800)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: const TextStyle(
                      color: YColors.ink, fontWeight: FontWeight.w900)),
              Text(meta,
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return _ActionCard(
      icon: Icons.verified_user_outlined,
      iconColor: color,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: _MiniBadge('Review', color: color),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge(this.label, {required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: YColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _YMark extends StatelessWidget {
  const _YMark({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          size: Size(size, size),
          painter: _YMarkPainter(color),
        ),
      ),
    );
  }
}

class _YMarkPainter extends CustomPainter {
  const _YMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * .18, size.height * .16)
      ..lineTo(size.width * .5, size.height * .48)
      ..lineTo(size.width * .82, size.height * .16)
      ..moveTo(size.width * .5, size.height * .48)
      ..lineTo(size.width * .5, size.height * .86);
    canvas.drawPath(path, paint);
    canvas.drawCircle(
      Offset(size.width * .5, size.height * .5),
      size.width * .45,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _YMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

Color _statusColor(String status) {
  return switch (status) {
    'red' || 'bad' => YColors.red,
    'amber' || 'warn' => YColors.amber,
    'green' || 'ok' => YColors.green,
    _ => YColors.blue,
  };
}

String? _roleForScreen(String screen) {
  if (screen.startsWith('vendor')) return 'vendor';
  if (screen.startsWith('mgmt') ||
      const {'approvals', 'approvalDetail', 'vendorPerf'}.contains(screen)) {
    return 'mgmt';
  }
  if (screen.startsWith('planning') ||
      const {'millDetail', 'scheduleDiff', 'drift'}.contains(screen)) {
    return 'planning';
  }
  if (screen.startsWith('ops') ||
      const {'gateScan', 'gateConfirm', 'qcReceipt', 'issue'}.contains(screen)) {
    return 'ops';
  }
  return null;
}

String _activeTab(String role, String screen) {
  if (screen == 'profile') return 'me';
  if (screen == 'notifications') return role == 'ops' ? 'alerts' : 'home';
  return switch (role) {
    'planning' => switch (screen) {
        'scheduleDiff' => 'schedule',
        'drift' => 'anomalies',
        _ => 'home',
      },
    'vendor' => switch (screen) {
        'vendorPOs' => 'pos',
        'vendorStock' => 'stock',
        'vendorFinance' => 'finance',
        _ => 'home',
      },
    'mgmt' => switch (screen) {
        'approvals' || 'approvalDetail' => 'approvals',
        'vendorPerf' => 'vendors',
        'drift' => 'anomalies',
        _ => 'home',
      },
    _ => switch (screen) {
        'gateScan' || 'gateConfirm' || 'qcReceipt' || 'issue' => 'scan',
        'notifications' => 'alerts',
        _ => 'home',
      },
  };
}

String _roleLabel(String role) {
  return switch (role) {
    'planning' => 'Planning',
    'vendor' => 'Component Vendor',
    'mgmt' => 'Management',
    _ => 'Plant Operations',
  };
}

const _roleHome = {
  'ops': 'opsHome',
  'planning': 'planningHome',
  'vendor': 'vendorHome',
  'mgmt': 'mgmtHome',
};

const _tabsByRole = {
  'ops': [
    _DemoTab('home', 'Plan', Icons.home_outlined, 'opsHome'),
    _DemoTab('tasks', 'Tasks', Icons.checklist_outlined, 'opsHome'),
    _DemoTab('scan', 'Scan', Icons.qr_code_scanner, 'gateScan', center: true),
    _DemoTab('alerts', 'Alerts', Icons.notifications_none, 'notifications'),
    _DemoTab('me', 'Me', Icons.person_outline, 'profile'),
  ],
  'planning': [
    _DemoTab('home', 'Flags', Icons.flag_outlined, 'planningHome'),
    _DemoTab('schedule', 'Schedule', Icons.calendar_month_outlined, 'scheduleDiff'),
    _DemoTab('anomalies', 'Anomaly', Icons.warning_amber_outlined, 'drift'),
    _DemoTab('me', 'Me', Icons.person_outline, 'profile'),
  ],
  'vendor': [
    _DemoTab('home', 'Home', Icons.home_outlined, 'vendorHome'),
    _DemoTab('pos', 'POs', Icons.description_outlined, 'vendorPOs'),
    _DemoTab('stock', 'Stock', Icons.inventory_2_outlined, 'vendorStock'),
    _DemoTab('finance', 'Finance', Icons.account_balance_wallet_outlined,
        'vendorFinance'),
    _DemoTab('me', 'Me', Icons.person_outline, 'profile'),
  ],
  'mgmt': [
    _DemoTab('home', 'Pulse', Icons.query_stats, 'mgmtHome'),
    _DemoTab('approvals', 'Approve', Icons.verified_outlined, 'approvals'),
    _DemoTab('vendors', 'Vendors', Icons.local_shipping_outlined, 'vendorPerf'),
    _DemoTab('anomalies', 'Anomaly', Icons.warning_amber_outlined, 'drift'),
    _DemoTab('me', 'Me', Icons.person_outline, 'profile'),
  ],
};

class _DemoTab {
  const _DemoTab(this.id, this.label, this.icon, this.screen,
      {this.center = false});
  final String id;
  final String label;
  final IconData icon;
  final String screen;
  final bool center;
}

class _RoleCardData {
  const _RoleCardData(
      this.id, this.title, this.subtitle, this.icon, this.color);
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

const _roleCards = [
  _RoleCardData('ops', 'Plant Operations', 'Gate - QC - Store - Line',
      Icons.factory_outlined, Color(0xFF0EA5E9)),
  _RoleCardData('planning', 'Planning', 'Cascade - Mills - Config',
      Icons.calendar_month_outlined, Color(0xFF7C3AED)),
  _RoleCardData('vendor', 'Component Vendor', 'Schedule - POs - Finance',
      Icons.local_shipping_outlined, Color(0xFF16A34A)),
  _RoleCardData('mgmt', 'Management', 'Dashboards - Approvals',
      Icons.query_stats, Color(0xFFD97706)),
];

class _JumpGroup {
  const _JumpGroup(this.title, this.items);
  final String title;
  final List<_JumpItem> items;
}

class _JumpItem {
  const _JumpItem(this.id, this.label, this.icon, this.color);
  final String id;
  final String label;
  final IconData icon;
  final Color color;
}

const _jumpGroups = [
  _JumpGroup('Onboarding', [
    _JumpItem('login', 'Login', Icons.login, YColors.navy),
    _JumpItem('otp', 'OTP verify', Icons.pin_outlined, YColors.navy),
    _JumpItem('roleSelect', 'Role selector', Icons.badge_outlined, YColors.navy),
  ]),
  _JumpGroup('Plant Ops', [
    _JumpItem('opsHome', "Home - today's plan", Icons.factory_outlined,
        Color(0xFF0EA5E9)),
    _JumpItem('gateScan', 'Gate scan', Icons.qr_code_scanner, Color(0xFF0EA5E9)),
    _JumpItem('gateConfirm', 'Gate confirm', Icons.fact_check_outlined,
        Color(0xFF0EA5E9)),
    _JumpItem('qcReceipt', 'QC receipt + anomaly', Icons.inventory_outlined,
        Color(0xFF0EA5E9)),
    _JumpItem('issue', 'Material issue', Icons.call_made, Color(0xFF0EA5E9)),
  ]),
  _JumpGroup('Planning', [
    _JumpItem('planningHome', 'Mill flag inbox', Icons.flag_outlined,
        Color(0xFF7C3AED)),
    _JumpItem('millDetail', 'Mill flag detail', Icons.stacked_line_chart,
        Color(0xFF7C3AED)),
    _JumpItem('scheduleDiff', 'Schedule diff & release',
        Icons.calendar_month_outlined, Color(0xFF7C3AED)),
    _JumpItem('drift', 'Anomaly register', Icons.warning_amber_outlined,
        Color(0xFF7C3AED)),
  ]),
  _JumpGroup('Vendor', [
    _JumpItem('vendorHome', 'Home + critical alert', Icons.home_outlined,
        Color(0xFF16A34A)),
    _JumpItem('vendorAlert', 'Alert response', Icons.warning_amber_outlined,
        Color(0xFF16A34A)),
    _JumpItem('vendorPOs', 'Purchase orders', Icons.description_outlined,
        Color(0xFF16A34A)),
    _JumpItem('vendorFinance', 'Financial position',
        Icons.account_balance_wallet_outlined, Color(0xFF16A34A)),
    _JumpItem('vendorStock', 'Yeshshree stock', Icons.inventory_2_outlined,
        Color(0xFF16A34A)),
  ]),
  _JumpGroup('Management', [
    _JumpItem('mgmtHome', 'Dashboard pulse', Icons.query_stats,
        Color(0xFFD97706)),
    _JumpItem('approvals', 'Approvals inbox', Icons.verified_outlined,
        Color(0xFFD97706)),
    _JumpItem('approvalDetail', 'Approval detail', Icons.rule_folder_outlined,
        Color(0xFFD97706)),
    _JumpItem('vendorPerf', 'Vendor performance', Icons.local_shipping_outlined,
        Color(0xFFD97706)),
  ]),
  _JumpGroup('Shared', [
    _JumpItem('notifications', 'Notifications', Icons.notifications_none,
        YColors.blue),
    _JumpItem('profile', 'Profile / Me', Icons.person_outline, YColors.blue),
  ]),
];
