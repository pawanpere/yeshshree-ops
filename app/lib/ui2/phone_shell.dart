import 'package:flutter/material.dart';

import 'nav.dart';
import 'screen_registry.dart';
import 'widgets/correction_sheet.dart';

/// The running phone app: a 5-tab shell with a per-tab navigation stack and an
/// in-frame modal-sheet layer. Implements [PhoneNav] so any screen can drive
/// navigation without knowing about the others.
class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key, this.initial, this.initialSheet});

  /// Screen to land on (deep-link / dev jump-nav). Tab roots select their tab;
  /// anything else is pushed on top of the Home tab.
  final ScreenId? initial;
  final SheetId? initialSheet;

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> implements PhoneNav {
  static const _roots = [
    ScreenId.home,
    ScreenId.tasks,
    ScreenId.sync,
    ScreenId.notifications,
    ScreenId.profile,
  ];

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
        // Sit drill-downs on top of Home so the back chevron has somewhere to go.
        _tab = 0;
        _stacks[0] = [ScreenId.home, init];
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
  void pop() => setState(() {
        if (_stack.length > 1) _stack.removeLast();
      });

  @override
  void tab(int index) => setState(() {
        _tab = index;
        _stacks[index] = [_roots[index]];
        _sheet = null;
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
    return Stack(
      children: [
        Positioned.fill(child: buildScreen(_stack.last, this)),
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
