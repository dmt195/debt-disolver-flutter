import 'package:debt_destroyer/features/analysis/presentation/plan_change_lines.dart';
import 'package:debt_destroyer/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  final l10n = AppLocalizationsEn();

  TransferChange transfer({required int promoMonths}) => TransferChange(
    moved: const [
      MovedBalance(debtId: 'a', name: 'Visa', amount: Money(100000, 'GBP')),
    ],
    fee: const Money(4000, 'GBP'),
    creditLimit: const Money(104000, 'GBP'),
    limitAssumed: true,
    promoMonths: promoMonths,
  );

  test('includes the 0% promo line when there are promo months', () {
    final lines = planChangeLines(l10n, transfer(promoMonths: 12), 'en_GB');
    expect(lines, contains('0% for 12 months'));
  });

  test(
    'omits the promo line entirely at 0 months, never "0% for 0 months"',
    () {
      final lines = planChangeLines(l10n, transfer(promoMonths: 0), 'en_GB');
      expect(lines.where((l) => l.contains('0%')), isEmpty);
    },
  );
}
