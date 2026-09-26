import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/widgets/rate_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';

enum ParameterField {
  consolidationApr,
  consolidationTerm,
  consolidationFee,
  promoMonths,
  transferFee,
  revertApr,
  creditLimit,
}

/// Text controllers for every strategy parameter. Settings and the scenario
/// editor both show these fields.
class ParameterControllers {
  ParameterControllers(StrategyParameters p, {required String locale})
    : _controllers = {
        ParameterField.consolidationApr: RateController(
          aprBps: p.consolidationAprBps,
          locale: locale,
        ),
        ParameterField.consolidationTerm: TextEditingController(
          text: '${p.consolidationTermMonths}',
        ),
        ParameterField.consolidationFee: TextEditingController(
          text: formatPercentInput(p.consolidationFeeBps, locale),
        ),
        ParameterField.promoMonths: TextEditingController(
          text: '${p.promoMonths}',
        ),
        ParameterField.transferFee: TextEditingController(
          text: formatPercentInput(p.transferFeeBps, locale),
        ),
        ParameterField.revertApr: RateController(
          aprBps: p.revertAprBps,
          locale: locale,
        ),
        ParameterField.creditLimit: TextEditingController(
          text: switch (p.transferCreditLimit) {
            final limit? => formatAmountInput(limit, locale),
            null => '',
          },
        ),
      };

  final Map<ParameterField, TextEditingController> _controllers;

  TextEditingController operator [](ParameterField field) =>
      _controllers[field]!;

  /// A rate field's controller.
  RateController rate(ParameterField field) =>
      _controllers[field]! as RateController;

  /// The typed values. Call only after every field's validator passed.
  StrategyParameters parse({
    required String locale,
    required String currencyCode,
  }) {
    String text(ParameterField f) => _controllers[f]!.text;
    final limit = text(ParameterField.creditLimit).trim();
    return StrategyParameters(
      consolidationAprBps: rate(ParameterField.consolidationApr)
          .aprBps(locale)!,
      consolidationTermMonths: parseWholeNumber(
        text(ParameterField.consolidationTerm),
      )!,
      consolidationFeeBps: parsePercentBps(
        text(ParameterField.consolidationFee),
        locale,
      )!,
      promoMonths: parseWholeNumber(text(ParameterField.promoMonths))!,
      transferFeeBps: parsePercentBps(
        text(ParameterField.transferFee),
        locale,
      )!,
      revertAprBps: rate(ParameterField.revertApr).aprBps(locale)!,
      transferCreditLimit: limit.isEmpty
          ? null
          : Money(
              parseAmountMinor(
                limit,
                currencyCode: currencyCode,
                locale: locale,
              )!,
              currencyCode,
            ),
    );
  }

  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
  }
}

/// The strategy parameter fields under their headings. [errors] are shown
/// as forced errors; [onEdited] lets the caller clear a field's error when
/// it changes (never at the start of a save).
class ParameterFields extends ConsumerWidget {
  const ParameterFields({
    required this.controllers,
    required this.errors,
    required this.onEdited,
    required this.currencyCode,
    super.key,
  });

  final ParameterControllers controllers;
  final Map<ParameterField, String> errors;
  final ValueChanged<ParameterField> onEdited;
  final String currencyCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final percentError = l10n.errorInvalidPercent(
      formatPercentInput(1990, locale),
    );
    String? percent(String v) =>
        parsePercentBps(v, locale) == null ? percentError : null;
    String? whole(String v) =>
        parseWholeNumber(v) == null ? l10n.errorWholeNumber : null;
    String? optionalAmount(String v) =>
        v.trim().isEmpty ||
            parseAmountMinor(v, currencyCode: currencyCode, locale: locale) !=
                null
        ? null
        : l10n.errorInvalidAmount(
            formatAmountInput(Money(500000, currencyCode), locale),
          );

