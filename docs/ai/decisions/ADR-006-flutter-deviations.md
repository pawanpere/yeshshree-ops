# ADR-006: Flutter pragmatic deviations (S.t strings, hand-written client, shared_preferences)
Date: 2026-06-12 · Status: accepted, each item carries an explicit upgrade path
Decisions:
1. Bilingual strings via S.t('en','मराठी') at call sites instead of ARB/gen-l10n.
   Why: no Flutter toolchain in the build sandbox; both languages visible at the call
   site is friendlier to AI review. Upgrade: mechanical extraction to ARB once Flutter
   CI runs (P42 expands to do it).
2. Hand-written Api.dio calls mirroring backend/docs/openapi.json 1:1 instead of a
   generated client. Why: openapi-generator needs the dev machine. Upgrade: generate,
   swap imports; drift is already guarded by the backend's openapi-freshness CI gate.
3. Session persisted in shared_preferences instead of flutter_secure_storage.
   Why: secure storage needs per-platform setup that `flutter create` hasn't run yet.
   Risk accepted for pilot (15-min access tokens, rotated opaque refresh tokens,
   reuse-detection revokes all sessions). Upgrade: swap persistence calls in
   auth_state.dart only.
