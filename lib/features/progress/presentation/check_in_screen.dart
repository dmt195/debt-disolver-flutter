import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';

/// Today's balances, pre-filled from the plan (spec §4.8).
class CheckInScreen extends StatelessWidget {
  const CheckInScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(context.l10n.checkInTitle)));
}
