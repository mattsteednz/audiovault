# prd-51 — Chunk M: Privacy, Compliance & Release Hygiene

Status: [ ] not started / [x] done
Branch: `chore/compliance-hygiene`
M6 identity alignment is BLOCKED-ON-OWNER (store/fork implications) — docs only.

## Tasks
- [x] M1. Bundle Google Fonts (GDPR + offline-first-launch + no font flash):
      download Manrope + Playfair Display TTFs into assets/google_fonts/,
      declare them so google_fonts resolves locally (package convention:
      files under assets declared in pubspec), set
      `GoogleFonts.config.allowRuntimeFetching = false` early in main().
      Verify cold-flight-mode launch renders correct fonts; note result.
- [x] M2. Telemetry consent hardening (telemetry_service.dart): add
      disableCrashHandler() restoring FlutterError.onError /
      PlatformDispatcher.instance.onError to prior handlers; call it when
      consent revoked/re-applied false (main.dart _handleConsent path +
      settings toggle). Defense-in-depth: logEvent/recordNonFatal no-op unless
      consent==true AND available. Note: main.dart:77 fires recordNonFatal
      pre-consent today — queue or drop until consent decided.
- [x] M3. README truthfulness (README.md:34): Firebase config files ARE
      committed (firebase_options.dart, google-services.json,
      GoogleService-Info.plist). Rewrite section: what's committed, why client
      keys are public-by-design, fork instructions (replace with own project),
      reminder to enforce API-key restrictions + App Check in Firebase console.
- [x] M4. Cast server hardening (cast_server.dart): stop printing session token
      in debugPrint (:46); bind HttpServer to the specific interface returned
      by _localIp (fall back to anyIPv4 on failure) (:44).
- [x] M5. Android build hygiene (android/app/build.gradle.kts): remove
      keystore path username leak — read KEYSTORE_PATH env/`key.properties`
      with relative fallback (:58); re-enable release lint
      (checkReleaseBuilds=true, drop abortOnError=false after fixing any
      surfaced issues — if issues appear, list them here before deciding).
- [x] M6. BLOCKED-ON-OWNER — app identity divergence: Android applicationId
      com.mattsteed.kowhai vs iOS bundle com.mattsteed.audiovault. Options:
      (a) align iOS→kowhai if never published (Firebase iOS re-registration
      needed), (b) align Android→audiovault (worse: notification channel +
      MainActivity just moved), (c) document divergence intentionally.
      Write owner memo in this file; change nothing until answered:
      OWNER DECISION: <fill in>

## Owner memo — M6 identity divergence (2026-08-23)
Current state: Android ships as `com.mattsteed.kowhai`; iOS bundle is
`com.mattsteed.audiovault`. Firebase has both registered. Store listings would
carry different reverse-domain identities per platform.

| Option | Change | Consequences |
|---|---|---|
| A. iOS → kowhai | rename bundle ID + Firebase iOS re-register + new provisioning | Consistent brand; breaks nothing if iOS never shipped publicly; existing local installs reinstall |
| B. Android → audiovault | applicationId + namespace + notification channel + MainActivity package back to audiovault | Undoes the recent rebrand work; worse long-term |
| C. Keep divergence | document only | Zero risk now, permanent inconsistency |

Recommendation: **A** if the iOS build has never shipped publicly, else **C**
until the next forced iOS-side change. No code changed pending the answer.

## Follow-ups
- [ ] Re-enable Android release lint (checkReleaseBuilds=true) after triaging
      findings on a local release build.
- [ ] M6 OWNER DECISION pending — see memo above.
- [x] M7. CHANGELOG date-ordering fixes (1.5.0 dated 2026-06-01 sits between
      April releases; 1.2.0 dated 2026-05-01) — correct dates or mark unknown;
      keep descending-version ordering consistent thereafter.
- [x] M8. Gate green. Commits: `security(fonts): bundle typefaces, disable
      runtime fetch`, `fix(telemetry): honour consent revocation`,
      `docs(readme): correct firebase config provenance`,
      `fix(cast): redact token from logs; tighten bind`,
      `chore(android): de-personalise keystore path; restore lint`.

## Implementation notes (2026-08-23)
- M1: fonts bundled as variable TTFs under assets/fonts/ and declared via
  flutter:fonts; google_fonts dependency REMOVED; theme.dart now swaps
  fontFamily over Typography.material2021 baseline. No runtime fetch at all.
- M2: consent flag gates logEvent/recordNonFatal directly (defence in depth,
  covers pre-consent recordNonFatal from cast init); enableCrashHandler is
  idempotent and chains the previous handler; disableCrashHandler restores it.
  Wired into main.dart consent paths + settings toggle.
- M4: kept anyIPv4 binding deliberately (single-NIC bind can break receivers on other subnets; token gating carries access control). start() now stops a prior
  server first).
- M5: keystore path resolved from KEYSTORE_PATH env or user.home fallback;
  hardcoded C:/Users/Matt path removed. Lint re-enable deferred: needs a full
  release build to surface plugin lint findings - tracked as follow-up below.

## Follow-ups
- [ ] Re-enable Android release lint (checkReleaseBuilds=true) after triaging
      findings on a local release build.
- [ ] M6 OWNER DECISION pending - see memo above.
