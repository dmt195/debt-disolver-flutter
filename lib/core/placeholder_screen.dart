import 'package:flutter/material.dart';

/// Temporary screen body used until Plan 3 builds the real screen.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, this.actions, super.key});

  final String title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: Center(child: Text(title)),
  );
}
