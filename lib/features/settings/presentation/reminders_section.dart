import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/notifications.dart';
import 'package:debt_destroyer/core/widgets/outlined_card.dart';
import 'package:debt_destroyer/features/reminders/domain/reminder_schedule.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pay-day reminder and check-in nudge (spec §4.11). Changes save at once;
/// switching one on asks the phone for permission first.
class RemindersSection extends ConsumerStatefulWidget {
  const RemindersSection({required this.settings, super.key});

  final AppSettings settings;

  @override
  ConsumerState<RemindersSection> createState() => _RemindersSectionState();
}

class _RemindersSectionState extends ConsumerState<RemindersSection> {
  var _denied = false;

  /// Asks for permission; remembers a refusal so it can be explained.
  Future<bool> _allowed() async {
    final granted = await ref
        .read(notificationsServiceProvider)
        .requestPermission();
    if (mounted) setState(() => _denied = !granted);
    return granted;
  }

  Future<void> _setPayDay({required bool on}) async {
    if (on && !await _allowed()) return;
    if (!mounted) return;
    await runGuarded(
      context,
      () => ref
          .read(settingsControllerProvider.notifier)
          .setPayDayReminder(on: on),
    );
  }

  Future<void> _setNudge(int months) async {
    if (months > 0 && widget.settings.checkInNudgeMonths == 0) {
      if (!await _allowed()) return;
    }
    if (!mounted) return;
    await runGuarded(
      context,
      () => ref
          .read(settingsControllerProvider.notifier)
          .setCheckInNudgeMonths(months),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final s = widget.settings;
    return OutlinedCard(
      title: l10n.remindersTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.remindersPayDay),
            subtitle: Text(l10n.remindersPayDayHint),
            value: s.payDayReminder,
            onChanged: (on) => _setPayDay(on: on),
          ),
          const SizedBox(height: 8),
          _Picker(
            key: const ValueKey('payDay'),
            label: l10n.remindersDay,
            value: s.payDay,
            items: {
              for (var day = 1; day <= 28; day++) day: ordinal(day),
              kLastDay: l10n.remindersLastDay,
            },
            onChanged: s.payDayReminder
                ? (day) => runGuarded(
                    context,
                    () => ref
                        .read(settingsControllerProvider.notifier)
                        .setPayDayReminder(on: true, day: day),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          _Picker(
            key: const ValueKey('nudge'),
            label: l10n.remindersNudge,
            value: s.checkInNudgeMonths,
            items: {
              0: l10n.remindersNudgeOff,
              for (final months in [1, 2, 3])
                months: l10n.remindersNudgeEvery(months),
            },
            onChanged: _setNudge,
          ),
          if (_denied) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.remindersDenied,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            l10n.remindersLocalOnly,
            style: TextStyle(fontSize: 12, color: c.ink2),
          ),
        ],
      ),
    );
  }
}

/// A dropdown that always shows the saved [value]: a choice that isn't
/// saved (a refused permission, a failed write) springs back.
class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final String label;
  final int value;
  final Map<int, String> items;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(labelText: label, enabled: onChanged != null),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: value,
        isExpanded: true,
        isDense: true,
        items: [
          for (final MapEntry(key: v, value: text) in items.entries)
            DropdownMenuItem(value: v, child: Text(text)),
        ],
        onChanged: onChanged == null ? null : (v) => onChanged!(v ?? value),
      ),
    ),
  );
}
