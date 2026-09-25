import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/illustrations/illustration.dart';
import 'package:debt_destroyer/core/illustrations/welcome_art.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/notifications.dart';
import 'package:debt_destroyer/core/widgets/outlined_card.dart';
import 'package:debt_destroyer/features/reminders/domain/reminder_schedule.dart';
import 'package:debt_destroyer/features/settings/presentation/currency_picker.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// First launch: three welcome pages on what the app does, then currency,
/// monthly budget and reminders (spec §4.1). The router leaves this screen
/// once onboarding is complete.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _budget = TextEditingController();
  final _pages = PageController();
  var _page = 0;
  String? _currency;
  bool _prefilled = false;
  bool _saving = false;

  /// The pay-day reminder: on by default (spec §4.1).
  bool _remind = true;
  int _day = 28;

  @override
  void dispose() {
    _budget.dispose();
    _pages.dispose();
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
    final c = context.colors;
    final welcome = [
      (const TangleToPath(), l10n.welcomeTitle1, l10n.onboardingIntro1),
      (const HighestRateFirst(), l10n.welcomeTitle2, l10n.onboardingIntro2),
      (const PaymentsRollOn(), l10n.welcomeTitle3, l10n.onboardingIntro3),
    ];
    final onWelcome = _page < welcome.length;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          if (onWelcome)
            TextButton(
              onPressed: () => _goTo(welcome.length),
              child: Text(l10n.welcomeSkip),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: PageView(
          controller: _pages,
          onPageChanged: (page) => setState(() => _page = page),
          children: [
            for (final (painter, title, body) in welcome)
              _WelcomePage(painter: painter, title: title, body: body),
            _setup(context, currency, locale),
          ],
        ),
      ),
      bottomNavigationBar: onWelcome
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Row(
                  children: [
                    Semantics(
                      label: l10n.welcomePage(_page + 1, welcome.length),
                      excludeSemantics: true,
                      child: Row(
                        children: [
                          for (var i = 0; i < welcome.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 6),
                              width: i == _page ? 22 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i == _page ? c.ink : c.track,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        // Only as tall as the button: the bar takes no more.
                        heightFactor: 1,
                        child: FilledButton(
                          onPressed: () => _goTo(_page + 1),
                          child: Text(l10n.welcomeNext),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  void _goTo(int page) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _setup(BuildContext context, String currency, String locale) {
    final l10n = context.l10n;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: const Center(
              child: Illustration(painter: SetupArt(), aspectRatio: 2.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.setupTitle, style: displayStyle(30)),
          const SizedBox(height: 16),
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.monthlyBudget,
              border: const OutlineInputBorder(),
            ),
            validator: (v) => _budgetProblem(v ?? '', currency, locale),
          ),
          const SizedBox(height: 16),
          OutlinedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.setupRemindMe),
                  subtitle: Text(l10n.setupRemindMeHint),
                  value: _remind,
                  onChanged: (on) => setState(() => _remind = on),
                ),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _day,
                  decoration: InputDecoration(labelText: l10n.remindersDay),
                  items: [
                    for (var day = 1; day <= 28; day++)
                      DropdownMenuItem(value: day, child: Text(ordinal(day))),
                    DropdownMenuItem(
                      value: kLastDay,
                      child: Text(l10n.remindersLastDay),
                    ),
                  ],
                  onChanged: _remind
                      ? (day) => setState(() => _day = day ?? 28)
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : () => _start(addDebt: true),
            child: Text(l10n.setupAddFirstDebt),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _saving ? null : () => _start(addDebt: false),
            child: Text(l10n.setupLater),
          ),
        ],
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

  /// Saves the choices and finishes onboarding, then opens the debt form
  /// ([addDebt]) or Home. A refused notification permission saves the
  /// reminder off and carries on.
  Future<void> _start({required bool addDebt}) async {
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
    final router = ref.read(routerProvider);
    final messenger = ScaffoldMessenger.of(context);
    final denied = context.l10n.remindersDenied;
    var refused = false;
    final done = await runGuarded(context, () async {
      await controller.setCurrency(currency);
      await controller.setMonthlyBudget(minor);
      final on =
          _remind &&
          await ref.read(notificationsServiceProvider).requestPermission();
      refused = _remind && !on;
      await controller.setPayDayReminder(on: on, day: _day);
      // The check-in nudge comes with the reminders, never without leave.
      await controller.setCheckInNudgeMonths(on ? 2 : 0);
      await controller.completeOnboarding();
      return true;
    });
    if (!(done ?? false)) return;
    router.go(addDebt ? Routes.newDebt : Routes.home);
    // The app-level messenger outlives this screen.
    if (refused) messenger.showSnackBar(SnackBar(content: Text(denied)));
    if (mounted) setState(() => _saving = false);
  }
}

/// One welcome page: a picture on a hi-vis panel, a headline and a line.
class _WelcomePage extends StatelessWidget {
  const _WelcomePage({
    required this.painter,
    required this.title,
    required this.body,
  });

  final CustomPainter painter;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.hiVis,
            border: Border.all(color: c.onHiVis, width: 2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            // Never so tall on a wide screen that it pushes the words away.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: Center(child: Illustration(painter: painter)),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(title, style: displayStyle(42, color: c.ink)),
        const SizedBox(height: 14),
        Text(body, style: TextStyle(fontSize: 17, height: 1.4, color: c.ink2)),
      ],
    );
  }
}
