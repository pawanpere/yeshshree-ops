# Flutter App Architecture

How the Yeshshree client is built. Companion to `docs/packets/P09-frontend.md` (build log)
and the backend's `docs/planning/Yeshshree_Backend_Architecture.md`. Read this before
writing or modifying any screen.

## Layout

```
lib/
├── main.dart                 ProviderScope → MaterialApp.router; rebuilds on language switch
├── core/
│   ├── theme.dart            App-map visual language. statusColors(kind) maps any backend
│   │                         status string → (fg,bg). Add new statuses HERE, nowhere else.
│   ├── strings.dart          S.t('English','मराठी') — bilingual at the call site (see ADR-006)
│   ├── api_client.dart       Api.dio: bearer injection, ONE retry after refresh on 401,
│   │                         ApiException (code/message_en/message_mr/details, isClockSkew)
│   ├── auth_state.dart       authProvider: Session (tokens, role, station, language,
│   │                         deviceKey). login/pinSwitch/requestOtp/verifyOtp/logout.
│   ├── retry_queue.dart      retryQueueProvider: offline POST queue (below)
│   └── router.dart           THE route table + role redirect. Every screen class is named
│                             here — adding a screen = add file + add route, nothing else.
├── widgets/common.dart       KpiCard · AppCard · AlertBanner · TileButton · StatusBadge ·
│                             ListRow · ProgressBar · AsyncBody. USE these; never redefine.
└── features/<domain>/        One folder per role-domain; screens only, no shared state.
```

## The five rules every screen follows

1. **Strings**: every user-visible string is `S.t('en','मराठी')`. Backend-supplied bilingual
   fields (`message_en/mr`, `label_en/mr`) are picked by `S.lang.value`.
2. **Errors**: catch `DioException` → `ApiException.from(e)`; show `e.message` (already
   localized). Switch behaviour on `e.code` (machine-stable), NEVER on message text.
   401 + `e.isClockSkew` → tell the user their device clock is wrong.
3. **Transactional POSTs** (gate entry, backfill, GR, issue, confirmation, dispatch,
   invoice) go through `retryQueueProvider.post(path, body, label:)` with a fresh
   `uuid.v4()` as `client_ref`. A `null` return means queued offline — show
   "Queued — will sync", never an error. Keep the SAME client_ref when resubmitting
   after a 409/422 dialog (consignment, confirm_escalate, mismatch_reason) so the
   backend's idempotency dedupes correctly.
4. **Reads** call `Api.dio.get(...)` directly; lists get pull-to-refresh; dashboards add a
   30 s `Timer`. Numbers arrive as JSON strings (backend Decimal) — parse num-or-string.
5. **Navigation**: `context.push('/route', extra: map)` with plain `Map<String,dynamic>`
   extras. Constructor params for extras are declared in router.dart — match them exactly.

## Offline model (the supervisor story)

The retry queue is *first-class UX*, not an error path: a confirmation posted in a wifi
dead spot shows "Queued — will sync", appears as a grey QUEUED row in history, and drains
every 30 s. Backend `client_ref` idempotency makes blind re-fire safe (invariant 4).
KNOWN GAP (packet follow-up): a queued post that's *rejected* (4xx) on drain is dropped
silently — a "failed sync" surface is the first frontend follow-up packet.

## Screen ↔ endpoint map

| Screen (route) | Backend |
|---|---|
| LoginScreen /login · PinSwitchScreen /pin · OtpScreen /otp | /auth/login · /auth/pin-switch · /auth/vendor-otp/* |
| ForceUpdateScreen /force-update | /system/min-version |
| HomeScreen /home | role/station tiles (no API) + retryQueueProvider |
| NotificationsScreen /notifications | /notifications · /{id}/read · /{id}/act |
| ScansPendingScreen /gate/scans | /gate-entries/scans/pending · discard · /system/station-status |
| GateEntryScreen /gate/entry | /gate-entries (queued) · complete-backfill · /master/vendors·purchase-orders |
| UnmatchedScreen /gate/unmatched | /gate-entries/unmatched · link-po · mark-consumable |
| BackfillScreen /gate/backfill | /gate-entries/backfill (queued, offline-by-design) |
| GrFormScreen /qc/gr | /gate-entries?status=open&match_status=matched · /goods-receipts (queued) |
| IssueScreen /store/issue | /issues (queued) · /vendors/{id}/exposure · /master/lines·materials |
| DispatchScreen /store/dispatch | /dispatches (queued) · /master/customers |
| BillingScreen /store/billing | /dispatches?status=open · /invoices (queued) · /{id}/confirm |
| SupervisorHomeScreen /supervisor | /master/lines · /plans/supervisor-view |
| ConfirmSheetScreen /supervisor/confirm | /confirmations (queued) · /confirmations/hold · /config/reason-codes |
| ConfirmHistoryScreen /supervisor/history | /confirmations?line_id&date · /{id}/correction |
| HoldsScreen /supervisor/holds | /confirmations/holds · /{id}/resolve |
| PlanningHomeScreen /planning | /dashboards/overview (subset) |
| ScheduleScreen /planning/schedule | /schedules · /{id}/diff·sanity·release·re-release |
| ConfigScreen /planning/config | /config/* (6 tabs) |
| DashboardsScreen /mgmt | /dashboards/overview·achievement·sales·yield |
| ApprovalsScreen /mgmt/approvals | /approvals/inbox · decide · override · delegations |
| AnomaliesScreen /mgmt/anomalies | /anomalies · /{id}/resolve |

## Deviations from the original playbook (ADR-006) + upgrade paths

| Deviation | Why | Upgrade path |
|---|---|---|
| `S.t()` call-site strings, not ARB | both languages visible where used; no gen-l10n toolchain in sandbox | mechanical extraction to ARB once Flutter CI exists |
| Hand-written API calls, not generated client | openapi-generator needs the dev machine | endpoints mirror openapi.json 1:1; generate + swap imports |
| shared_preferences for session | flutter_secure_storage needs platform setup | swap the persistence calls in auth_state.dart only |

## Not yet built (deliberate)

Vendor-portal screens (P39, post-pilot) · photo capture at gate (camera plugin decision
pending) · FCM push (in-app notifications only) · widget/integration tests (start with the
first `flutter test` run on the dev machine — test seams exist: Riverpod providers are
overridable, screens take plain maps).
