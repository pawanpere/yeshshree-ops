import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/polish2.dart';

/// Admin — Settings office screen (READ-ONLY). Lists the system settings that
/// drive backend behaviour: `ops_mode` (parallel_run vs authoritative), the
/// anomaly thresholds, and the debit-note multiplier. Reads from
/// [Data.settings]; clearly-marked DEMO fallback when the backend is unreachable
/// or the table is still empty. Each setting renders as a card: the key humanized
/// as a title, with the value shown readably — `ops_mode` as a tinted Pill2,
/// everything else as muted 'key: value' lines. Renders inside the office shell —
/// no responsive code of its own. Changing settings is server-side for now.
class Ui2AdminSettingsScreen extends StatefulWidget {
  const Ui2AdminSettingsScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2AdminSettingsScreen> createState() => _Ui2AdminSettingsScreenState();
}

class _Ui2AdminSettingsScreenState extends State<Ui2AdminSettingsScreen> {
  Loaded<List<Json>>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Data.settings();
    if (!mounted) return;
    setState(() => _data = res);
  }

  // 'ops_mode' -> 'Ops mode', 'anomaly_thresholds' -> 'Anomaly thresholds'.
  String _humanize(String key) {
    if (key.isEmpty) return S.t('Setting', 'सेटिंग');
    final words = key.split(RegExp(r'[_\s]+')).where((w) => w.isNotEmpty);
    return words
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('SETTINGS', 'सेटिंग्ज'),
          demo: loaded?.demo ?? false,
          trailing: rows.isEmpty
              ? null
              : Text('${rows.length}', style: F.mono(12, color: Y2.muted)),
        ),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 3)
              : rows.isEmpty
                  ? EmptyState2(
                      icon: Icons.tune_outlined,
                      title: S.t('No settings', 'सेटिंग्ज नाहीत'),
                      subtitle: S.t(
                          'No system settings are configured on the server.',
                          'सर्व्हरवर कोणत्याही सिस्टम सेटिंग्ज कॉन्फिगर केलेल्या नाहीत.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      itemCount: rows.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                                S.t(
                                    'Read-only — change settings on the server for now.',
                                    'सध्या फक्त वाचनासाठी — सर्व्हरवर बदला.'),
                                style: F.hind(12, color: Y2.muted),
                                maxLines: 2),
                          );
                        }
                        return _card(rows[i - 1]);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _card(Json row) {
    final key = '${row['key'] ?? ''}';
    final rawValue = row['value'];
    final value = rawValue is Map ? Json.from(rawValue) : const <String, dynamic>{};
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Y2.card,
        borderRadius: BorderRadius.circular(Y2.rRow),
        border: Border.all(color: Y2.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_humanize(key),
                    style: F.hind(14, w: FontWeight.w600, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(key,
                    style: F.mono(11, color: Y2.muted),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (key == 'ops_mode')
            _opsMode('${value['mode'] ?? ''}')
          else
            _entries(value),
        ],
      ),
    );
  }

  // ops_mode: parallel_run = orange tint (shadow mode), authoritative = green
  // tint (stock checks live). Anything else falls back to a muted pill.
  Widget _opsMode(String mode) {
    final isAuth = mode == 'authoritative';
    final isParallel = mode == 'parallel_run';
    final label = isParallel
        ? S.t('parallel run', 'समांतर चालन')
        : isAuth
            ? S.t('authoritative', 'अधिकृत')
            : (mode.isEmpty ? S.t('unset', 'सेट नाही') : mode);
    if (isAuth) {
      return Pill2(
          text: label, fg: Y2.green, bg: Y2.greenTint, borderColor: Y2.greenLine);
    }
    if (isParallel) {
      return Pill2(
          text: label,
          fg: Y2.orange,
          bg: Y2.orangeTint,
          borderColor: Y2.orangeLine);
    }
    return Pill2(
        text: label,
        fg: Y2.muted,
        bg: Y2.lineSoft,
        borderColor: Y2.line,
        dot: false);
  }

  // Other settings (thresholds, debit_note): render each map entry as a muted
  // 'k: v' line.
  Widget _entries(Json value) {
    if (value.isEmpty) {
      return Text(S.t('No values', 'मूल्ये नाहीत'),
          style: F.hind(12, color: Y2.muted));
    }
    final keys = value.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text('${keys[i]}',
                    style: F.mono(12, color: Y2.body),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text('${value[keys[i]]}',
                    style: F.mono(12, w: FontWeight.w600, color: Y2.ink),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
