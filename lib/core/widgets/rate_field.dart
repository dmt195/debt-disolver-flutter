import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Which way a rate is typed: as an APR, or as a rate a month.
enum RateUnit { year, month }

/// The text of a rate field, and the unit it's typed in (spec §3.1). The
/// rate is always read as APR basis points, whichever unit is showing.
class RateController extends TextEditingController {
  RateController({required String locale, int? aprBps})
    : super(text: aprBps == null ? '' : formatPercentInput(aprBps, locale));

  RateUnit _unit = RateUnit.year;

  /// What to show if the unit is switched straight back: the unit and text
  /// before the last switch, and the text the switch left.
  ({RateUnit unit, String text, String left})? _restore;

  RateUnit get unit => _unit;

  /// The typed rate as APR basis points; null if the text isn't a rate.
  int? aprBps(String locale) => switch (_unit) {
    RateUnit.year => parsePercentBps(text, locale),
    RateUnit.month => switch (parseMonthlyRatePpm(text, locale)) {
      final ppm? => aprBpsFromMonthlyPpm(ppm),
      null => null,
    },
  };

  /// The typed rate a month, in parts per million; null if the text isn't a
  /// rate.
  int? monthlyPpm(String locale) => switch (_unit) {
    RateUnit.year => switch (parsePercentBps(text, locale)) {
      final bps? => monthlyRatePpm(bps),
      null => null,
    },
    RateUnit.month => parseMonthlyRatePpm(text, locale),
  };

  /// Shows the rate in [to], converting the typed number. Switching back
  /// before any edit restores the exact earlier text, so rates never drift.
  void switchTo(RateUnit to, String locale) {
    if (to == _unit) return;
    final from = (unit: _unit, text: text);
    final restore = _restore;
    final String next;
    if (restore != null && restore.unit == to && restore.left == text) {
      next = restore.text;
    } else {
      next = switch (to) {
        RateUnit.month => switch (parsePercentBps(text, locale)) {
          final bps? => formatMonthlyRateInput(monthlyRatePpm(bps), locale),
          null => text,
        },
        RateUnit.year => switch (parseMonthlyRatePpm(text, locale)) {
          final ppm? => formatPercentInput(aprBpsFromMonthlyPpm(ppm), locale),
          null => text,
        },
      };
    }
    _unit = to;
    _restore = (unit: from.unit, text: from.text, left: next);
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  /// Replaces the text with [aprBps], in the unit showing.
  void setAprBps(int aprBps, String locale) {
    _restore = null;
    text = switch (_unit) {
      RateUnit.year => formatPercentInput(aprBps, locale),
      RateUnit.month => formatMonthlyRateInput(monthlyRatePpm(aprBps), locale),
    };
  }
}

/// A rate input with a "a year / a month" switch and the rate in the other
/// unit underneath. Validates in the unit showing.
class RateField extends ConsumerWidget {
  const RateField({
    required this.controller,
    required this.aprLabel,
    required this.monthlyLabel,
    required this.fieldKey,
    this.required = true,
    this.forceErrorText,
    this.helperText,
    this.onChanged,
    super.key,
  });

  final RateController controller;
  final String aprLabel;
  final String monthlyLabel;

  /// The text field's key; the switch is keyed `'$fieldKey-unit'`.
  final ValueKey<Object> fieldKey;
  final bool required;
  final String? forceErrorText;

  /// Shown under the field, e.g. "Worked out".
  final String? helperText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final locale = ref.watch(formatLocaleProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final monthly = controller.unit == RateUnit.month;
        final ppm = controller.monthlyPpm(locale);
        final bps = controller.aprBps(locale);
        final converted = ppm == null || bps == null
            ? ''
            : monthly
            ? l10n.rateAsApr(formatPercent(bps, locale))
            : l10n.rateAsMonthly(formatMonthlyRate(ppm, locale));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: fieldKey,
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: monthly ? monthlyLabel : aprLabel,
                helperText: helperText,
                border: const OutlineInputBorder(),
              ),
              validator: (text) => _validate(l10n, text ?? '', locale),
              forceErrorText: forceErrorText,
              onChanged: onChanged,
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(converted, style: TextStyle(fontSize: 13, color: c.ink2)),
                SegmentedButton<RateUnit>(
                  key: ValueKey('${fieldKey.value}-unit'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  segments: [
                    ButtonSegment(
                      value: RateUnit.year,
                      label: Text(l10n.rateUnitYear),
                    ),
                    ButtonSegment(
                      value: RateUnit.month,
                      label: Text(l10n.rateUnitMonth),
                    ),
                  ],
                  selected: {controller.unit},
                  onSelectionChanged: (s) =>
                      controller.switchTo(s.single, locale),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String? _validate(AppLocalizations l10n, String text, String locale) {
    final monthly = controller.unit == RateUnit.month;
    if (!required && text.trim().isEmpty) return null;
    if (controller.aprBps(locale) == null) {
      return l10n.errorInvalidRate(
        monthly
            ? formatMonthlyRateInput(19000, locale)
            : formatPercentInput(1990, locale),
      );
    }
    // A rate over 100% APR is left to the save, which reports it with every
    // other problem at once (worded by [rateRangeMessage]).
    return null;
  }
}

/// The message for a rate over 100% APR, worded in the unit it was typed in.
String rateRangeMessage(AppLocalizations l10n, RateUnit unit, String locale) =>
    unit == RateUnit.month
    ? l10n.errorRateRangeMonthly(
        formatMonthlyRate(monthlyRatePpm(10000), locale),
      )
    : l10n.errorRateRange;
