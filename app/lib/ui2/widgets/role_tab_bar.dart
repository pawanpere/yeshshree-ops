import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../roles.dart';
import '../tokens.dart';

/// Bottom nav driven by a role's tab list (replaces the fixed BottomTabs2). The
/// shell owns and renders this; screens are pure content.
class RoleTabBar extends StatelessWidget {
  const RoleTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onTap,
  });
  final List<RoleTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Y2.line)),
      ),
      padding: const EdgeInsets.fromLTRB(0, 9, 0, 20),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Icon(tabs[i].icon,
                          size: 23,
                          color: i == activeIndex ? Y2.accent : Y2.muted),
                    ),
                    Text(
                      S.t(tabs[i].en, tabs[i].mr),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.hind(9,
                          w: FontWeight.w600,
                          color: i == activeIndex ? Y2.accent : Y2.muted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
