import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/parameter_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Edits a saved scenario: its name, budget and strategy settings.
class ScenarioFormScreen extends ConsumerWidget {
  const ScenarioFormScreen({required this.scenarioId, super.key});

  final String scenarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final title = Text(l10n.editScenarioTitle);
    final body = switch (ref.watch(scenariosProvider)) {
      AsyncData(:final value) => switch (value
          .where((s) => s.id == scenarioId)
          .firstOrNull) {
        final scenario? => _ScenarioForm(
          // Amounts are rescaled when the currency changes.
          key: ValueKey('${scenario.id}-${scenario.monthlyBudget.currency}'),
          scenario: scenario,
        ),
        null => Center(child: Text(l10n.errorGeneric)),
      },
      AsyncError() => ErrorRetryView(
        onRetry: () => ref.invalidate(scenariosProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
    return Scaffold(
      appBar: AppBar(title: title),
      body: body,
    );
  }
}

class _ScenarioForm extends ConsumerStatefulWidget {
  const _ScenarioForm({required this.scenario, super.key});

  final Scenario scenario;

  @override
  ConsumerState<_ScenarioForm> createState() => _ScenarioFormState();
}

class _ScenarioFormState extends ConsumerState<_ScenarioForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _budget;
  late final ParameterControllers _parameters;
  String? _nameError;
  String? _budgetError;
  Map<ParameterField, String> _parameterErrors = const {};

  @override
  void initState() {
    super.initState();
    final locale = ref.read(formatLocaleProvider);
    _name = TextEditingController(text: widget.scenario.name);
    _budget = TextEditingController(
      text: formatAmountInput(widget.scenario.monthlyBudget, locale),
    );
    _parameters = ParameterControllers(
      widget.scenario.parameters,
      locale: locale,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    _parameters.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final code = widget.scenario.monthlyBudget.currency;
    InputDecoration decoration(String label) =>
        InputDecoration(labelText: label, border: const OutlineInputBorder());
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              controller: _name,
              decoration: decoration(l10n.scenarioNameLabel),
              forceErrorText: _nameError,
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              controller: _budget,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: decoration(l10n.settingsBudget),
              validator: (v) =>
                  parseAmountMinor(
                        v ?? '',
                        currencyCode: code,
                        locale: locale,
                      ) ==
                      null
                  ? l10n.errorInvalidAmount(
                      formatAmountInput(Money(30000, code), locale),
                    )
                  : null,
              forceErrorText: _budgetError,
              onChanged: (_) {
                if (_budgetError != null) setState(() => _budgetError = null);
              },
            ),
          ),
          ParameterFields(
            controllers: _parameters,
            errors: _parameterErrors,
            currencyCode: code,
            onEdited: (f) {
              if (_parameterErrors.containsKey(f)) {
                setState(
                  () => _parameterErrors = {..._parameterErrors}..remove(f),
                );
              }
            },
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: Text(l10n.save)),
        ],
      ),
    );
  }

  Future<void> _save() async {
    // A field rejected last time keeps its message until it is edited.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final locale = ref.read(formatLocaleProvider);
    final code = widget.scenario.monthlyBudget.currency;
    final updated = widget.scenario.copyWith(
      name: _name.text,
      monthlyBudget: Money(
        parseAmountMinor(_budget.text, currencyCode: code, locale: locale)!,
        code,
      ),
      parameters: _parameters.parse(locale: locale, currencyCode: code),
    );
    final outcome = await runGuarded(
      context,
      () => ref.read(scenarioActionsProvider.notifier).update(updated),
    );
    if (!mounted) return;
    switch (outcome) {
      case ScenarioSaved():
        context.pop();
      case ScenarioRejected(
        :final nameErrors,
        :final budgetErrors,
        :final parameterErrors,
      ):
        setState(() {
          _nameError = nameErrors.contains(ScenarioNameError.empty)
              ? l10n.errorScenarioNameEmpty
              : nameErrors.contains(ScenarioNameError.duplicate)
              ? l10n.errorScenarioNameDuplicate
              : null;
          _budgetError =
              budgetErrors.contains(BudgetValidationError.notPositive)
              ? l10n.errorBudgetNotPositive
              : budgetErrors.contains(BudgetValidationError.tooLarge)
              ? l10n.errorTooLarge
              : null;
          _parameterErrors = parameterErrorMessages(
            l10n,
            parameterErrors,
            locale,
            controllers: _parameters,
          );
        });
      case null:
        break; // runGuarded already told the user
    }
  }
}
