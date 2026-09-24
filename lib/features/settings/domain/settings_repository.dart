import 'package:debt_destroyer/features/settings/domain/app_settings.dart';

abstract interface class SettingsRepository {
  /// Stored settings. Missing or invalid values fall back to defaults.
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}
