import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/interest.dart';

/// Highest rate charged in [month] first (a promotional rate counts while it
/// lasts); ties broken by name, then id.
int compareHighestAprInMonth(Debt a, Debt b, int month) {
  final byApr = aprInMonth(b, month).compareTo(aprInMonth(a, month));
  return byApr != 0 ? byApr : _byNameThenId(a, b);
}

/// The rate-months [debt] charges from [month] to [horizon] inclusive: in
/// parts-per-million-months of the true monthly rate, what one pound paid
/// off it in [month] saves by the end of a plan that clears in [horizon].
/// Zero past the horizon.
int aprMonthsUntil(Debt debt, int month, int horizon) {
  if (month > horizon) return 0;
  final months = horizon - month + 1;
  final promo = debt.promo;
  // Months still at the promo rate within [month, horizon].
  final atPromo = promo == null
      ? 0
      : (promo.months - month + 1).clamp(0, months);
  final promoRate = promo?.aprBps ?? 0;
  return atPromo * monthlyRatePpm(promoRate) +
      (months - atPromo) * monthlyRatePpm(debt.aprBps);
}

/// Most interest saved per pound between [month] and [horizon] first; ties
/// broken by the rate charged in [month], then name, then id.
int compareMostInterestSaved(Debt a, Debt b, int month, int horizon) {
  final bySaving = aprMonthsUntil(
    b,
    month,
    horizon,
  ).compareTo(aprMonthsUntil(a, month, horizon));
  return bySaving != 0 ? bySaving : compareHighestAprInMonth(a, b, month);
}

/// Smallest balance first; ties broken by name, then id.
int compareSmallestBalanceFirst(Debt a, Debt b) {
  final byBalance = a.balance.compareTo(b.balance);
  return byBalance != 0 ? byBalance : _byNameThenId(a, b);
}

int _byNameThenId(Debt a, Debt b) {
  final byName = a.name.compareTo(b.name);
  return byName != 0 ? byName : a.id.compareTo(b.id);
}
