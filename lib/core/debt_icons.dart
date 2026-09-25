import 'package:flutter/material.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// The glyph for a kind of debt (drawn in white on the debt's colour).
IconData debtTypeIcon(DebtType type) => switch (type) {
  DebtType.creditCard => Icons.credit_card,
  DebtType.storeCard => Icons.shopping_bag_outlined,
  DebtType.loan => Icons.account_balance_outlined,
  DebtType.overdraft => Icons.account_balance_wallet_outlined,
  DebtType.studentLoan => Icons.school_outlined,
  DebtType.mortgage => Icons.home_outlined,
  DebtType.personal => Icons.people_outline,
  DebtType.other => Icons.receipt_long_outlined,
};
