import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Shared input validation for the ui2 forms. Every rule is HARD: a CTA must stay
/// disabled until the field is valid (the product decision was hard-block, not
/// warn). Keep the predicates pure (bool) — screens build the bilingual error
/// message with S.t and render it via [FieldHint]. Devanagari letters are allowed
/// wherever a human-typed name/label is expected.
class V {
  V._();

  static final _letter = RegExp(r'[A-Za-zऀ-ॿ]');

  // ---- Vehicle plate (strict Indian commercial format) ----
  /// Uppercase + strip all whitespace, so "mh12 ab 4421" → "MH12AB4421".
  static String normPlate(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'\s+'), '');
  static final _plate = RegExp(r'^[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{1,4}$');

  /// State(2 letters) + RTO(1-2 digits) + series(1-3 letters) + number(1-4 digits).
  static bool plate(String s) => _plate.hasMatch(normPlate(s));

  // ---- Human names / free text ----
  /// A real name: ≥3 chars and contains at least one letter (Latin or Devanagari).
  static bool name(String s) {
    final t = s.trim();
    return t.length >= 3 && _letter.hasMatch(t);
  }

  /// Generic free text (vendor, label, …): ≥[min] chars and contains a letter.
  static bool freeText(String s, {int min = 3}) {
    final t = s.trim();
    return t.length >= min && _letter.hasMatch(t);
  }

  // ---- Credentials ----
  static final _username = RegExp(r'^[a-z0-9._]{3,32}$');
  static bool username(String s) => _username.hasMatch(s.trim());

  /// Login username for the pilot accounts — same charset, allow up to 64.
  static final _loginUser = RegExp(r'^[a-z0-9._]{3,64}$');
  static bool loginUsername(String s) => _loginUser.hasMatch(s.trim());

  /// Password: ≥6 chars, not all-whitespace. (Demo policy; not trimmed when used.)
  static bool password(String s) => s.length >= 6 && s.trim().isNotEmpty;

  static const _weakPins = {
    '0000', '1111', '2222', '3333', '4444', '5555', '6666', '7777', '8888',
    '9999', '1234', '4321', '0123',
  };
  static final _pin = RegExp(r'^[0-9]{4}$');
  /// Exactly 4 digits, rejecting trivial sequences/repeats.
  static bool pin(String s) {
    final t = s.trim();
    return _pin.hasMatch(t) && !_weakPins.contains(t);
  }

  // ---- Codes ----
  /// Lowercase slug, 3–64 chars, internal hyphens only (no leading/trailing/double).
  static final _deviceKey = RegExp(r'^[a-z0-9](?:[a-z0-9-]{1,62}[a-z0-9])?$');
  static bool deviceKey(String s) {
    final t = s.trim();
    return t.length >= 3 && _deviceKey.hasMatch(t) && !t.contains('--');
  }

  /// SAP production order number — digits only, ≥6.
  static final _sapOrder = RegExp(r'^[0-9]{6,}$');
  static bool sapOrder(String s) => _sapOrder.hasMatch(s.trim());

  /// Indian mobile: 10 digits starting 6–9 (spaces tolerated in input).
  static final _mobile = RegExp(r'^[6-9][0-9]{9}$');
  static bool mobile(String s) =>
      _mobile.hasMatch(s.replaceAll(RegExp(r'\s+'), ''));

  // ---- Quantities ----
  static bool positive(num? v) => v != null && v > 0;

  // ---- Input formatters (restrict the keystrokes a field accepts) ----
  static List<TextInputFormatter> get digitsOnly =>
      [FilteringTextInputFormatter.digitsOnly];

  /// Plate: uppercase, allow letters/digits/space, cap length.
  static List<TextInputFormatter> get plateInput => [
        _UpperCaseFormatter(),
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
        LengthLimitingTextInputFormatter(13),
      ];

  /// Username: lowercase, allow a-z 0-9 . _
  static List<TextInputFormatter> get usernameInput => [
        _LowerCaseFormatter(),
        FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9._]')),
        LengthLimitingTextInputFormatter(64),
      ];

  /// Device key slug: lowercase, allow a-z 0-9 -
  static List<TextInputFormatter> get slugInput => [
        _LowerCaseFormatter(),
        FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]')),
        LengthLimitingTextInputFormatter(64),
      ];

  static List<TextInputFormatter> pin4() =>
      [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)];

  static List<TextInputFormatter> mobile10() =>
      [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)];
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue next) =>
      next.copyWith(text: next.text.toUpperCase());
}

class _LowerCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue next) =>
      next.copyWith(text: next.text.toLowerCase());
}

/// Severity of a [FieldHint]: a hard [error] (red) that blocks submit, or a soft
/// [warning] (orange) that is purely advisory and never gates the CTA.
enum FieldHintTone { error, warning }

/// Inline validation hint shown under a field. Render it only when the field is
/// non-empty-but-invalid (error) or worth flagging (warning), so the form isn't
/// pre-littered. Red = hard error (blocks); orange = soft warning (advisory).
class FieldHint extends StatelessWidget {
  const FieldHint(this.message,
      {super.key, this.show = true, this.tone = FieldHintTone.error});
  final String message;
  final bool show;
  final FieldHintTone tone;

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    final warn = tone == FieldHintTone.warning;
    final color = warn ? Y2.orange : Y2.red;
    final icon = warn ? Icons.warning_amber_rounded : Icons.error_outline;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(message,
                style: F.hind(11, w: FontWeight.w500, color: color)),
          ),
        ],
      ),
    );
  }
}
