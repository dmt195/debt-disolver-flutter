import 'package:debt_destroyer/core/crash_reporter.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs [action]. If it throws, reports the error, shows [failureMessage]
/// (by default, that the change wasn't saved) and returns null.
Future<T?> runGuarded<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? failureMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final reporter = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(crashReporterProvider);
  final message = failureMessage ?? context.l10n.errorSaving;
  try {
    return await action();
  } on Object catch (error, stackTrace) {
    reporter.recordError(error, stackTrace, reason: 'Action failed');
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return null;
  }
}
