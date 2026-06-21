import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/lang_toggle.dart';
import '../widgets/polish2.dart';

/// Vendor portal home — prototype screen [29]. A different surface from the
/// operator app: a 4-tab vendor nav (Home / Orders / Stock / Money), no
/// operator [BottomTabs2] and no back chevron (this is the vendor root). The
/// EN/मराठी pill flips the app language; Orders/Stock reach their screens.
///
/// Phone: a single scrolling column (alert banner, two KPI tiles, drill-down
/// rows). Desktop: the same data widened into a KPI grid + a destinations grid
/// under a centered 1200px column. Both share the vendor header and every tile.
class Ui2VHomeScreen extends StatefulWidget {
  const Ui2VHomeScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2VHomeScreen> createState() => _Ui2VHomeScreenState();
}

class _Ui2VHomeScreenState extends State<Ui2VHomeScreen> {
  PhoneNav get nav => widget.nav;

  void _toggleLang() => toggleLanguage(context);

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- phone layout (single column, unchanged) ----

  Widget _phone() {
    return Column(
      children: [
        const StatusBar2(),
        _header(wide: false),
        // ---- Scrollable body ----
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _alert(),
                const SizedBox(height: 11),
                Row(children: [
                  Expanded(child: _stat('3', null, S.t('open orders', 'खुल्या ऑर्डर'))),
                  const SizedBox(width: 11),
                  Expanded(child: _due()),
                ]),
                const SizedBox(height: 11),
                // Tiles SWITCH tabs (not push), so the bottom nav stays in sync and
                // the tab bar is the way back. Vendor tabs: Home0 Alerts1 Stock2
                // Orders3 Money4.
                _navRow(
                    I2.invoice,
                    S.t('My orders & call-offs', 'माझ्या ऑर्डर व कॉल-ऑफ'),
                    () => nav.tab(3)),
                const SizedBox(height: 11),
                _navRow(I2.store, S.t('Stock & cover', 'स्टॉक व कव्हर'),
                    () => nav.tab(2)),
                const SizedBox(height: 11),
                _payments(),
              ],
            ),
          ),
        ),
        // Bottom nav is owned by the role shell (RoleTabBar) — no embedded one here.
      ],
    );
  }

  // ---- desktop layout (wide KPI grid + destinations grid) ----

  Widget _desktop() {
    return Column(
      children: [
        // No StatusBar2 on desktop — the vendor header is the top chrome.
        _header(wide: true),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: ResponsiveContent(
              maxWidth: 1200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _alert(),
                  const SizedBox(height: 16),
                  // KPIs widen into a 2–4 column grid instead of two squeezed
                  // tiles — same data, same Ticker2/₹ figures.
                  CardGrid2(
                    minTileWidth: 240,
                    children: [
                      _stat('3', null, S.t('open orders', 'खुल्या ऑर्डर')),
                      _due(),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(S.t('GO TO', 'इथे जा'),
                      style: F.hind(11,
                          w: FontWeight.w600, ls: 0.5, color: Y2.muted)),
                  const SizedBox(height: 10),
                  // Destinations as a card grid; each switches a vendor tab.
                  CardGrid2(
                    minTileWidth: 300,
                    children: [
                      _navRow(
                          I2.invoice,
                          S.t('My orders & call-offs',
                              'माझ्या ऑर्डर व कॉल-ऑफ'),
                          () => nav.tab(3)),
                      _navRow(I2.store, S.t('Stock & cover', 'स्टॉक व कव्हर'),
                          () => nav.tab(2)),
                      _payments(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // Bottom nav is owned by the role shell (RoleTabBar) — no embedded one here.
      ],
    );
  }

  // ---- shared vendor header (name + portal sub + demo + lang pill) ----

  Widget _header({required bool wide}) {
    return Container(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 8, wide ? 24 : 16, 12),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Y2.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MAHALAXMI COMPONENTS',
                    style: F.khand(19, ls: 0.3, height: 1, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                            S.t('Component supplier · Yeshshree',
                                'घटक पुरवठादार · येशश्री'),
                            style: F.hind(11, color: Y2.muted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Icon(I2.sync, size: 11, color: Y2.muted2),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                            S.t('Synced 4 min ago', '4 मिनिटांपूर्वी सिंक'),
                            style: F.hind(11, color: Y2.muted2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const DemoChip(),
          const SizedBox(width: 8),
          Pressable2(
            onTap: _toggleLang,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD2DAE6)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(S.t('EN', 'मराठी'),
                  style: F.hind(11, w: FontWeight.w500, color: Y2.ink)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alert() => Pressable2(
        onTap: () => nav.tab(1),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: const Color(0x0F1D4ED8), // rgba(29,78,216,0.06)
            border: Border.all(color: const Color(0xFFBCD0F5)),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(I2.alertsActive, size: 16, color: Y2.accent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.t('2 things need you', '2 गोष्टींना तुमची गरज'),
                        style: F.hind(15, w: FontWeight.w600, color: Y2.ink)),
                    Text(
                        S.t('1 call-off to confirm · 1 low-stock alert',
                            '1 कॉल-ऑफ कन्फर्म करा · 1 कमी-स्टॉक सूचना'),
                        style: F.hind(12, color: Y2.body)),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(I2.chevronRight, size: 18, color: Y2.accent),
              ),
            ],
          ),
        ),
      );

  Widget _stat(String value, String? unit, String label) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Y2.card,
          border: Border.all(color: Y2.line),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Ticker2(int.tryParse(value) ?? 0,
                style: F.mono(36, height: 0.8, color: Y2.ink)),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(label, style: F.hind(11, color: Y2.muted)),
            ),
          ],
        ),
      );

  Widget _due() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Y2.card,
          border: Border.all(color: Y2.line),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('₹2.9', style: F.mono(30, height: 0.8, color: Y2.ink)),
                  Text('L', style: F.mono(16, color: Y2.muted)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(S.t('due to you', 'तुम्हाला देय'),
                  style: F.hind(11, color: Y2.muted)),
            ),
          ],
        ),
      );

  Widget _navRow(IconData icon, String title, VoidCallback onTap) => Pressable2(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Y2.card,
            border: Border.all(color: Y2.line),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Y2.muted),
              const SizedBox(width: 11),
              Expanded(
                child: Text(title,
                    style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
              ),
              const Icon(I2.chevronRight, size: 18, color: Y2.muted),
            ],
          ),
        ),
      );

  Widget _payments() => Pressable2(
        onTap: () => nav.tab(4),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Y2.card,
            border: Border.all(color: Y2.line),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              const Icon(Icons.payments_outlined, size: 20, color: Y2.muted),
              const SizedBox(width: 11),
              Expanded(
                child: Text(S.t('Payments & debit notes', 'पेमेंट्स व डेबिट नोट'),
                    style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
              ),
              const Icon(I2.chevronRight, size: 18, color: Y2.muted),
            ],
          ),
        ),
      );
}
