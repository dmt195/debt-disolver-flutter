import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/domain/strategy_groups.dart';
import 'package:debt_destroyer/features/strategies/presentation/current_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Pick the plan to follow from the ways to pay off that work now, then
/// confirm (spec §6.2).
Future<void> showFollowSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _FollowSheet(),
    );

/// Confirm following [id] (from Plan detail).
Future<void> showFollowConfirm(BuildContext context, StrategyId id) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _FollowSheet(chosen: id),
    );

class _FollowSheet extends ConsumerStatefulWidget {
  const _FollowSheet({this.chosen});

  final StrategyId? chosen;

  @override
  ConsumerState<_FollowSheet> createState() => _FollowSheetState();
}

class _FollowSheetState extends ConsumerState<_FollowSheet> {
  late StrategyId? _chosen = widget.chosen;
  var _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final plans = ref.watch(currentPlansProvider).value;
    final followed =
        ref.watch(settingsControllerProvider).value?.followedStrategy ??
        (plans == null ? null : bestPayOffMethod(plans.ranked)?.strategyId);
    final options = [
      for (final r in plans?.ranked ?? const <PayoffResult>[])
        if (r is Feasible && !isBorrowingAlternative(r.strategyId))
          r.strategyId,
    ];
    final chosen = _chosen;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.ink2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (chosen == null) ...[
            Text(l10n.followSheetTitle, style: displayStyle(24, color: c.ink)),
            const SizedBox(height: 8),
            for (final id in options)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(strategyName(l10n, id)),
                subtitle: switch (strategyNickname(l10n, id)) {
                  final nickname? => Text(nickname),
                  null => null,
                },
                trailing: id == followed ? const Icon(Icons.check) : null,
                onTap: id == followed
                    ? null
                    : () => setState(() => _chosen = id),
              ),
          ] else ...[
            Text(
              strategyName(l10n, chosen),
              style: displayStyle(24, color: c.ink),
            ),
            const SizedBox(height: 8),
            Text(l10n.followConfirm),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      await ref
                          .read(progressControllerProvider.notifier)
                          .follow(chosen);
                      if (context.mounted) Navigator.of(context).pop();
                    },
              child: Text(l10n.followConfirmButton(strategyName(l10n, chosen))),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
          ],
        ],
      ),
    );
  }
}