    Widget field(
      ParameterField f,
      String label,
      String? Function(String) validate, {
      String? helper,
      TextInputType keyboard = const TextInputType.numberWithOptions(
        decimal: true,
      ),
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey(f),
        controller: controllers[f],
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
        validator: (v) => validate(v ?? ''),
        forceErrorText: errors[f],
        onChanged: (_) => onEdited(f),
      ),
    );

    Widget rate(ParameterField f, String aprLabel, String monthlyLabel) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RateField(
            controller: controllers.rate(f),
            fieldKey: ValueKey(f),
            aprLabel: aprLabel,
            monthlyLabel: monthlyLabel,
            forceErrorText: errors[f],
            onChanged: (_) => onEdited(f),
          ),
        );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(l10n.settingsConsolidation),
        rate(
          ParameterField.consolidationApr,
          l10n.settingsConsolidationApr,
          l10n.settingsConsolidationAprMonthly,
        ),
        field(
          ParameterField.consolidationTerm,
          l10n.settingsConsolidationTerm,
          whole,
          keyboard: TextInputType.number,
        ),
        field(
          ParameterField.consolidationFee,
          l10n.settingsConsolidationFee,
          percent,
        ),
        heading(l10n.settingsTransfer),
        field(
          ParameterField.promoMonths,
          l10n.settingsPromoMonths,
          whole,
          keyboard: TextInputType.number,
        ),
        field(ParameterField.transferFee, l10n.settingsTransferFee, percent),
        rate(
          ParameterField.revertApr,
          l10n.settingsRevertApr,
          l10n.settingsRevertAprMonthly,
        ),
        field(
          ParameterField.creditLimit,
          l10n.settingsCreditLimit,
          optionalAmount,
          helper: l10n.settingsCreditLimitHint,
        ),
      ],
    );
  }
}

/// Messages for rejected parameters, keyed by the field that shows each.
Map<ParameterField, String> parameterErrorMessages(
  AppLocalizations l10n,
  Set<StrategyParametersValidationError> errors,
  String locale, {
  ParameterControllers? controllers,
}) {
  final messages = <ParameterField, String>{};
  // A rate over 100% APR, worded in the unit it was typed in.
  String rateRange(ParameterField f) => rateRangeMessage(
    l10n,
    controllers?.rate(f).unit ?? RateUnit.year,
    locale,
  );
  for (final e in errors) {
    final (field, message) = switch (e) {
      StrategyParametersValidationError.consolidationAprOutOfRange => (
        ParameterField.consolidationApr,
        rateRange(ParameterField.consolidationApr),
      ),
      StrategyParametersValidationError.consolidationTermOutOfRange => (
        ParameterField.consolidationTerm,
        l10n.errorConsolidationTermRange(
          kMinConsolidationTermMonths,
          kMaxConsolidationTermMonths,
        ),
      ),
      StrategyParametersValidationError.consolidationFeeOutOfRange => (
        ParameterField.consolidationFee,
        l10n.errorConsolidationFeeRange(
          formatPercent(kMaxConsolidationFeeBps, locale),
        ),
      ),
      StrategyParametersValidationError.transferFeeOutOfRange => (
        ParameterField.transferFee,
        l10n.errorRateRange,
      ),
      StrategyParametersValidationError.promoMonthsOutOfRange => (
        ParameterField.promoMonths,
        l10n.errorPromoMonthsRange(kMaxPromoMonths),
      ),
      StrategyParametersValidationError.revertAprOutOfRange => (
        ParameterField.revertApr,
        rateRange(ParameterField.revertApr),
      ),
      StrategyParametersValidationError.creditLimitNotPositive => (
        ParameterField.creditLimit,
        l10n.errorCreditLimitNotPositive,
      ),
      StrategyParametersValidationError.creditLimitTooLarge => (
        ParameterField.creditLimit,
        l10n.errorTooLarge,
      ),
    };
    messages[field] = message;
  }
  return messages;
}
