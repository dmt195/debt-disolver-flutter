import 'package:debt_destroyer/app/app.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  // Load settings before the first frame so the router knows whether to
  // show onboarding.
  await container.read(settingsControllerProvider.future);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const DebtDestroyerApp(),
    ),
  );
}
