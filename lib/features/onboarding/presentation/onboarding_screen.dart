import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/settings/presentation/currency_picker.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// First launch: what the app does, then currency and monthly budget. The
/// router leaves this screen once onboarding is complete.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _budget = TextEditingController();
  String? _currency;
  bool _prefilled = false;
  bool _saving = false;

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final state = ref.watch(settingsControllerProvider);
    if (state.hasError) {
      return Scaffold(
        body: ErrorRetryView(
          onRetry: () => ref.invalidate(settingsControllerProvider),
        ),
      );
    }
    final settings = state.value;
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final currency = _currency ??= settings.currencyCode;
    if (!_prefilled) {
      _prefilled = true;
      _budget.text = formatAmountInput(settings.monthlyBudget, locale);
    }
    final theme = Theme.of(context);

    Widget point(IconData icon, String text) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(text),
    );

    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(l10n.onboardingTitle, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              point(Icons.compare_arrows, l10n.onboardingIntro1),
              point(Icons.trending_down, l10n.onboardingIntro2),
              point(Icons.flag_outlined, l10n.onboardingIntro3),
              const SizedBox(height: 24),
              CurrencyPicker(
                value: currency,
                onChanged: (code) => setState(() => _currency = code),
              ),
              const SizedBox(height: 16),
              Text(l10n.onboardingBudgetQuestion),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('budget'),
                controller: _budget,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.monthlyBudget,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => _budgetProblem(v ?? '', currency, locale),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _start,
                child: Text(l10n.onboardingStart),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _budgetProblem(String text, String currency, String locale) {
    final l10n = context.l10n;
    final minor = parseAmountMinor(
      text,
      currencyCode: currency,
      locale: locale,
    );
    if (minor == null) {
      return l10n.errorInvalidAmount(
        formatAmountInput(Money(30000, currency), locale),
      );
    }
    final errors = validateBudget(Money(minor, currency));
    if (errors.contains(BudgetValidationError.tooLarge)) {
      return l10n.errorTooLarge;
    }
    if (errors.contains(BudgetValidationError.notPositive)) {
      return l10n.errorBudgetNotPositive;
    }
    return null;
  }

  Future<void> _start() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final locale = ref.read(formatLocaleProvider);
    final currency = _currency!;
    final minor = parseAmountMinor(
      _budget.text,
      currencyCode: currency,
      locale: locale,
    )!;
    setState(() => _saving = true);
    final controller = ref.read(settingsControllerProvider.notifier);
    await runGuarded(context, () async {
      await controller.setCurrency(currency);
      await controller.setMonthlyBudget(minor);
      await controller.completeOnboarding();
    });
    if (mounted) setState(() => _saving = false);
  }
}
