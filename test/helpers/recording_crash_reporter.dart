import 'package:debt_destroyer/core/crash_reporter.dart';

class RecordingCrashReporter implements CrashReporter {
  final errors = <(Object, bool)>[];

  @override
  void recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) => errors.add((error, fatal));
}
