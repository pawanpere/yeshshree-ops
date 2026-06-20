import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../tokens.dart';
import '../validators.dart';
import '../widgets/bits.dart';
import '../widgets/polish2.dart';

/// Admin — Users office screen. Lists users, adds a user, deactivates a user.
/// Reads from [Data.users]; clearly-marked DEMO fallback when the backend is
/// unreachable or the table is still empty. Two views toggle on [_adding]: the
/// user LIST and an inline ADD-USER form (simpler + safer than an overlay).
/// Renders inside the office shell — no responsive code of its own.
class Ui2AdminUsersScreen extends StatefulWidget {
  const Ui2AdminUsersScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2AdminUsersScreen> createState() => _Ui2AdminUsersScreenState();
}

class _Ui2AdminUsersScreenState extends State<Ui2AdminUsersScreen> {
  Loaded<List<Json>>? _data;

  // List view: which user id is mid-deactivation (so only its button busies).
  int? _deactivating;

  // Toggles between the LIST view and the inline ADD-USER form.
  bool _adding = false;

  // Add-user form state.
  final _username = TextEditingController();
  final _fullName = TextEditingController();
  final _password = TextEditingController();
  final _pin = TextEditingController();
  String _role = ''; // one of _roles; required.
  String? _station; // one of _stations or null ("none").
  String _language = 'en'; // 'en' | 'mr'.
  bool _obscure = true;
  bool _creating = false;

  static const _roles = <String>[
    'admin',
    'management',
    'planning',
    'plant_ops',
    'supervisor',
    'vendor',
  ];
  static const _stations = <String>['gate', 'qc', 'store', 'ppc'];

  @override
  void initState() {
    super.initState();
    // Re-evaluate the CTA + inline hints on every keystroke in any field.
    for (final c in [_username, _fullName, _password, _pin]) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  @override
  void dispose() {
    _username.dispose();
    _fullName.dispose();
    _password.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await Data.users();
    if (!mounted) return;
    setState(() => _data = res);
  }

  // ----------------------------------------------------------------- actions ---

  Future<void> _deactivate(Json u) async {
    final id = u['id'];
    if (_deactivating != null || id is! int) return;
    setState(() => _deactivating = id);
    final res = await Data.patch('/master/users/$id', {'is_active': false});
    if (!mounted) return;
    if (res.failed) {
      setState(() => _deactivating = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.error?.message ??
            S.t('Could not deactivate user',
                'वापरकर्ता निष्क्रिय करता आला नाही')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(S.t('User deactivated', 'वापरकर्ता निष्क्रिय केला')),
      behavior: SnackBarBehavior.floating,
    ));
    setState(() => _deactivating = null);
    await _load();
  }

  // Per-field validity. USERNAME: strict slug (V.username). FULL NAME: a real
  // name (≥3 chars + a letter). PASSWORD: ≥6 chars, not all-whitespace — stored
  // untrimmed. PIN: OPTIONAL — valid when empty, else exactly 4 non-trivial
  // digits. ROLE is required (chip selection, no inline hint).
  bool get _usernameValid => V.username(_username.text);
  bool get _fullNameValid => V.name(_fullName.text);
  bool get _passwordValid => V.password(_password.text);
  bool get _pinValid =>
      _pin.text.trim().isEmpty || V.pin(_pin.text);

  bool get _canCreate =>
      _usernameValid &&
      _fullNameValid &&
      _passwordValid &&
      _pinValid &&
      _role.isNotEmpty;

  Future<void> _create() async {
    if (_creating || !_canCreate) return;
    setState(() => _creating = true);
    final pin = _pin.text.trim();
    final body = <String, dynamic>{
      'username': _username.text.trim(),
      'full_name': _fullName.text.trim(),
      'role': _role,
      'password': _password.text,
      'language': _language,
      if (pin.isNotEmpty) 'pin': pin,
      if (_station != null) 'station': _station,
    };
    final res = await Data.mutate('/master/users', body);
    if (!mounted) return;
    if (res.failed) {
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.error?.message ??
            S.t('Could not create user', 'वापरकर्ता तयार करता आला नाही')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(S.t('User created', 'वापरकर्ता तयार केला')),
      behavior: SnackBarBehavior.floating,
    ));
    _resetForm();
    setState(() {
      _creating = false;
      _adding = false;
    });
    await _load();
  }

