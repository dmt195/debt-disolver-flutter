import 'dart:async';
import 'dart:developer';

import 'package:debt_destroyer/core/diagnostics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Diagnostics through Firebase Analytics and Crashlytics. Collection starts
/// off and follows the user's choice (`setCollectionEnabled`); always used
/// behind [GatedDiagnostics], which blocks and redacts.
class FirebaseDiagnostics implements DiagnosticsService {
  FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;
  FirebaseCrashlytics get _crashlytics => FirebaseCrashlytics.instance;

  @override
  Future<void> setCollectionEnabled({
    required bool enabled,
    bool discardPending = false,
  }) async {
    // Crashlytics keeps reports made while collection is off and sends them
    // once it's on: on opting in, those go first.
    if (discardPending) await _crashlytics.deleteUnsentReports();
    if (enabled) {
      // Analytics only: never ad storage, ad user data or personalisation
      // (the privacy policy).
      await _analytics.setConsent(
        analyticsStorageConsentGranted: true,
        adStorageConsentGranted: false,
        adUserDataConsentGranted: false,
        adPersonalizationSignalsConsentGranted: false,
      );
    }
    await _analytics.setAnalyticsCollectionEnabled(enabled);
    await _crashlytics.setCrashlyticsCollectionEnabled(enabled);
    if (enabled) {
      // The same random ID on crash reports, so a deletion request quoting
      // it covers them too.
      final id = await _analytics.appInstanceId;
      if (id != null) await _crashlytics.setUserIdentifier(id);
    }
  }

  @override
  void recordError(
    Object error,
    StackTrace stack, {
    bool fatal = false,
    String? reason,
  }) => unawaited(
    _crashlytics.recordError(error, stack, fatal: fatal, reason: reason),
  );

  @override
  void logScreen(String name) =>
      unawaited(_analytics.logScreenView(screenName: name));

  @override
  void logEvent(UsageEvent event) => unawaited(
    _analytics.logEvent(name: event.name, parameters: event.parameters),
  );

  @override
  Future<String?> appInstanceId() => _analytics.appInstanceId;
}

/// Whether this build may use Firebase at all: release builds, or a debug
/// build run with `--dart-define=DIAGNOSTICS_ENABLED=true`.
const _enabledForBuild = bool.fromEnvironment(
  'DIAGNOSTICS_ENABLED',
  // Not redundant: kReleaseMode is only false in the debug builds the
  // analyzer sees.
  // ignore: avoid_redundant_argument_values
  defaultValue: kReleaseMode,
);

/// Starts Firebase when this build may use it and its config files are
/// present; otherwise the app sends nothing ([NoDiagnostics]). Collection
/// starts off either way (diagnostics spec §2.2).
Future<DiagnosticsService> startDiagnostics({
  bool enabled = _enabledForBuild,
  Future<void> Function()? initialize,
}) async {
  if (!enabled) return NoDiagnostics();
  try {
    await (initialize ?? Firebase.initializeApp)();
  } on Object catch (error) {
    // Expected until `flutterfire configure` has added the config files
    // (docs/release.md).
    log('Diagnostics off: Firebase did not start', error: error);
    return NoDiagnostics();
  }
  final service = GatedDiagnostics(FirebaseDiagnostics());
  await service.setCollectionEnabled(enabled: false);
  return service;
}
