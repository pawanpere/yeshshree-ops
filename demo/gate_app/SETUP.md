# Android Studio demo app — setup

A thin Flutter app that shows the receiving flow as a **real Android app** in the
emulator. The screens come from the Python demo server on your laptop; the app is
the native shell around it.

> ⚠️ I could not compile this in my environment (no Flutter SDK there). **Test it
> tonight**, not in front of the client. Steps 1–6 take ~10 min.

## Architecture (why it works)
```
Android emulator  ──http──►  10.0.2.2:8000  ──►  your laptop's localhost:8000  (Python server)
```
`10.0.2.2` is the emulator's built-in alias for the host machine's localhost.

## Steps

**1. Start the Python server** (must be reachable from the emulator):
```
cd demo
export GVISION_KEY="<your Vision key>"
python3 -m uvicorn server:app --host 0.0.0.0 --port 8000
```

**2. Create the Flutter project** (in the `demo/` folder or anywhere):
```
flutter create gate_app
```

**3. Copy in the app code:** replace the generated `gate_app/lib/main.dart` with the
`lib/main.dart` from this folder.

**4. Add the WebView dependency** — open `gate_app/pubspec.yaml`, add under `dependencies:`
```
  webview_flutter: ^4.7.0
```
then:
```
cd gate_app && flutter pub get
```

**5. Allow the app to load http (cleartext) + internet.** Edit
`gate_app/android/app/src/main/AndroidManifest.xml`:
- add inside `<manifest>` (above `<application>`):
  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  ```
- add this attribute to the `<application ...>` tag:
  ```xml
  android:usesCleartextTraffic="true"
  ```
  *(Without this, Android silently blocks the http call and the app shows a blank/error page.)*

**6. Run it:** start an emulator (Android Studio → Device Manager → ▶), then:
```
flutter run
```
The app opens with the Yeshshree app bar + DEMO chip and loads the receiving screen.

## Test checklist (do tonight)
- [ ] App launches in emulator, shows "Waiting for a scan…" (not the "can't reach server" error).
- [ ] Drop `data/doc00857220260527165933.pdf` into `demo/scans/` → the app auto-flips to the receiving screen with **PO 520000845** matched.
- [ ] Enter qty + Quality = OK → **Confirm & Generate GRN** → GRN screen shows.
- [ ] (The generated GRN .xlsx lands in `demo/grn_out/` on your laptop.)

## Notes
- **Use the folder-watch path** (scanner/laptop drops the file) for the app demo. The
  "Upload manually" button may not open a file picker inside a WebView — do manual
  uploads from the laptop browser if ever needed.
- **Physical phone instead of emulator?** Put the phone on the same Wi-Fi, find your
  laptop's IP (`ipconfig getifaddr en0` on Mac), and set `kServerUrl` in `main.dart`
  to `http://<that-ip>:8000`.
- **If Flutter fights you tonight:** fallback is opening `http://10.0.2.2:8000` in the
  emulator's Chrome (full-screen) — same flow, just with browser chrome.
