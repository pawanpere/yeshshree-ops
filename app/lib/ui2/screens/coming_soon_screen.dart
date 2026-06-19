import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../widgets/polish2.dart';

/// Placeholder for a role screen that lands in a later phase. Keeps the role
/// navigation complete in Phase 0; each is replaced by its real screen later.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({
    super.key,
    required this.nav,
    required this.titleEn,
    required this.titleMr,
    required this.phase,
    this.icon = Icons.pending_outlined,
  });
  final PhoneNav nav;
  final String titleEn;
  final String titleMr;
  final String phase; // e.g. 'Phase 3'
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return EmptyState2(
      icon: icon,
      title: S.t(titleEn, titleMr),
      subtitle: S.t('Coming in $phase', '$phase मध्ये येत आहे'),
    );
  }
}
