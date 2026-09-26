import 'package:debt_destroyer/app/diagnostic_events.dart';
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:debt_destroyer/core/diagnostics.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/widgets/hi_vis_block.dart';
import 'package:debt_destroyer/core/widgets/outlined_card.dart';
import 'package:debt_destroyer/core/widgets/rate_field.dart';
import 'package:debt_destroyer/features/debts/domain/debt_draft.dart';
import 'package:debt_destroyer/features/debts/domain/promo_dates.dart';
import 'package:debt_destroyer/features/loans/domain/loan_calculator.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// "What would a loan cost?" (spec §4): pick the figure to work out, fill in
/// the other three, and see it with the totals and the balance falling.
/// Nothing is saved; leaving the screen clears it.
class LoanCalculatorScreen extends ConsumerStatefulWidget {
  const LoanCalculatorScreen({super.key});

  @override
  ConsumerState<LoanCalculatorScreen> createState() =>
      _LoanCalculatorScreenState();
}

class _LoanCalculatorScreenState extends ConsumerState<LoanCalculatorScreen> {
  final _amount = TextEditingController();
  final _payment = TextEditingController();
  final _term = TextEditingController();
  late final RateController _rate;
  LoanUnknown _unknown = LoanUnknown.payment;
  var _termInYears = true;

  /// The unknowns already solved this visit: each is counted once, not per
  /// keystroke.
  final _counted = <LoanUnknown>{};

  @override
  void initState() {
    super.initState();
    _rate = RateController(locale: ref.read(formatLocaleProvider));
  }

  @override
  void dispose() {
    _amount.dispose();
    _payment.dispose();
    _term.dispose();
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final locale = ref.watch(formatLocaleProvider);
    final currency =
        ref.watch(
          settingsControllerProvider.select((s) => s.value?.currencyCode),
        ) ??
        'GBP';
    final now = ref.watch(clockProvider)();

    Money? money(TextEditingController controller) {
      final minor = parseAmountMinor(
        controller.text,
        currencyCode: currency,
        locale: locale,
      );
      return minor == null ? null : Money(minor, currency);
    }

    final termNumber = parseWholeNumber(_term.text);
    final result = solveLoan(
      unknown: _unknown,
      amount: money(_amount),
      aprBps: _rate.aprBps(locale),
      payment: money(_payment),
      months: termNumber == null ? null : termNumber * (_termInYears ? 12 : 1),
    );
    final solved = result is LoanSolved ? result : null;
    if (solved != null && _counted.add(_unknown)) {
      ref
          .read(diagnosticsProvider)
          .logEvent(DiagnosticEvent.loanCalculatorUsed(_unknown));
    }

    Widget input(String key, String label, TextEditingController controller) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            key: ValueKey(key),
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        );

    final inputs = <Widget>[
      if (_unknown != LoanUnknown.amount)
        input('calcAmount', l10n.fieldAmount, _amount),
      if (_unknown != LoanUnknown.rate)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RateField(
            controller: _rate,
            fieldKey: const ValueKey<String>('calcRate'),
            aprLabel: l10n.fieldApr,
            monthlyLabel: l10n.fieldAprMonthly,
            onChanged: (_) => setState(() {}),
          ),
        ),
      if (_unknown != LoanUnknown.term) ...[
        TextFormField(
          key: const ValueKey('calcTerm'),
          controller: _term,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l10n.fieldTerm,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: SegmentedButton<bool>(
            key: const ValueKey('calcTermUnit'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: true, label: Text(l10n.termYears)),
              ButtonSegment(value: false, label: Text(l10n.termMonths)),
            ],
            selected: {_termInYears},
            onSelectionChanged: (s) => setState(() => _termInYears = s.single),
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (_unknown != LoanUnknown.payment)
        input('calcPayment', l10n.fieldMonthlyPayment, _payment),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.loanCalculatorTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(l10n.calcWorkOut, style: TextStyle(fontSize: 13, color: c.ink2)),
          const SizedBox(height: 6),
          _UnknownPicker(
            selected: _unknown,
            onChanged: (u) => setState(() => _unknown = u),
          ),
          const SizedBox(height: 12),
          HiVisBlock(
            key: const ValueKey('hero'),
            // Announced as it changes: the answer is what this screen is
            // for, and it's above the fields being typed in.
            child: Semantics(
              liveRegion: true,
              child: _Answer(unknown: _unknown, result: result, locale: locale),
            ),
          ),
          const SizedBox(height: 16),
          ...inputs,
          // The chart keeps this place in the list while there's an answer,
          // so typing doesn't replay its draw-in.
          if (solved != null)
            _Totals(loan: solved, locale: locale, now: now)
          else
            const SizedBox.shrink(),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: solved == null
                ? null
                : () => context.push(
                    Routes.newDebt,
                    extra: DebtDraft(
                      balance: solved.balance,
                      aprBps: solved.aprBps,
                      payment: solved.payment,
                      lastPaymentYearMonth: yearMonthAfter(solved.months, now),
                    ),
                  ),
            child: Text(l10n.calcAddAsDebt),
          ),
        ],
      ),
    );
  }
}

