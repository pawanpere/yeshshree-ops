import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_state.dart';
import '../../core/strings.dart';
import '../roles.dart';
import '../tokens.dart';
import '../widgets/polish2.dart';

/// After login the user picks a role; from then on they see only that role's
/// screens. Structured so a role can later be locked to the account (this picker
/// would then be skipped). Full-viewport, responsive grid.
class RolePickerScreen extends ConsumerWidget {
  const RolePickerScreen({super.key, this.onSignOut, this.roles});

  /// The roles this account may pick (entitlement-gated). Null = all.
  final List<Role>? roles;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider);
    final name = session.fullName ?? session.username ?? '';
    return Container(
      color: Y2.navy,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(S.t('Pick your role', 'तुमची भूमिका निवडा'),
                                style: F.khand(26, ls: 0.3, color: Colors.white)),
                            if (name.isNotEmpty)
                              Text(
                                  S.t('Signed in as $name', '$name म्हणून साइन इन'),
                                  style: F.hind(12,
                                      color: Colors.white.withValues(alpha: 0.7))),
                          ],
                        ),
                      ),
                      if (onSignOut != null)
                        GestureDetector(
                          onTap: onSignOut,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(S.t('Sign out', 'साइन आउट'),
                                style: F.hind(12,
                                    w: FontWeight.w600, color: Colors.white)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(builder: (context, c) {
                    final cols = c.maxWidth < 360
                        ? 2
                        : c.maxWidth < 540
                            ? 3
                            : 4;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final role in (roles ?? Role.values))
                          SizedBox(
                            width: (c.maxWidth - (cols - 1) * 12) / cols,
                            child: _RoleCard(
                              spec: kRoles[role]!,
                              onTap: () => ref
                                  .read(activeRoleProvider.notifier)
                                  .state = role,
                            ),
                          ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.spec, required this.onTap});
  final RoleSpec spec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable2(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Y2.screen,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0x141D4ED8),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(spec.icon, size: 22, color: Y2.accent),
            ),
            const SizedBox(height: 10),
            Text(S.t(spec.en, spec.mr),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.khand(16, color: Y2.ink)),
            Text(
                spec.isOffice
                    ? S.t('office', 'ऑफिस')
                    : S.t('floor', 'फ्लोअर'),
                style: F.hind(10, color: Y2.muted)),
          ],
        ),
      ),
    );
  }
}
