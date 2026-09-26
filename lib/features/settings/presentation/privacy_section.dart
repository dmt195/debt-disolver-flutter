import 'dart:async';

import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/app_version.dart';
import 'package:debt_destroyer/core/diagnostics.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/links.dart';
import 'package:debt_destroyer/features/ads/presentation/ads_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens [uri], or says where it is if it can't (diagnostics spec §3).
Future<void> openLegalPage(BuildContext context, WidgetRef ref, Uri uri) async {
  final messenger = ScaffoldMessenger.of(context);
  final failed = context.l10n.linkOpenFailed('$uri');
  if (!await ref.read(linkOpenerProvider).open(uri)) {
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}

/// The diagnostics switch as a list tile: off until the user opts in.
class ShareDiagnosticsTile extends StatelessWidget {
  const ShareDiagnosticsTile({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: const ValueKey('shareDiagnostics'),
    contentPadding: EdgeInsets.zero,
    title: Text(context.l10n.diagnosticsTitle),
    subtitle: Text(context.l10n.diagnosticsHint),
    value: value,
    onChanged: onChanged,
  );
}

/// Settings → Privacy: the diagnostics choice (applied at once), the app ID
/// for deletion requests, ad privacy choices, the legal pages and the
/// version.
class PrivacySection extends ConsumerWidget {
  const PrivacySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final share = ref.watch(
      settingsControllerProvider.select((s) => s.value?.shareDiagnostics),
    );
    final version = ref.watch(appVersionProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Text(
            l10n.settingsPrivacy,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ShareDiagnosticsTile(
          value: share ?? false,
          onChanged: (on) => runGuarded(
            context,
            () => ref
                .read(settingsControllerProvider.notifier)
                .setShareDiagnostics(on: on),
          ),
        ),
        if (share ?? false) const _AppInstanceId(),
        if (ref.watch(privacyOptionsRequiredProvider).value ?? false)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.privacyChoices),
            subtitle: Text(l10n.privacyChoicesHint),
            onTap: () => runGuarded(
              context,
              () => ref.read(adsServiceProvider).showPrivacyOptions(),
            ),
          ),
        for (final (label, uri) in [
          (l10n.privacyPolicy, LegalLinks.privacyPolicy),
          (l10n.termsOfUse, LegalLinks.terms),
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => unawaited(openLegalPage(context, ref, uri)),
          ),
        if (version != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.appVersion(version),
              style: TextStyle(fontSize: 12, color: c.ink2),
            ),
          ),
      ],
    );
  }
}

/// "Your app ID: …", for deletion requests; nothing until there is one.
class _AppInstanceId extends ConsumerWidget {
  const _AppInstanceId();

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<String?>(
    future: ref.read(diagnosticsProvider).appInstanceId(),
    builder: (context, snapshot) => switch (snapshot.data) {
      final id? => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SelectableText(
          context.l10n.appInstanceId(id),
          style: TextStyle(fontSize: 12, color: context.colors.ink2),
        ),
      ),
      null => const SizedBox.shrink(),
    },
  );
}
