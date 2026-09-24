import 'dart:developer';

import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';

/// Runs [action]. If it throws, logs the error, shows [failureMessage]
/// (by default, that the change wasn't saved) and returns null.
Future<T?> runGuarded<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? failureMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = failureMessage ?? context.l10n.errorSaving;
  try {
    return await action();
  } on Object catch (error, stackTrace) {
    log('Action failed', error: error, stackTrace: stackTrace);
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return null;
  }
}
