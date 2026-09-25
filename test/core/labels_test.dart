import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_change_lines.dart';
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

  test('describes a balance transfer with no promo, not "0% for 0 months"', () {
    const p = StrategyParameters(promoMonths: 0);
    expect(
      strategyDescription(l10n, StrategyId.balanceTransfer, p, 'en_GB'),
      'Move card balances to a new card (4% fee, 15% interest).',
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

  test('the two best-known methods have nicknames', () {
    expect(
      strategyNickname(l10n, StrategyId.avalanche),
      'The avalanche method',
    );
    expect(strategyNickname(l10n, StrategyId.snowball), 'The snowball method');
    for (final id in [
      StrategyId.customOrder,
      StrategyId.cardTransfers,
      StrategyId.consolidation,
      StrategyId.balanceTransfer,
      StrategyId.minimumsOnly,
    ]) {
      expect(strategyNickname(l10n, id), isNull, reason: '$id');
    }
  });

  test('every ranked strategy says who it is best for', () {
    expect(
      strategyBestFor(l10n, StrategyId.avalanche),
      "Best if you'll stick to a plan: it costs the least in interest.",
    );
    expect(
      strategyBestFor(l10n, StrategyId.snowball),
      'Best if quick wins keep you going: whole debts disappear sooner.',
    );
    for (final s in standardStrategies(const StrategyParameters())) {
      expect(strategyBestFor(l10n, s.id), isNotEmpty, reason: '${s.id}');
    }
    expect(strategyBestFor(l10n, StrategyId.minimumsOnly), isNull);
  });

  test('describes card moves, with and without a promo', () {
    final lines = planChangeLines(
      l10n,
      const PlanChange.cardTransfers(
        moves: [
          CardMove(
            fromDebtId: 's',
            fromName: 'Store',
            toDebtId: 'a',
            toName: 'Amex',
            amount: Money(58252, 'GBP'),
            fee: Money(1748, 'GBP'),
            promo: Promo(aprBps: 0, months: 12),
          ),
          CardMove(
            fromDebtId: 'v',
            fromName: 'Visa',
            toDebtId: 'a',
            toName: 'Amex',
            amount: Money(10000, 'GBP'),
            fee: Money(300, 'GBP'),
          ),
        ],
        fee: Money(2048, 'GBP'),
      ),
      'en_GB',
    );
    expect(lines, [
      'Move £582.52 from Store to Amex (fee £17.48, 0% for 12 months)',
      'Move £100.00 from Visa to Amex (fee £3.00)',
      // Adjacent strings are intentional: one long line, split for width.
      // ignore: no_adjacent_strings_in_list
      "Check your card's terms: most won't take a balance from a card by "
          'the same bank. This plan assumes payments above the minimum clear '
          'the highest-rate balance first, as UK and US law requires.',
    ]);
  });
}
