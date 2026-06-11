/// MVP bilingual strings: both languages live AT THE CALL SITE — S.t('Login','लॉगिन').
/// The user's language comes from the login response (users.language).
/// DELIBERATE deviation from ARB files (documented in the packet record): consolidating
/// into gen-l10n ARBs is a later mechanical pass once the Flutter SDK toolchain is in CI.
import 'package:flutter/foundation.dart';

class S {
  /// 'en' | 'mr' — set by auth on login, persisted with the session.
  static final ValueNotifier<String> lang = ValueNotifier('en');

  static String t(String en, String mr) => lang.value == 'mr' ? mr : en;
}
