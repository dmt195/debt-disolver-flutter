import 'package:debt_destroyer/core/crash_reporter.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks for a scenario name. [submit] tries to save it and returns an error
/// message, or null once saved; the dialog then closes and returns true.
Future<bool> showScenarioNameDialog(
  BuildContext context, {
  required String title,
  required Future<String?> Function(String name) submit,
  String initialName = '',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ScenarioNameDialog(
        title: title,
        submit: submit,
        initialName: initialName,
      ),
    ) ??
    false;

/// The message for a rejected scenario, or null when it was saved.
String? scenarioOutcomeMessage(
  AppLocalizations l10n,
  ScenarioSaveOutcome outcome,
) => switch (outcome) {
  ScenarioSaved() => null,
  ScenarioRejected(:final nameErrors)
      when nameErrors.contains(ScenarioNameError.empty) =>
    l10n.errorScenarioNameEmpty,
  ScenarioRejected(:final nameErrors)
      when nameErrors.contains(ScenarioNameError.duplicate) =>
    l10n.errorScenarioNameDuplicate,
  ScenarioRejected() => l10n.errorScenarioInvalid,
};

class _ScenarioNameDialog extends ConsumerStatefulWidget {
  const _ScenarioNameDialog({
    required this.title,
    required this.submit,
    required this.initialName,
  });

  final String title;
  final Future<String?> Function(String name) submit;
  final String initialName;

  @override
  ConsumerState<_ScenarioNameDialog> createState() =>
      _ScenarioNameDialogState();
}

class _ScenarioNameDialogState extends ConsumerState<_ScenarioNameDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    String? error;
    try {
      error = await widget.submit(_name.text);
    } on Object catch (e, stackTrace) {
      ref
          .read(crashReporterProvider)
          .recordError(e, stackTrace, reason: 'Saving a scenario failed');
      if (!mounted) return;
      error = context.l10n.errorSaving;
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('scenarioName'),
        controller: _name,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l10n.scenarioNameLabel,
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
