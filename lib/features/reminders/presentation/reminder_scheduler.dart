import 'dart:async';

import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/notifications.dart';
import 'package:debt_destroyer/features/analysis/domain/plan_series.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
import 'package:debt_destroyer/features/reminders/domain/reminder_schedule.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/presentation/current_plans.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reminder_scheduler.g.dart';

const _nudgeId = 10;

/// The notifications wanted now (spec §7): the next three pay days (the
/// first listing this month's payments) and the check-in nudge. None unless
/// the followed plan clears the debts.
List<Reminder> wantedReminders({
  required AppSettings settings,
  required HomePlan home,
  required ProgressHistory history,
  required DateTime now,
  required AppLocalizations l10n,
  required String locale,
}) {
  if (home is! HomeFollowing) return const [];
  final reminders = <Reminder>[];
  if (settings.payDayReminder) {
    final payments = firstMonthPayments(
      home.result.plan,
      (d) => planDebtName(l10n, d),
    );
    final total = payments.fold(
      Money.zero(settings.currencyCode),
      (s, p) => s + p.amount,
    );
    final list = [
      for (final p in payments)
        '${p.debt.name} ${formatMoney(p.amount, locale)}',
    ].join(' · ');
    // No more pay days than the plan has months left; only the first knows
    // exactly what to pay.
    final count = home.result.plan.monthsToClear.clamp(0, 3);
    for (final (i, at) in nextPayDays(
      now,
      settings.payDay,
      count: count,
    ).indexed) {
      reminders.add((
        id: i + 1,
        at: at,
        title: i == 0
            ? l10n.reminderPayDayTitle(formatMoney(total, locale))
            : l10n.reminderPayDayGenericTitle,
        body: i == 0 ? list : l10n.reminderPayDayGeneric,
      ));
    }
  }
  final nudge = nudgeAt(
    history.lastCheckIn?.at,
    settings.checkInNudgeMonths,
    now,
  );
  if (nudge != null) {
    reminders.add((
      id: _nudgeId,
      at: nudge,
      title: l10n.reminderNudgeTitle,
      body: l10n.reminderNudgeBody(settings.checkInNudgeMonths),
    ));
  }
  return reminders;
}

/// Sets the notifications service up once, routing taps to Check in.
@Riverpod(keepAlive: true)
Future<void> notificationsReady(Ref ref) async {
  await ref
      .watch(notificationsServiceProvider)
      .initialize(
        onTap: (payload) => openReminder(ref.read(routerProvider), payload),
      );
}

/// A reminder's tap: open Check in. The router's onboarding redirect still
/// applies.
void openReminder(GoRouter router, String? payload) {
  if (payload == kCheckInPayload) router.go(Routes.checkIn);
}

/// If a reminder launched the app, open what it points to.
Future<void> openLaunchReminder(ProviderContainer container) async {
  await container.read(notificationsReadyProvider.future);
  final payload = await container
      .read(notificationsServiceProvider)
      .launchPayload();
  openReminder(container.read(routerProvider), payload);
}

/// Keeps the scheduled notifications in step with the plan, settings and
/// history, for as long as the app runs. Replaces them only when what is
/// wanted changes.
@Riverpod(keepAlive: true)
class ReminderScheduler extends _$ReminderScheduler {
  List<Reminder>? _sent;
  var _busy = false;
  var _again = false;

  @override
  void build() {
    void check(Object? _, Object? _) => _check();
    ref
      ..listen(homePlanProvider, check)
      ..listen(settingsControllerProvider, check)
      ..listen(progressHistoryProvider, check);
    unawaited(Future.microtask(_check));
  }

  Future<void> _check() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _schedule();
      } while (_again);
    } on Object {
      // Tried again on the next change; reminders never break the app.
    } finally {
      _busy = false;
    }
  }

  Future<void> _schedule() async {
    final settings = ref.read(settingsControllerProvider).value;
    if (settings == null) return;
    final home = await ref.read(homePlanProvider.future);
    final history = await ref
        .read(progressRepositoryProvider)
        .load(settings.currencyCode);
    final wanted = wantedReminders(
      settings: settings,
      home: home,
      history: history,
      now: ref.read(clockProvider)(),
      l10n: lookupAppLocalizations(const Locale('en')),
      locale: ref.read(formatLocaleProvider),
    );
    if (_sent != null && listEquals(_sent, wanted)) return;
    await ref.read(notificationsReadyProvider.future);
    await ref.read(notificationsServiceProvider).replaceAll(wanted);
    _sent = wanted;
  }
}
