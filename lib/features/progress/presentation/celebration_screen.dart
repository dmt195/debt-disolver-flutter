import 'dart:async';

import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/illustrations/wrecking_ball.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/text_sharer.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/progress/domain/progress_math.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A cleared debt, celebrated (spec §4.10). Shown straight after the check-in
/// that cleared it; opened any other way the route goes Home.
class CelebrationScreen extends ConsumerWidget {
  const CelebrationScreen({required this.debtId, super.key});

  final String debtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final locale = ref.watch(formatLocaleProvider);
    final outcome = ref.watch(progressControllerProvider);
    final cleared = outcome?.cleared ?? const <Cleared>[];
    final index = cleared.indexWhere((x) => x.debtId == debtId);
    // The route redirects Home when there is nothing to celebrate.
    if (index < 0) return const Scaffold();
    final debt = cleared[index];
    final gone = formatMoney(debt.gone, locale);

    void keepGoing() {
      if (index + 1 < cleared.length) {
        context.go(Routes.cleared(cleared[index + 1].debtId));
      } else if (ref.read(debtsProvider).value?.isEmpty ?? false) {
        context.go(Routes.debtFree);
      } else {
        context.go(Routes.home);
      }
    }

    return _HiVisPage(
      art: (t) => WreckingBallScene(progress: t),
      duration: const Duration(milliseconds: 1100),
      onClose: () => context.go(Routes.home),
      title: l10n.celebrationTitle(debt.name),
      lines: [l10n.celebrationGone(gone)],
      card: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (debt.next case final next?) ...[
            Text(
              l10n.celebrationRollsOn(formatMoney(debt.rollsOn, locale), next),
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              for (var i = 0; i < debt.totalCount; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: i < debt.clearedCount ? c.onHiVis : Colors.white,
                      border: Border.all(color: c.onHiVis, width: 2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.celebrationCount(debt.clearedCount, debt.totalCount),
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
      share: () => ref
          .read(textSharerProvider)
          .share(l10n.celebrationShareText(debt.name, gone)),
      primary: l10n.celebrationKeepGoing,
      onPrimary: keepGoing,
    );
  }
}

/// Every debt cleared.
class DebtFreeScreen extends ConsumerWidget {
  const DebtFreeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final summary = ref.watch(progressSummaryProvider).value;
    final since = ref.watch(progressHistoryProvider).value?.firstStart?.at;
    final now = ref.watch(clockProvider)();
    final amount = summary == null
        ? ''
        : formatMoney(summary.paid.amount, locale);
    final months = since == null ? 0 : monthIndex(since, now);
    final body = l10n.debtFreeBody(
      amount,
      formatDuration(l10n, months < 1 ? 1 : months),
    );
    return _HiVisPage(
      art: (t) => DebtFreeScene(progress: t),
      duration: const Duration(milliseconds: 900),
      onClose: () => context.go(Routes.home),
      title: l10n.debtFreeTitle,
      lines: [body],
      share: () => ref.read(textSharerProvider).share(l10n.debtFreeShareText),
      primary: l10n.resultDone,
      onPrimary: () => context.go(Routes.home),
    );
  }
}

/// A full hi-vis screen: art, a slammed-in headline, a white card and
/// Share beside the main action (canvas "A · Debt cleared"). One timeline
/// drives the art and the headline, once per screen (spec §5.2).
class _HiVisPage extends StatefulWidget {
  const _HiVisPage({
    required this.art,
    required this.duration,
    required this.onClose,
    required this.title,
    required this.lines,
    required this.share,
    required this.primary,
    required this.onPrimary,
    this.card,
  });

  /// The picture at a point (0–1) of the timeline.
  final Widget Function(double t) art;
  final Duration duration;
  final VoidCallback onClose;
  final String title;
  final List<String> lines;
  final Widget? card;
  final Future<void> Function() share;
  final String primary;
  final VoidCallback onPrimary;

  @override
  State<_HiVisPage> createState() => _HiVisPageState();
}

class _HiVisPageState extends State<_HiVisPage>
    with SingleTickerProviderStateMixin {
  late final _timeline = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _timeline.value = 1;
    } else if (!_started) {
      _timeline.forward();
    }
    _started = true;
  }

  @override
  void dispose() {
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.hiVis,
      body: SafeArea(
        child: DefaultTextStyle.merge(
          style: TextStyle(color: c.onHiVis),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: Icon(Icons.close, color: c.onHiVis),
                  tooltip: l10n.close,
                  onPressed: widget.onClose,
                ),
              ),
              AnimatedBuilder(
                animation: _timeline,
                builder: (context, _) {
                  final t = _timeline.value;
                  // The headline slams in over the last 30%.
                  final slam = ((t - 0.7) / 0.3).clamp(0.0, 1.0);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      widget.art(t),
                      const SizedBox(height: 12),
                      Opacity(
                        key: const ValueKey('headline'),
                        opacity: slam,
                        alwaysIncludeSemantics: true,
                        child: Transform.scale(
                          scale: 1.3 - 0.3 * Curves.easeOutBack.transform(slam),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            widget.title,
                            style: displayStyle(54, color: c.onHiVis),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              for (final line in widget.lines)
                Text(line, style: const TextStyle(fontSize: 17, height: 1.4)),
              if (widget.card case final card?) ...[
                const SizedBox(height: 14),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: c.onHiVis, width: 2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: card,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => unawaited(widget.share()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.onHiVis,
                        side: BorderSide(color: c.onHiVis, width: 2),
                      ),
                      child: Text(l10n.celebrationShare),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: widget.onPrimary,
                      style: FilledButton.styleFrom(
                        backgroundColor: c.onHiVis,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(widget.primary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
