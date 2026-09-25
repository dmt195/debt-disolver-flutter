import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/ads/presentation/ads_providers.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/presentation/currency_picker.dart';
import 'package:debt_destroyer/features/settings/presentation/parameter_fields.dart';
import 'package:debt_destroyer/features/settings/presentation/reminders_section.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsControllerProvider);
    final settings = state.value;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: state.hasError
          ? ErrorRetryView(
              onRetry: () => ref.invalidate(settingsControllerProvider),
            )
          : settings == null
          ? const Center(child: CircularProgressIndicator())
          // Rebuild the fields when the currency changes: amounts are rescaled.
          : _SettingsForm(
              key: ValueKey(settings.currencyCode),
              settings: settings,
            ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings, super.key});

  final AppSettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _budget;
  late final ParameterControllers _parameters;
  String? _budgetError;
  Map<ParameterField, String> _parameterErrors = const {};

  @override
  void initState() {
    super.initState();
    final locale = ref.read(formatLocaleProvider);
    _budget = TextEditingController(
      text: formatAmountInput(widget.settings.monthlyBudget, locale),
    );
    _parameters = ParameterControllers(
      widget.settings.strategyParameters,
      locale: locale,
    );
  }

  @override
  void dispose() {
    _budget.dispose();
    _parameters.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final code = widget.settings.currencyCode;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // First, and saved at once: the setting people come here to change.
          RemindersSection(settings: widget.settings),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CurrencyPicker(
              value: code,
              onChanged: (next) => runGuarded(
                context,
                () => ref
                    .read(settingsControllerProvider.notifier)
                    .setCurrency(next),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              key: const ValueKey('budget'),
              controller: _budget,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.settingsBudget,
                border: const OutlineInputBorder(),
              ),
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
        ],
      ),
    );
  }

  Future<void> _save() async {
    // A field rejected last time keeps its message until it is edited.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final locale = ref.read(formatLocaleProvider);
    final code = widget.settings.currencyCode;
    final budgetMinor = parseAmountMinor(
      _budget.text,
      currencyCode: code,
      locale: locale,
    )!;
    final parameters = _parameters.parse(locale: locale, currencyCode: code);
    final controller = ref.read(settingsControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final result = await runGuarded(context, () async {
      final budgetErrors = await controller.setMonthlyBudget(budgetMinor);
      final parameterErrors = await controller.setStrategyParameters(
        parameters,
      );
      return (budgetErrors, parameterErrors);
    });
    if (result == null || !mounted) return;
    final (budgetErrors, parameterErrors) = result;
    setState(() {
      _budgetError = budgetErrors.contains(BudgetValidationError.notPositive)
          ? l10n.errorBudgetNotPositive
          : budgetErrors.contains(BudgetValidationError.tooLarge)
          ? l10n.errorTooLarge
          : null;
      _parameterErrors = parameterErrorMessages(l10n, parameterErrors, locale);
    });
    if (budgetErrors.isEmpty && parameterErrors.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSaved)));
    }
  }
}
