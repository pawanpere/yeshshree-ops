import 'package:flutter/material.dart';

import 'package:flutter/widgets.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';

/// Placeholder shown for screens not yet implemented. Replaced file-by-file by
/// the build-out. Keeps the shell navigable while screens land.
class StubScreen extends StatelessWidget {
  const StubScreen(
      {super.key, required this.nav, required this.title, this.tab});
  final PhoneNav nav;
  final String title;
  final int? tab;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        if (tab == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 16, 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: nav.pop,
              child: Row(children: [
                Text('‹', style: F.khand(22, color: Y2.muted)),
                const SizedBox(width: 6),
                Text(title, style: F.khand(16, color: Y2.ink)),
              ]),
            ),
          ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Y2.lineSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Y2.line),
                  ),
                ),
                const SizedBox(height: 12),
                Text(title, style: F.khand(18, color: Y2.ink)),
                const SizedBox(height: 4),
                Text('screen pending', style: F.hind(12, color: Y2.muted)),
              ],
            ),
          ),
        ),
        if (tab != null) BottomTabs2(active: tab!, onTap: nav.tab),
      ],
    );
  }
}
