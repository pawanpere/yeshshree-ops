import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

/// A typed-editable quantity field — the central number in a stepper, now
/// keyboard-editable so an operator can type "215" instead of tapping `+` 215
/// times. The PARENT owns the value: `+`/`-` buttons stay the parent's job and
/// their result flows back in through [value]; typing calls [onChanged]. Styled
/// (mono, centered) to match the old read-only big-count display it replaces.
class QtyField2 extends StatefulWidget {
  const QtyField2({
    super.key,
    required this.value,
    required this.onChanged,
    this.color = Y2.ink,
    this.fontSize = 50,
    this.min = 0,
    this.max = 99999,
    this.decimal = false,
    this.enabled = true,
    this.suffix,
  });

  /// Current value (driven by the parent; reflects `+`/`-` taps).
  final num value;

  /// Called with the clamped value whenever the user types or steps.
  final ValueChanged<num> onChanged;

  final Color color;
  final double fontSize;
  final num min;
  final num max;

  /// Allow a decimal point (qty fields are NUMERIC(14,3)); false = integers only.
  final bool decimal;
  final bool enabled;

  /// Optional trailing unit (e.g. ' min', ' kg') shown after the number.
  final String? suffix;

  @override
  State<QtyField2> createState() => _QtyField2State();
}

class _QtyField2State extends State<QtyField2> {
  late final TextEditingController _c;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: _fmt(widget.value));
    _focus = FocusNode();
    // Select-all on focus so a tap lets the operator overwrite immediately
    // instead of appending to the current count.
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _c.selection =
            TextSelection(baseOffset: 0, extentOffset: _c.text.length);
      }
    });
  }

  @override
  void didUpdateWidget(QtyField2 old) {
    super.didUpdateWidget(old);
    // Reflect external (stepper) changes, but never fight the user mid-type.
    if (widget.value != old.value && !_focus.hasFocus) {
      if (num.tryParse(_c.text) != widget.value) _c.text = _fmt(widget.value);
    }
  }

  String _fmt(num v) {
    if (widget.decimal) {
      // Trim a trailing .0 so integers read cleanly.
      return v == v.roundToDouble() ? '${v.round()}' : '$v';
    }
    return '${v.round()}';
  }

  void _onChanged(String s) {
    final t = s.trim();
    if (t.isEmpty) {
      widget.onChanged(widget.min); // empty = the floor (usually 0)
      return;
    }
    final parsed = num.tryParse(t);
    if (parsed == null) return;
    widget.onChanged(parsed.clamp(widget.min, widget.max));
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _c,
      focusNode: _focus,
      enabled: widget.enabled,
      textAlign: TextAlign.center,
      keyboardType:
          TextInputType.numberWithOptions(decimal: widget.decimal, signed: false),
      inputFormatters: [
        if (widget.decimal)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
        else
          FilteringTextInputFormatter.digitsOnly,
      ],
      style: F.mono(widget.fontSize, height: 0.9, color: widget.color),
      cursorColor: Y2.accent,
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: _onChanged,
    );
    if (widget.suffix == null) return field;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(child: field),
        Text(widget.suffix!,
            style: F.hind(widget.fontSize * 0.34,
                w: FontWeight.w400, color: Y2.muted)),
      ],
    );
  }
}
