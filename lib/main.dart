import 'dart:developer';

import 'package:debt_destroyer/app/app.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  // Load settings before the first frame so the router knows whether to
  // show onboarding. If loading fails the app still starts; the screens show
  // the error and offer a retry.
  try {
    await container.read(settingsControllerProvider.future);
  } on Object catch (error, stackTrace) {
    log('Settings failed to load', error: error, stackTrace: stackTrace);
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const DebtDestroyerApp(),
    ),
  );
}