/// The worked-out figure, big; or why it can't be worked out; or a nudge to
/// fill in the rest.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.unknown,
    required this.result,
    required this.locale,
  });

  final LoanUnknown unknown;
  final LoanResult? result;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    const message = TextStyle(fontSize: 16, height: 1.35);
    switch (result) {
      case null:
        return Text(l10n.calcFillIn, style: message);
      case LoanImpossible(:final problem):
        return Text(switch (problem) {
          LoanProblem.neverClears => l10n.loanNeverClears,
          LoanProblem.rateTooHigh => l10n.loanRateTooHigh,
          LoanProblem.rateBelowZero => l10n.loanRateBelowZero,
          LoanProblem.outOfRange => l10n.loanOutOfRange,
        }, style: message);
      case final LoanSolved loan:
        final (figure, caption) = switch (unknown) {
          LoanUnknown.payment => (
            formatMoney(loan.payment, locale),
            l10n.calcPerMonth,
          ),
          LoanUnknown.amount => (
            formatMoney(loan.balance, locale),
            l10n.calcCanBorrow,
          ),
          LoanUnknown.rate => (
            formatPercent(loan.aprBps, locale),
            l10n.calcApr,
          ),
          LoanUnknown.term => (
            formatDuration(l10n, loan.months),
            l10n.calcToPayOff,
          ),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A money or rate figure shrinks to stay on one line rather than
            // split mid-number; a duration wraps at its spaces.
            if (unknown == LoanUnknown.term)
              Text(figure, style: displayStyle(44, color: c.onHiVis))
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  figure,
                  maxLines: 1,
                  style: displayStyle(44, color: c.onHiVis),
                ),
              ),
            const SizedBox(height: 4),
            Text(caption, style: const TextStyle(fontSize: 15)),
            if (unknown == LoanUnknown.rate) ...[
              const SizedBox(height: 4),
              Text(
                l10n.rateAsMonthly(
                  formatMonthlyRate(monthlyRatePpm(loan.aprBps), locale),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ],
        );
    }
  }
}

/// Total interest and total repaid, then the balance falling.
class _Totals extends StatelessWidget {
  const _Totals({required this.loan, required this.locale, required this.now});

  final LoanSolved loan;
  final String locale;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    Widget total(String label, Money amount) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: c.ink2)),
        Text(
          formatMoney(amount, locale),
          style: displayStyle(20, color: c.ink),
        ),
      ],
    );
    return OutlinedCard(
      title: l10n.calcChartTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              total(l10n.calcTotalInterest, loan.totalInterest),
              total(l10n.calcTotalRepaid, loan.totalPaid),
            ],
          ),
          const SizedBox(height: 12),
          BalanceLineChart(
            lines: [
              ChartLine(
                values: loanBalanceSeries(loan),
                color: c.ink,
                width: 3,
              ),
            ],
            semanticLabel: l10n.calcChartLabel(
              formatMoney(loan.balance, locale),
              formatDuration(l10n, loan.months),
            ),
            startLabel: DateFormat.yMMM(locale).format(now),
            endLabel: DateFormat.yMMM(locale)
                .format(DateTime(now.year, now.month + loan.months)),
          ),
        ],
      ),
    );
  }
}

/// What to work out: four equal segments across the width, or wrapping
/// chips once text is large enough that the segments would break words.
class _UnknownPicker extends StatelessWidget {
  const _UnknownPicker({required this.selected, required this.onChanged});

  final LoanUnknown selected;
  final ValueChanged<LoanUnknown> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = {
      LoanUnknown.payment: l10n.calcPayment,
      LoanUnknown.amount: l10n.calcAmount,
      LoanUnknown.rate: l10n.calcRate,
      LoanUnknown.term: l10n.calcTerm,
    };
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Wrap(
        key: const ValueKey('unknown'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final MapEntry(key: unknown, value: label) in labels.entries)
            ChoiceChip(
              label: Text(label),
              selected: unknown == selected,
              onSelected: (_) => onChanged(unknown),
            ),
        ],
      );
    }
    return SegmentedButton<LoanUnknown>(
      key: const ValueKey('unknown'),
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
      segments: [
        for (final MapEntry(key: unknown, value: label) in labels.entries)
          ButtonSegment(value: unknown, label: Text(label)),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.single),
    );
  }
}
