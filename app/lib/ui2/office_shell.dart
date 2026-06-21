import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_state.dart';
import '../core/strings.dart';
import 'data/flow.dart';
import 'nav.dart';
import 'responsive.dart';
import 'roles.dart';
import 'screen_registry.dart';
import 'tokens.dart';
import 'widgets/correction_sheet.dart';
import 'widgets/lang_toggle.dart';

/// Responsive office shell for the management / planning / admin roles. Wide
/// viewports get a persistent left sidebar; narrow get a drawer. Full-viewport
/// (NOT inside the phone frame), reuses the ui2 design system. Implements
/// [PhoneNav] so the same screens work here as in the phone shell.
class OfficeShell extends ConsumerStatefulWidget {
  const OfficeShell({super.key, required this.spec, this.initial});
  final RoleSpec spec;

  /// Optional deep-link target (dev `?screen=`). A section root selects its
  /// section; anything else is pushed on top of the first section so back works.
  final ScreenId? initial;

  @override
  ConsumerState<OfficeShell> createState() => _OfficeShellState();
}

class _OfficeShellState extends ConsumerState<OfficeShell>
    implements PhoneNav {
  List<RoleTab> get _tabs => widget.spec.tabs;
  late final List<ScreenId> _roots = [for (final t in _tabs) t.id];
  late final List<List<ScreenId>> _stacks = [
    for (final r in _roots) [r]
  ];
  int _section = 0;
  SheetId? _sheet;
  Widget? _overlay;

  List<ScreenId> get _stack => _stacks[_section];

  @override
  void initState() {
    super.initState();
    // Deep-link (?screen=): land a section root on its section, or push a
    // drill-down on top of the first section so back has somewhere to go.
    final init = widget.initial;
    if (init != null) {
      final si = _roots.indexOf(init);
      if (si >= 0) {
        _section = si;
      } else {
        _stacks[0] = [_roots[0], init];
      }
    }
  }

  // ---- PhoneNav ----
  @override
  void go(ScreenId id) => setState(() => _stack.add(id));
  @override
  void replace(ScreenId id) => setState(() => _stack[_stack.length - 1] = id);
  @override
  void pop() {
    if (_stack.length > 1) {
      setState(() => _stack.removeLast());
      return;
    }
    // A flow step replaced onto a section root → return to THIS section's own
    // root, not home() (which would clear staged flow state).
    if (_stack.last != _roots[_section]) {
      setState(() => _stacks[_section] = [_roots[_section]]);
      return;
    }
    if (_section != 0) home();
  }
  @override
  void tab(int index) => setState(() {
        _section = index.clamp(0, _roots.length - 1);
        _stacks[_section] = [_roots[_section]];
        _sheet = null;
        _overlay = null;
        // A section is an independent task root: switching ends the current flow,
        // so reset the process-global flow bag (parity with PhoneShell.tab) — else
        // staged context (e.g. a consumed gate.entryId) leaks across sections.
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

  void _toggleLang() => toggleLanguage(context);
  void _switchRole() => ref.read(activeRoleProvider.notifier).state = null;
  Future<void> _signOut() async {
    await ref.read(authProvider.notifier).logout();
    if (mounted) ref.read(activeRoleProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 820;
      final title = S.t(_tabs[_section].en, _tabs[_section].mr);
      if (wide) {
        return ColoredBox(
          color: Y2.screen,
          child: Row(
            children: [
              SizedBox(width: 236, child: _navColumn(inDrawer: false)),
              Expanded(
                child: Column(
                  children: [
                    _topStrip(title, showMenu: false),
                    Expanded(child: _content()),
                  ],
                ),
              ),
            ],
          ),
        );
      }
      return Scaffold(
        backgroundColor: Y2.screen,
        drawer: Drawer(
          backgroundColor: Colors.white,
          child: SafeArea(child: _navColumn(inDrawer: true)),
        ),
        body: Column(
          children: [
            _topStrip(title, showMenu: true),
            Expanded(child: _content()),
          ],
        ),
      );
    });
  }

  Widget _content() => Stack(
        children: [
          // Cap content width on very wide monitors so screens don't stretch
          // edge-to-edge; pass-through on narrow boxes (preserves height contract).
          Positioned.fill(
            child: ResponsiveContent(child: buildScreen(_stack.last, this)),
          ),
          if (_sheet != null) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: closeSheet,
                child: const ColoredBox(color: Color(0x8C11243F)),
              ),
            ),
            Align(
                alignment: Alignment.bottomCenter,
                child: CorrectionSheet2(
                    onClose: closeSheet, onPost: closeSheet)),
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

  Widget _topStrip(String title, {required bool showMenu}) => Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Y2.line)),
        ),
        child: Row(
          children: [
            if (showMenu)
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Y2.ink),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.khand(18, ls: 0.3, color: Y2.ink)),
            ),
            _langButton(),
          ],
        ),
      );

  Widget _navColumn({required bool inDrawer}) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: inDrawer
              ? null
              : const Border(right: BorderSide(color: Y2.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand + role
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Y2.accent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(widget.spec.icon, size: 19, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(S.t(widget.spec.en, widget.spec.mr),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: F.khand(17, color: Y2.ink)),
                        Text('Yeshshree Ops',
                            style: F.hind(10, color: Y2.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Y2.line),
            const SizedBox(height: 8),
            for (var i = 0; i < _tabs.length; i++)
              _navItem(i, inDrawer: inDrawer),
            const Spacer(),
            const Divider(height: 1, color: Y2.line),
            _actionRow(Icons.swap_horiz, S.t('Switch role', 'भूमिका बदला'),
                () {
              if (inDrawer) Navigator.of(context).pop();
              _switchRole();
            }),
            _actionRow(Icons.logout, S.t('Sign out', 'साइन आउट'), () {
              if (inDrawer) Navigator.of(context).pop();
              _signOut();
            }),
            const SizedBox(height: 10),
          ],
        ),
      );

  Widget _navItem(int i, {required bool inDrawer}) {
    final active = i == _section;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (inDrawer) Navigator.of(context).pop();
        tab(i);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        decoration: BoxDecoration(
          color: active ? const Color(0x141D4ED8) : null,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Icon(_tabs[i].icon,
                size: 20, color: active ? Y2.accent : Y2.muted),
            const SizedBox(width: 11),
            Expanded(
              child: Text(S.t(_tabs[i].en, _tabs[i].mr),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.hind(14,
                      w: FontWeight.w600,
                      color: active ? Y2.accent : Y2.ink)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Y2.muted),
              const SizedBox(width: 12),
              Text(label, style: F.hind(13, w: FontWeight.w600, color: Y2.body)),
            ],
          ),
        ),
      );

  Widget _langButton() => GestureDetector(
        onTap: _toggleLang,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: Y2.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(S.lang.value == 'mr' ? 'EN' : 'मराठी',
              style: F.hind(12, w: FontWeight.w700, color: Y2.ink)),
        ),
      );
}
