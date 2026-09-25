import 'package:debt_destroyer/app/theme.dart';
import 'package:flutter/painting.dart';

const _portion = '#from-';

/// The user's debt a plan column belongs to: a card-transfer portion
/// (`<card>#from-<source>`) belongs to its card.
String baseDebtId(String planDebtId) {
  final i = planDebtId.indexOf(_portion);
  return i < 0 ? planDebtId : planDebtId.substring(0, i);
}

/// A debt's colour slot: its position in the user's own list order, so it
/// never changes with the strategy. Debts the user didn't enter (a
/// consolidation loan, a transfer card) take the slot after the list.
int debtColorIndex(String planDebtId, List<String> listOrderIds) {
  final i = listOrderIds.indexOf(baseDebtId(planDebtId));
  return (i < 0 ? listOrderIds.length : i) % 6;
}

Color debtColor(
  DestroyerColors colors,
  String planDebtId,
  List<String> listOrderIds,
) => colors.series[debtColorIndex(planDebtId, listOrderIds)];
