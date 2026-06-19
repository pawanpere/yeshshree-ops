import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/polish2.dart';

/// Force-update wall — prototype screen [39]. Blocking full-screen
/// 'UPDATE REQUIRED' over a navy panel: no back chevron, no tab bar. The
/// 'Update now' button is visual only.
class Ui2ForceUpdateScreen extends StatelessWidget {
  const Ui2ForceUpdateScreen({super.key, required this.nav});
  final PhoneNav nav;

  // Dark-panel palette, from the prototype's inline styles.
  static const _panel = Color(0xFF11243F); // #11243f
  static const _tile = Color(0xFF1C3354); // #1c3354
  static const _onPanel = Color(0xFFEAF0F8); // #eaf0f8
  static const _bodyText = Color(0xFFAEBFD6); // #aebfd6
  static const _label = Color(0xFF8FA3C0); // #8fa3c0
  static const _bad = Color(0xFFFF8A84); // #ff8a84 (your version)
  static const _good = Color(0xFF3DDC97); // #3ddc97 (latest version)

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        Expanded(
          child: ColoredBox(
            color: _panel,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 34, 28, 34),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // System-update badge
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _tile,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.system_update_alt_rounded,
                            size: 30, color: _onPanel),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      S.t('UPDATE REQUIRED', 'अपडेट आवश्यक'),
                      textAlign: TextAlign.center,
                      style: F.khand(24, ls: 0.5, color: _onPanel),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      S.t(
                          "This version is too old to use safely. Please update to keep posting to SAP correctly. You can't continue until you update.",
                          'ही आवृत्ती सुरक्षितपणे वापरण्यासाठी फार जुनी आहे. SAP ला योग्य पोस्टिंग सुरू ठेवण्यासाठी अपडेट करा. अपडेट केल्याशिवाय तुम्ही पुढे जाऊ शकत नाही.'),
                      textAlign: TextAlign.center,
                      style: F.hind(13, color: _bodyText, height: 1.55),
                    ),
                    const SizedBox(height: 22),
                    // Version comparison tile
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: _tile,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _versionRow(S.t('You have', 'तुमच्याकडे'), '4.0.6',
                              _bad,
                              icon: Icons.error_outline_rounded),
                          const SizedBox(height: 8),
                          _versionRow(
                              S.t('Minimum', 'किमान'), '4.2.0', _onPanel),
                          const SizedBox(height: 8),
                          _versionRow(
                              S.t('Latest', 'नवीनतम'), '4.2.1', _good,
                              icon: Icons.check_circle_rounded),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // 'Update now' — visual only (pressed state + haptic)
                    PrimaryButton2(
                      label: S.t('Update now', 'आता अपडेट करा'),
                      onTap: () {},
                    ),
                    const SizedBox(height: 12),
                    Text(
                      S.t(
                          "From Play Store, or your plant's internal app link. Ask IT if the update doesn't appear.",
                          'Play Store वरून, किंवा तुमच्या प्लांटच्या अंतर्गत अॅप लिंकवरून. अपडेट दिसत नसल्यास IT ला विचारा.'),
                      textAlign: TextAlign.center,
                      style: F.hind(11, color: _label, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _versionRow(String label, String version, Color versionColor,
          {IconData? icon}) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: F.hind(13, color: _label)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: versionColor),
                const SizedBox(width: 5),
              ],
              Text(version,
                  style: F.mono(13, w: FontWeight.w700, color: versionColor)),
            ],
          ),
        ],
      );
}
