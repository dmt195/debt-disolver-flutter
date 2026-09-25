import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/illustrations/scenes.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/widgets/hi_vis_block.dart';
import 'package:debt_destroyer/core/widgets/outlined_card.dart';
import 'package:debt_destroyer/features/home/presentation/home_progress.dart';
import 'package:debt_destroyer/features/progress/domain/progress_math.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
import 'package:debt_destroyer/features/strategies/presentation/current_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Where the check-in leaves you (spec §4.9).
class CheckInResultScreen extends ConsumerWidget {
  const CheckInResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final locale = ref.watch(formatLocaleProvider);
    final now = ref.watch(clockProvider)();
    final outcome = ref.watch(progressControllerProvider);
    final summary = ref.watch(progressSummaryProvider).value;
    final home = ref.watch(homePlanProvider).value;
    final monthsNow = home is HomeFollowing
        ? home.result.plan.monthsToClear
        : null;
    String month(int months) =>
        DateFormat.yMMM(locale).format(DateTime(now.year, now.month + months));

    // The headline amount counts up from zero (spec §5.2).
    final (
      String Function(double t)? big,
      String small,
    ) = switch (summary?.standing) {
      AheadMoney(:final amount) => (
        (t) => formatMoney(_part(amount, t), locale),
        l10n.resultAheadOfPlan,
      ),
      AheadMonths(:final months) => (
        (_) => l10n.resultMonths(months),
        l10n.resultAheadOfPlan,
      ),
      Behind(:final amount) => (
        (t) => formatMoney(_part(amount, t), locale),
        l10n.resultBehindPlan,
      ),
      OnTrack() => (null, l10n.resultOnTrack),
      NoProgressYet() || null => (null, l10n.resultCheckedIn),
    };
    Widget headline(double t) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClimbWall(percent: summary?.paid.percent ?? 0, progress: t),
        const SizedBox(height: 8),
        if (big != null) ...[
          Text(l10n.resultYoure, style: const TextStyle(fontSize: 15)),
          Text(big(t), style: displayStyle(56, color: c.ink)),
        ],
      ],
    );
    final cleared = outcome?.cleared ?? const [];
    final before = outcome?.monthsBefore;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.close,
            onPressed: () => context.go(Routes.home),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          // Counting starts once there is something to count.
          if (summary == null)
            headline(0)
          else if (MediaQuery.disableAnimationsOf(context))
            headline(1)
          else
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => headline(t),
            ),
          Text(small, style: displayStyle(26, color: c.ink)),
          if (before != null && monthsNow != null && before != monthsNow) ...[
            const SizedBox(height: 12),
            HiVisBlock(
              child: Text(
                l10n.resultDateMoved(month(before), month(monthsNow)),
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
          if (summary?.chart case final chart?) ...[
            const SizedBox(height: 12),
            ProgressChartCard(
              chart: chart,
              debtFree: DateTime(now.year, now.month + (monthsNow ?? 0)),
            ),
          ],
          for (final w
              in outcome?.wentUp ?? const <({String name, Money up})>[]) ...[
            const SizedBox(height: 12),
            OutlinedCard(
              child: Text(l10n.resultWentUp(w.name, formatMoney(w.up, locale))),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => context.go(
              cleared.isEmpty
                  ? Routes.home
                  : Routes.cleared(cleared.first.debtId),
            ),
            child: Text(
              cleared.isEmpty
                  ? l10n.resultDone
                  : l10n.resultContinueCleared(cleared.length),
            ),
          ),
        ],
      ),
    );
  }
}

/// [amount] scaled by [t] (0–1), in whole minor units.
Money _part(Money amount, double t) =>
    Money((amount.minor * t).round(), amount.currency);
