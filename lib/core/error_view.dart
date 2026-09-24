import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';

/// A centred message with a retry button, for screens whose data failed to
/// load.
class ErrorRetryView extends StatelessWidget {
  const ErrorRetryView({required this.onRetry, this.message, super.key});

  final VoidCallback onRetry;

  /// Defaults to [AppLocalizations.errorGeneric].
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message ?? context.l10n.errorGeneric,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retry)),
        ],
      ),
    ),
  );
}
