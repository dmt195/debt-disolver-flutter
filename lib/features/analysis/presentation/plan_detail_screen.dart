import 'package:debt_destroyer/core/placeholder_screen.dart';
import 'package:flutter/material.dart';
import 'package:payoff_engine/payoff_engine.dart';

class PlanDetailScreen extends StatelessWidget {
  const PlanDetailScreen({required this.strategyId, super.key});

  final StrategyId strategyId;

  @override
  Widget build(BuildContext context) =>
      PlaceholderScreen(title: 'Plan: ${strategyId.name}');
}
