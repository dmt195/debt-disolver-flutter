import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/debt_colors.dart';
import 'package:debt_destroyer/core/debt_icons.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/widgets/outlined_card.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/progress/domain/progress_math.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/presentation/current_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Today's balances, pre-filled with what the plan expected (spec §4.8).
class CheckInScreen extends ConsumerWidget {
  const CheckInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final debts = ref.watch(debtsProvider).value;
    final history = ref.watch(progressHistoryProvider).value;
    final home = ref.watch(homePlanProvider).value;
    final settings = ref.watch(settingsControllerProvider).value;
    final body =
        debts == null || history == null || home == null || settings == null
        ? const Center(child: CircularProgressIndicator())
        : _CheckInForm(
            // A debt added from here gets a field of its own.
            key: ValueKey([for (final d in debts) d.id].join(',')),
            debts: debts,
            currencyCode: settings.currencyCode,
            expected: switch (home) {
              HomeFollowing(:final result) => expectedBalances(
                result.plan,
                switch (history.lastCheckIn) {
                  final last? => monthIndex(last.at, ref.read(clockProvider)()),
                  null => 0,
                },
                debts,
              ),
              _ => {for (final d in debts) d.id: d.balance},
            },
          );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.close,
          // Opened from a notification there is nothing to go back to.
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.home),
        ),
        title: Text(l10n.checkInTitle),
      ),
      body: body,
    );
  }
}

class _CheckInForm extends ConsumerStatefulWidget {
  const _CheckInForm({
    required this.debts,
    required this.currencyCode,
    required this.expected,
    super.key,
  });

  final List<Debt> debts;
  final String currencyCode;

  /// What the plan expected each debt to owe today.
  final Map<String, Money> expected;

  @override
  ConsumerState<_CheckInForm> createState() => _CheckInFormState();
}

class _CheckInFormState extends ConsumerState<_CheckInForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final locale = ref.read(formatLocaleProvider);
    _fields = {
      for (final d in widget.debts)
        d.id: TextEditingController(
          text: formatAmountInput(widget.expected[d.id] ?? d.balance, locale),
        ),
    };
  }

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  int? _minor(String id) => parseAmountMinor(
    _fields[id]!.text,
    currencyCode: widget.currencyCode,
    locale: ref.read(formatLocaleProvider),
  );

  String? _problem(String? text, String locale) {
    final l10n = context.l10n;
    final minor = parseAmountMinor(
      text ?? '',
      currencyCode: widget.currencyCode,
      locale: locale,
    );
    if (minor == null || minor < 0) {
      return l10n.errorInvalidAmount(
        formatAmountInput(Money(123400, widget.currencyCode), locale),
      );
    }
    if (minor > kMaxAmountMinor) return l10n.errorTooLarge;
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final saved = await runGuarded(context, () async {
      await ref.read(progressControllerProvider.notifier).saveCheckIn({
        for (final d in widget.debts)
          d.id: Money(_minor(d.id)!, widget.currencyCode),
      });
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved ?? false) context.pushReplacement(Routes.checkInResult);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final locale = ref.watch(formatLocaleProvider);
    final ids = [for (final d in widget.debts) d.id];
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(l10n.checkInHeading, style: displayStyle(28, color: c.ink)),
          const SizedBox(height: 6),
          Text(l10n.checkInIntro, style: TextStyle(color: c.ink2)),
          const SizedBox(height: 12),
          for (final d in widget.debts) ...[
            _DebtRow(
              debt: d,
              color: debtColor(c, d.id, ids),
              expected: widget.expected[d.id] ?? d.balance,
              controller: _fields[d.id]!,
              entered: _minor(d.id),
              validator: (text) => _problem(text, locale),
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push(Routes.newDebt),
              child: Text(l10n.checkInNewDebt),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(l10n.checkInSave),
          ),
        ],
      ),
    );
  }
}

class _DebtRow extends ConsumerWidget {
  const _DebtRow({
    required this.debt,
    required this.color,
    required this.expected,
    required this.controller,
    required this.entered,
    required this.validator,
    required this.onChanged,
  });

  final Debt debt;
  final Color color;
  final Money expected;
  final TextEditingController controller;

  /// The amount typed, in minor units, if it reads as one.
  final int? entered;
  final String? Function(String?) validator;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final locale = ref.watch(formatLocaleProvider);
    final paidOff = entered == 0;
    final up = entered != null && entered! > debt.balance.minor
        ? Money(entered! - debt.balance.minor, debt.balance.currency)
        : null;
    return OutlinedCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  debtTypeIcon(debt.type),
                  color: Colors.white,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      debt.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (paidOff)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: c.hiVis,
                          border: Border.all(color: c.onHiVis, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.checkInPaidOff,
                          style: TextStyle(
                            color: c.onHiVis,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                l10n.checkInPlan(formatMoney(expected, locale)),
                style: TextStyle(fontSize: 12.5, color: c.ink2),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('checkIn-${debt.id}'),
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: l10n.checkInOweToday),
            style: displayStyle(22, color: c.ink),
            validator: validator,
            onChanged: (_) => onChanged(),
          ),
          if (up != null) ...[
            const SizedBox(height: 6),
            Text(
              l10n.checkInWentUp(formatMoney(up, locale)),
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}