  void _resetForm() {
    _username.clear();
    _fullName.clear();
    _password.clear();
    _pin.clear();
    _role = '';
    _station = null;
    _language = 'en';
    _obscure = true;
  }

  void _cancelAdd() {
    _resetForm();
    setState(() => _adding = false);
  }

  // -------------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    final loaded = _data;
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('USERS', 'वापरकर्ते'),
          demo: loaded?.demo ?? false,
          trailing: _adding
              ? null
              : Pressable2(
                  onTap: () => setState(() => _adding = true),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: Y2.accent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, size: 15, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(S.t('Add', 'जोडा'),
                            style: F.hind(12,
                                w: FontWeight.w600, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
        ),
        Expanded(child: _adding ? _form() : _list()),
      ],
    );
  }

  // ----- LIST view -----

  Widget _list() {
    final loaded = _data;
    if (loaded == null) return const SkeletonRows(count: 5);
    final rows = loaded.data;
    if (rows.isEmpty) {
      return EmptyState2(
        icon: Icons.people_outline,
        title: S.t('No users yet', 'अद्याप वापरकर्ते नाहीत'),
        subtitle: S.t(
            'Add a user to give them access to the plant.',
            'प्लांटमध्ये प्रवेश देण्यासाठी वापरकर्ता जोडा.'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      itemCount: rows.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
                S.t('${rows.length} active users',
                    '${rows.length} सक्रिय वापरकर्ते'),
                style: F.hind(12, color: Y2.muted)),
          );
        }
        return _userCard(rows[i - 1]);
      },
    );
  }

  Widget _userCard(Json u) {
    final fullName =
        '${u['full_name'] ?? S.t('Unnamed user', 'नाव नसलेला वापरकर्ता')}';
    final username = '${u['username'] ?? '—'}';
    final role = '${u['role'] ?? ''}';
    final station = u['station'];
    final hasStation = station != null && '$station'.trim().isNotEmpty;
    final hasPin = u['has_pin'] == true;
    final id = u['id'];
    final busy = id is int && _deactivating == id;
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
                child: Text(fullName,
                    style: F.hind(14, w: FontWeight.w600, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              _rolePill(role),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: Text('@$username',
                    style: F.mono(12, color: Y2.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (hasStation) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text('· $station',
                      style: F.hind(12, color: Y2.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
              if (hasPin) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Y2.lineSoft,
                    borderRadius: BorderRadius.circular(Y2.rPill),
                  ),
                  child: Text('PIN',
                      style: F.hind(9,
                          w: FontWeight.w600, ls: 0.4, color: Y2.muted)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Pressable2(
              onTap: busy ? null : () => _deactivate(u),
              child: Opacity(
                opacity: busy ? 0.5 : 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (busy) ...[
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Y2.red),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Text(S.t('Deactivate', 'निष्क्रिय करा'),
                        style: F.hind(12, w: FontWeight.w600, color: Y2.red)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Role → tint mapping. admin/management = accent/navy tint, plant_ops/
  // supervisor = green tint, vendor = orange tint, planning = a blue tint.
  Widget _rolePill(String role) {
    Color fg = Y2.muted, bg = Y2.lineSoft, line = Y2.line;
    switch (role) {
      case 'admin':
      case 'management':
        fg = Y2.accent;
        bg = const Color(0x141D4ED8); // accent .08
        line = const Color(0x331D4ED8); // accent .20
        break;
      case 'planning':
        fg = const Color(0xFF0369A1); // a calmer blue
        bg = const Color(0x140EA5E9);
        line = const Color(0x330EA5E9);
        break;
      case 'plant_ops':
      case 'supervisor':
        fg = Y2.green;
        bg = Y2.greenTint;
        line = Y2.greenLine;
        break;
      case 'vendor':
        fg = Y2.orange;
        bg = Y2.orangeTint;
        line = Y2.orangeLine;
        break;
    }
    return Pill2(
        text: role.isEmpty ? S.t('user', 'वापरकर्ता') : role,
        fg: fg,
        bg: bg,
        borderColor: line,
        dot: false);
  }

  // ----- ADD-USER form -----

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Text(S.t('New user', 'नवीन वापरकर्ता'),
            style: F.khand(18, ls: 0.2, color: Y2.ink)),
        const SizedBox(height: 4),
        Text(
            S.t('Create a plant login.', 'प्लांट लॉगिन तयार करा.'),
            style: F.hind(12, color: Y2.muted)),
        const SizedBox(height: 18),
        _label(S.t('USERNAME', 'वापरकर्तानाव')),
        _field(_username,
            hint: 'gate1',
            formatters: V.usernameInput,
            // Show the rule only once they've typed something invalid.
            error: _username.text.trim().isNotEmpty && !_usernameValid
                ? S.t('3–32 chars: a–z, 0–9, dot or underscore',
                    '३–३२ अक्षरे: a–z, 0–9, बिंदू किंवा अंडरस्कोर')
                : null),
        const SizedBox(height: 14),
        _label(S.t('FULL NAME', 'पूर्ण नाव')),
        _field(_fullName,
            hint: S.t('Ravi (Gate)', 'रवी (गेट)'),
            error: _fullName.text.trim().isNotEmpty && !_fullNameValid
                ? S.t('Enter the full name (min 3 letters)',
                    'पूर्ण नाव भरा (किमान ३ अक्षरे)')
                : null),
        const SizedBox(height: 14),
        _label(S.t('PASSWORD', 'पासवर्ड')),
        _field(_password,
            obscure: _obscure,
            error: _password.text.isNotEmpty && !_passwordValid
                ? S.t('At least 6 characters',
                    'किमान ६ वर्ण')
                : null,
            trailing: GestureDetector(
              onTap: () => setState(() => _obscure = !_obscure),
              child: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: Y2.muted),
            )),
        const SizedBox(height: 14),
        _label(S.t('PIN (OPTIONAL)', 'पिन (पर्यायी)')),
        _field(_pin,
            hint: '1234',
            keyboard: TextInputType.number,
            formatters: V.pin4(),
            error: _pin.text.trim().isNotEmpty && !_pinValid
                ? S.t('4 digits, not an easy sequence',
                    '४ अंक, सोपा क्रम नको')
                : null),
        const SizedBox(height: 18),
        _label(S.t('ROLE', 'भूमिका')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in _roles)
              _chip(r, _role == r, () => setState(() => _role = r)),
          ],
        ),
        const SizedBox(height: 18),
        _label(S.t('STATION (OPTIONAL)', 'स्टेशन (पर्यायी)')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(S.t('none', 'काही नाही'), _station == null,
                () => setState(() => _station = null)),
            for (final st in _stations)
              _chip(st, _station == st, () => setState(() => _station = st)),
          ],
        ),
        const SizedBox(height: 18),
        _label(S.t('LANGUAGE', 'भाषा')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip('EN', _language == 'en', () => setState(() => _language = 'en')),
            _chip('मराठी', _language == 'mr',
                () => setState(() => _language = 'mr')),
          ],
        ),
        const SizedBox(height: 24),
        PrimaryButton2(
          label: S.t('Create user', 'वापरकर्ता तयार करा'),
          busy: _creating,
          enabled: _canCreate,
          onTap: _create,
        ),
        const SizedBox(height: 10),
        OutlineButton2(
          label: S.t('Cancel', 'रद्द करा'),
          onTap: _creating ? null : _cancelAdd,
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Pressable2(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0x141D4ED8) : Y2.card,
            border: Border.all(color: selected ? Y2.accent : Y2.line),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(label,
              style: F.hind(13,
                  w: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Y2.accent : Y2.body)),
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: F.hind(10, w: FontWeight.w600, ls: 0.5, color: Y2.muted)),
      );

  Widget _field(TextEditingController c,
          {String? hint,
          bool obscure = false,
          Widget? trailing,
          TextInputType? keyboard,
          List<TextInputFormatter>? formatters,
          String? error}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Y2.card,
              // Red hairline when the field is filled-but-invalid.
              border: Border.all(color: error != null ? Y2.red : Y2.line),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: c,
                    obscureText: obscure,
                    keyboardType: keyboard,
                    inputFormatters: formatters,
                    onChanged: (_) => setState(() {}),
                    style: F.hind(15, color: Y2.ink),
                    cursorColor: Y2.accent,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: F.hind(15, color: Y2.muted2),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          if (error != null) FieldHint(error),
        ],
      );
}
