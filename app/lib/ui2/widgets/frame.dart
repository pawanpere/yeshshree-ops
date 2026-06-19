import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../tokens.dart';
import 'icons2.dart';

/// Device shell: bezel + notch + inner screen surface, hosting a full screen
/// column (status bar → content → tab bar) at the prototype's 336×706 size.
class PhoneFrame2 extends StatelessWidget {
  const PhoneFrame2({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 336,
      height: 706,
      decoration: BoxDecoration(
        color: Y2.navyEdge,
        borderRadius: BorderRadius.circular(Y2.rFrame),
        boxShadow: Y2.shFrame,
      ),
      padding: const EdgeInsets.all(9),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Y2.rScreen),
              child: ColoredBox(color: Y2.screen, child: child),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: 128,
              height: 26,
              decoration: const BoxDecoration(
                color: Y2.navyEdge,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Top status row: clock (mono) + signal bars.
class StatusBar2 extends StatelessWidget {
  const StatusBar2({super.key, this.clock = '14:32'});
  final String clock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 36, 18, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(clock, style: F.mono(13)),
          const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(I2.signal, size: 15, color: Y2.muted),
            SizedBox(width: 5),
            Icon(I2.wifi, size: 15, color: Y2.muted),
            SizedBox(width: 5),
            Icon(I2.battery, size: 16, color: Y2.muted),
          ]),
        ],
      ),
    );
  }
}

class _Tab {
  const _Tab(this.en, this.mr, this.icon, this.activeIcon);
  final String en;
  final String mr;
  final IconData icon;
  final IconData activeIcon;
}

/// Bottom 5-tab bar (Home / Tasks / Sync / Alerts / Me).
class BottomTabs2 extends StatelessWidget {
  const BottomTabs2({super.key, required this.active, this.onTap});
  final int active;
  final ValueChanged<int>? onTap;

  static const _tabs = [
    _Tab('Home', 'मुख्य', I2.home, I2.homeActive),
    _Tab('Tasks', 'कामे', I2.tasks, I2.tasks),
    _Tab('Sync', 'सिंक', I2.sync, I2.sync),
    _Tab('Alerts', 'सूचना', I2.alerts, I2.alertsActive),
    _Tab('Me', 'मी', I2.me, I2.meActive),
  ];

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
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap == null ? null : () => onTap!(i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Icon(
                        i == active ? _tabs[i].activeIcon : _tabs[i].icon,
                        size: 23,
                        color: i == active ? Y2.accent : Y2.muted,
                      ),
                    ),
                    Text(
                      S.t(_tabs[i].en, _tabs[i].mr),
                      style: F.hind(9,
                          w: FontWeight.w600,
                          color: i == active ? Y2.accent : Y2.muted),
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
