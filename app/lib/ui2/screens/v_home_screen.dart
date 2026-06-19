import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Vendor portal home — prototype screen [29]. A different surface from the
/// operator app: a 4-tab vendor nav (Home / Orders / Stock / Money), no
/// operator [BottomTabs2] and no back chevron (this is the vendor root). The
/// EN/मराठी pill flips the app language; Orders/Stock reach their screens.
class Ui2VHomeScreen extends StatefulWidget {
  const Ui2VHomeScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2VHomeScreen> createState() => _Ui2VHomeScreenState();
}

class _Ui2VHomeScreenState extends State<Ui2VHomeScreen> {
  PhoneNav get nav => widget.nav;

  void _toggleLang() => setState(
      () => S.lang.value = S.lang.value == 'mr' ? 'en' : 'mr');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        // ---- Header: vendor name + portal sub + lang pill ----
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Y2.line))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SANDHAR STEEL',
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
                                S.t('Vendor portal · Yeshshree',
                                    'विक्रेता पोर्टल · येशश्री'),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
        ),
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
                  Expanded(child: _stat('6', null, S.t('open orders', 'खुल्या ऑर्डर'))),
                  const SizedBox(width: 11),
                  Expanded(child: _due()),
                ]),
                const SizedBox(height: 11),
                _navRow(
                    I2.invoice,
                    S.t('My orders & call-offs', 'माझ्या ऑर्डर व कॉल-ऑफ'),
                    () => nav.go(ScreenId.vAlert)),
                const SizedBox(height: 11),
                _navRow(I2.store, S.t('Stock & cover', 'स्टॉक व कव्हर'),
                    () => nav.go(ScreenId.vStock)),
                const SizedBox(height: 11),
                _payments(),
              ],
            ),
          ),
        ),
        // ---- Vendor bottom nav (Home / Orders / Stock / Money) ----
        _vendorTabs(),
      ],
    );
  }

  Widget _alert() => Pressable2(
        onTap: () => nav.go(ScreenId.vAlert),
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
                  Text('₹8.4', style: F.mono(30, height: 0.8, color: Y2.ink)),
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

  Widget _payments() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Y2.card,
          border: Border.all(color: Y2.line),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            const Icon(I2.invoice, size: 20, color: Y2.muted),
            const SizedBox(width: 11),
            Expanded(
              child: Text(S.t('Payments', 'पेमेंट्स'),
                  style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Y2.orangeTint,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(S.t('coming later', 'नंतर येणार'),
                  style: F.hind(10, w: FontWeight.w600, color: Y2.orange)),
            ),
          ],
        ),
      );

  Widget _vendorTabs() => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Y2.line)),
        ),
        padding: const EdgeInsets.fromLTRB(0, 9, 0, 20),
        child: Row(
          children: [
            _vTab(I2.homeActive, S.t('Home', 'मुख्य'), active: true),
            _vTab(I2.invoice, S.t('Orders', 'ऑर्डर'),
                onTap: () => nav.go(ScreenId.vAlert)),
            _vTab(I2.store, S.t('Stock', 'स्टॉक'),
                onTap: () => nav.go(ScreenId.vStock)),
            _vTab(Icons.payments_outlined, S.t('Money', 'पैसे')),
          ],
        ),
      );

  Widget _vTab(IconData icon, String label,
          {bool active = false, VoidCallback? onTap}) =>
      Expanded(
        child: Pressable2(
          haptic: false,
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 22, color: active ? Y2.accent : Y2.muted),
                const SizedBox(height: 3),
                Text(label,
                    style: F.hind(9,
                        w: FontWeight.w600,
                        color: active ? Y2.accent : Y2.muted)),
              ],
            ),
          ),
        ),
      );
}
