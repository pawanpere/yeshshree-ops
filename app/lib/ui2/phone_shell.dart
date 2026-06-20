import 'package:flutter/material.dart';

import 'data/flow.dart';
import 'nav.dart';
import 'roles.dart';
import 'screen_registry.dart';
import 'widgets/correction_sheet.dart';
import 'widgets/icons2.dart';
import 'widgets/role_tab_bar.dart';

/// The legacy 5-tab set, used when no role tabs are supplied (e.g. the
/// render-stress test, which pumps PhoneShell directly).
const _legacyTabs = <RoleTab>[
  RoleTab(ScreenId.home, I2.home, 'Home', 'मुख्य'),
  RoleTab(ScreenId.tasks, I2.tasks, 'Tasks', 'कामे'),
  RoleTab(ScreenId.sync, I2.sync, 'Sync', 'सिंक'),
  RoleTab(ScreenId.notifications, I2.alerts, 'Alerts', 'सूचना'),
  RoleTab(ScreenId.profile, I2.me, 'Me', 'मी'),
];

/// The running phone app: a bottom-tab shell with a per-tab navigation stack and
/// an in-frame modal/overlay layer. The shell OWNS the tab bar (driven by the
/// role's [tabs]) — screens are pure content. Implements [PhoneNav] so any
/// screen can drive navigation without knowing about the others.
class PhoneShell extends StatefulWidget {
  const PhoneShell({
    super.key,
    this.initial,
    this.initialSheet,
    this.tabs = _legacyTabs,
  });

  /// Screen to land on (deep-link / dev jump-nav). A tab root selects its tab;
  /// anything else is pushed on top of the first (home) tab.
  final ScreenId? initial;
  final SheetId? initialSheet;

  /// The role's navigation tabs (first = home). Defaults to the legacy set.
  final List<RoleTab> tabs;

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> implements PhoneNav {
  late final List<ScreenId> _roots = [for (final t in widget.tabs) t.id];

  late List<List<ScreenId>> _stacks;
  int _tab = 0;
  SheetId? _sheet;
  Widget? _overlay;

  @override
  void initState() {
    super.initState();
    _stacks = [
      for (final r in _roots) [r]
    ];
    _sheet = widget.initialSheet;
    final init = widget.initial;
    if (init != null) {
      final ti = _roots.indexOf(init);
      if (ti >= 0) {
        _tab = ti;
      } else {
        // Sit drill-downs on top of the home tab so back has somewhere to go.
        _tab = 0;
        _stacks[0] = [_roots[0], init];
      }
    }
  }

  List<ScreenId> get _stack => _stacks[_tab];

  @override
  void go(ScreenId id) => setState(() => _stack.add(id));

  @override
  void replace(ScreenId id) =>
      setState(() => _stack[_stack.length - 1] = id);

  @override
  void pop() {
    if (_stack.length > 1) {
      setState(() => _stack.removeLast());
      return;
    }
    // Depth-1 stack. Forward flows advance with replace(), so a flow STEP can sit
    // on a tab root (stack.last is then a non-root screen, e.g. gateQc/gateGrn).
    // Back there returns to THIS tab's own root — NOT home(), which would clear
    // all cross-screen flow state and discard the half-entered QC/GRN values.
    if (_stack.last != _roots[_tab]) {
      setState(() => _stacks[_tab] = [_roots[_tab]]);
      return;
    }
    // Genuinely on this tab's root: a non-home tab returns to the role's main
    // (home) screen; the home root has nothing above it, so back is a no-op there.
    if (_tab != 0) home();
  }

  @override
  void tab(int index) => setState(() {
        final i = index.clamp(0, _roots.length - 1);
        _tab = i;
        _stacks[i] = [_roots[i]];
        _sheet = null;
        _overlay = null;
        // A tab is an independent task root: switching (or re-tapping) one ends the
        // current flow, so reset ephemeral cross-screen flow state. Without this the
        // process-global Ui2Flow bag leaks context between tabs — e.g. a consumed
        // gate.entryId would let the Receipt tab re-receipt an already-received entry.
        Ui2Flow.clear('');
      });

  @override
  void home() => tab(0);

  @override
  void sheet(SheetId id) => setState(() => _sheet = id);

  @override
  void closeSheet() => setState(() => _sheet = null);

  @override
  void overlay(Widget child) => setState(() => _overlay = child);

  @override
  void hideOverlay() => setState(() => _overlay = null);

  @override
  Widget build(BuildContext context) {
    // Tab bar shows only on a tab-root screen; drill-downs/flows are full-screen.
    final showTabBar = _roots.contains(_stack.last);
    return Stack(
      children: [
        Column(
          children: [
            Expanded(child: buildScreen(_stack.last, this)),
            if (showTabBar)
              RoleTabBar(tabs: widget.tabs, activeIndex: _tab, onTap: tab),
          ],
        ),
        if (_sheet != null) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: closeSheet,
              child: const ColoredBox(color: Color(0x8C11243F)),
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: _sheetFor(_sheet!)),
        ],
        if (_overlay != null) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: hideOverlay,
              child: const ColoredBox(color: Color(0x8C11243F)),
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: _overlay!),
        ],
      ],
    );
  }

  Widget _sheetFor(SheetId id) => switch (id) {
        SheetId.correction =>
          CorrectionSheet2(onClose: closeSheet, onPost: closeSheet),
      };
}
