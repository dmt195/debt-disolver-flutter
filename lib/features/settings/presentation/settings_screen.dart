import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/presentation/currency_picker.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          // Rebuild the fields when the currency changes: amounts are rescaled.
          : _SettingsForm(
              key: ValueKey(settings.currencyCode),
              settings: settings,
            ),
    );
  }
}

enum _Field { budget, consolidationApr, promoMonths, transferFee, revertApr }

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings, super.key});

  final AppSettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<_Field, TextEditingController> _controllers;
  Map<_Field, String> _errors = const {};

  @override
  void initState() {
    super.initState();
    final locale = ref.read(formatLocaleProvider);
    final s = widget.settings;
    final p = s.strategyParameters;
    String percent(int bps) => formatPercentInput(bps, locale);
    _controllers = {
      _Field.budget: TextEditingController(
        text: formatAmountInput(s.monthlyBudget, locale),
      ),
      _Field.consolidationApr: TextEditingController(
        text: percent(p.consolidationAprBps),
      ),
      _Field.promoMonths: TextEditingController(text: '${p.promoMonths}'),
      _Field.transferFee: TextEditingController(
        text: percent(p.transferFeeBps),
      ),
      _Field.revertApr: TextEditingController(text: percent(p.revertAprBps)),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final code = widget.settings.currencyCode;
    final percentError = l10n.errorInvalidPercent(
      formatPercentInput(1990, locale),
    );
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);

    Widget field(
      _Field f,
      String label,
      String? Function(String) validate, {
      TextInputType keyboard = numberKeyboard,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey(f),
        controller: _controllers[f],
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (v) => validate(v ?? ''),
        forceErrorText: _errors[f],
        onChanged: (_) {
          if (_errors.containsKey(f)) {
            setState(() => _errors = {..._errors}..remove(f));
          }
        },
      ),
    );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          field(
            _Field.budget,
            l10n.settingsBudget,
            (v) =>
                parseAmountMinor(v, currencyCode: code, locale: locale) == null
                ? l10n.errorInvalidAmount(
                    formatAmountInput(Money(30000, code), locale),
                  )
                : null,
          ),
          heading(l10n.settingsConsolidation),
          field(
            _Field.consolidationApr,
            l10n.settingsConsolidationApr,
            (v) => parsePercentBps(v, locale) == null ? percentError : null,
          ),
          heading(l10n.settingsTransfer),
          field(
            _Field.promoMonths,
            l10n.settingsPromoMonths,
            (v) => parseWholeNumber(v) == null ? l10n.errorWholeNumber : null,
            keyboard: TextInputType.number,
          ),
          field(
            _Field.transferFee,
            l10n.settingsTransferFee,
            (v) => parsePercentBps(v, locale) == null ? percentError : null,
          ),
          field(
            _Field.revertApr,
            l10n.settingsRevertApr,
            (v) => parsePercentBps(v, locale) == null ? percentError : null,
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
    String text(_Field f) => _controllers[f]!.text;
    final budgetMinor = parseAmountMinor(
      text(_Field.budget),
      currencyCode: widget.settings.currencyCode,
      locale: locale,
    )!;
    final parameters = StrategyParameters(
      consolidationAprBps: parsePercentBps(
        text(_Field.consolidationApr),
        locale,
      )!,
      promoMonths: parseWholeNumber(text(_Field.promoMonths))!,
      transferFeeBps: parsePercentBps(text(_Field.transferFee), locale)!,
      revertAprBps: parsePercentBps(text(_Field.revertApr), locale)!,
    );
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
    final errors = <_Field, String>{
      if (budgetErrors.contains(BudgetValidationError.notPositive))
        _Field.budget: l10n.errorBudgetNotPositive,
      if (budgetErrors.contains(BudgetValidationError.tooLarge))
        _Field.budget: l10n.errorTooLarge,
      for (final e in parameterErrors)
        switch (e) {
          StrategyParametersValidationError.consolidationAprOutOfRange =>
            _Field.consolidationApr,
          StrategyParametersValidationError.transferFeeOutOfRange =>
            _Field.transferFee,
          StrategyParametersValidationError.promoMonthsOutOfRange =>
            _Field.promoMonths,
          StrategyParametersValidationError.revertAprOutOfRange =>
            _Field.revertApr,
        }: switch (e) {
          StrategyParametersValidationError.promoMonthsOutOfRange =>
            l10n.errorPromoMonthsRange(kMaxPromoMonths),
          _ => l10n.errorRateRange,
        },
    };
    setState(() => _errors = errors);
    if (errors.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSaved)));
    }
  }
}
