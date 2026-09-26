import 'dart:async';

import 'package:debt_destroyer/core/diagnostics.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'diagnostics_sync.g.dart';

/// Applies the user's diagnostics choice to the service: at start, and
/// whenever it changes (diagnostics spec §2.2). Until settings load it
/// stays off.
@Riverpod(keepAlive: true)
void diagnosticsSettingSync(Ref ref) {
  final service = ref.watch(diagnosticsProvider);
  ref.listen(
    settingsControllerProvider.select((s) => s.value?.shareDiagnostics),
    (before, on) => unawaited(
      service.setCollectionEnabled(
        enabled: on ?? false,
        // Only a real opt-in (off to on) discards what was stored while it
        // was off; someone already opted in keeps their pending reports.
        discardPending: before == false && on == true,
      ),
    ),
    fireImmediately: true,
  );
}
