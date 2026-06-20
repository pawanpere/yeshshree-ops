import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../tokens.dart';

/// Flip the app language EN <-> MR and confirm it with a green toast in the
/// language just selected. Every language switch in the app (phone topbar,
/// office header, profile, vendor screens) calls this so the change is both
/// global — the whole UI re-renders immediately, because the app subtree listens
/// to [S.lang] — and acknowledged, so the user isn't left guessing.
void toggleLanguage(BuildContext context) {
  final toMarathi = S.lang.value != 'mr';
  S.lang.value = toMarathi ? 'mr' : 'en';
  // S.t now reads the NEW language, so the toast announces the chosen one.
  _showLangToast(
    context,
    S.t('Language changed to English', 'भाषा मराठीत बदलली'),
  );
}

/// A self-removing green confirmation toast inserted into the root overlay (so
/// it works everywhere — the ui2 shells are bare Containers, not Scaffolds, so a
/// ScaffoldMessenger SnackBar would have nothing to anchor to).
void _showLangToast(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _LangToast(message: message, onDone: entry.remove),
  );
  overlay.insert(entry);
}

class _LangToast extends StatefulWidget {
  const _LangToast({required this.message, required this.onDone});
  final String message;
  final VoidCallback onDone;

  @override
  State<_LangToast> createState() => _LangToastState();
}

class _LangToastState extends State<_LangToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 240));
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    // Hold briefly, animate out, then remove the overlay entry exactly once.
    Future.delayed(const Duration(milliseconds: 1900), () async {
      if (!mounted) return;
      await _c.reverse();
      _finish();
    });
  }

  void _finish() {
    if (_removed) return;
    _removed = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topInset + 14,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _c,
          child: SlideTransition(
            position: Tween<Offset>(
                    begin: const Offset(0, -0.3), end: Offset.zero)
                .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: Y2.green,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Y2.green.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(widget.message,
                          style: F.hind(13.5,
                              w: FontWeight.w600, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
