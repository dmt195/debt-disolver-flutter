import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('formats durations in years and months', () {
    expect(formatDuration(l10n, 1), '1 month');
    expect(formatDuration(l10n, 5), '5 months');
    expect(formatDuration(l10n, 12), '1 year');
    expect(formatDuration(l10n, 27), '2 years 3 months');
    expect(formatDuration(l10n, 13), '1 year 1 month');
  });

  test('names the synthetic debts and keeps user names', () {
    expect(
      planDebtName(
        l10n,
        const PlanDebt(
          id: kConsolidationDebtId,
          name: 'x',
          startingBalance: Money(1, 'GBP'),
        ),
      ),
      'Consolidation loan',
    );
    expect(
      planDebtName(
        l10n,
        const PlanDebt(id: 'a', name: 'Visa', startingBalance: Money(1, 'GBP')),
      ),
      'Visa',
    );
  });

  test('describes strategies with their parameters', () {
    const p = StrategyParameters();
    expect(
      strategyDescription(l10n, StrategyId.balanceTransfer, p, 'en_GB'),
      'Move card balances to a 0% card for 12 months (4% fee, then 15%).',
    );
    expect(
      strategyDescription(l10n, StrategyId.consolidation, p, 'en_GB'),
      'A 60-month loan at 5% replaces your cards, loans and overdrafts.',
    );
  });

  test('every strategy and debt type has a label', () {
    for (final id in StrategyId.values) {
      expect(strategyName(l10n, id), isNotEmpty);
    }
    for (final type in DebtType.values) {
      expect(debtTypeLabel(l10n, type), isNotEmpty);
    }
  });

  test('explains why a strategy does not apply', () {
    expect(
      notApplicableReason(l10n, NotApplicableReason.noTransferableBalances),
      'Not available: there are no card balances with interest to move.',
    );
    expect(
      notApplicableReason(l10n, NotApplicableReason.nothingToConsolidate),
      'Not available: none of your debts can be consolidated.',
    );
  });
}
