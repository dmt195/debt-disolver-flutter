import 'package:flutter/foundation.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// A debt paid off through a check-in or "Mark as paid off". It stays in
/// the database but is never planned for (spec §6.6).
@immutable
class ClearedDebt {
  const ClearedDebt({
    required this.id,
    required this.name,
    required this.type,
    required this.clearedAt,
  });

  final String id;
  final String name;
  final DebtType type;
  final DateTime clearedAt;
}
