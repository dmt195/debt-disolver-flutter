import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
import 'package:debt_destroyer/features/strategies/presentation/current_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Restart from here (spec §6.8): start fresh (the default, asked twice) or
/// keep history.
Future<void> showRestartSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _RestartSheet(),
    );

class _RestartSheet extends ConsumerStatefulWidget {
  const _RestartSheet();

  @override
  ConsumerState<_RestartSheet> createState() => _RestartSheetState();
}

class _RestartSheetState extends ConsumerState<_RestartSheet> {
  var _fresh = true;
  var _confirming = false;
  var _busy = false;

  Future<void> _restart({required bool clearHistory}) async {
    setState(() => _busy = true);
    await runGuarded(
      context,
      () => ref
          .read(progressControllerProvider.notifier)
          .restart(clearHistory: clearHistory),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final canRestart = ref.watch(homePlanProvider).value is HomeFollowing;

    Widget option({
      required bool selected,
      required String title,
      required String body,
      required VoidCallback onTap,
    }) => Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? c.hiVis : c.surface,
            border: Border.all(
              color: selected ? c.onHiVis : c.outline,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? c.onHiVis : c.ink,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: selected ? c.onHiVis : c.ink,
                      ),
                    ),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected ? c.onHiVis : c.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final children = _confirming
        ? [
            Text(l10n.restartFresh, style: displayStyle(26, color: c.ink)),
            const SizedBox(height: 8),
            Text(l10n.restartConfirm),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : () => _restart(clearHistory: true),
              child: Text(l10n.restartConfirmButton),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
          ]
        : [
            Text(l10n.homeRestart, style: displayStyle(26, color: c.ink)),
            const SizedBox(height: 6),
            Text(
              canRestart ? l10n.restartBody : l10n.restartUnavailable,
              style: TextStyle(color: c.ink2),
            ),
            const SizedBox(height: 12),
            option(
              selected: _fresh,
              title: l10n.restartFresh,
              body: l10n.restartFreshBody,
              onTap: () => setState(() => _fresh = true),
            ),
            const SizedBox(height: 10),
            option(
              selected: !_fresh,
              title: l10n.restartKeep,
              body: l10n.restartKeepBody,
              onTap: () => setState(() => _fresh = false),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: !canRestart || _busy
                        ? null
                        : _fresh
                        ? () => setState(() => _confirming = true)
                        : () => _restart(clearHistory: false),
                    child: Text(
                      _fresh ? l10n.restartFresh : l10n.restartKeepButton,
                    ),
                  ),
                ),
              ],
            ),
          ];
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
          ...children,
        ],
      ),
    );
  }
}
