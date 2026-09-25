import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/debts/domain/promo_dates.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Adds a debt, or edits the one with [debtId].
class DebtFormScreen extends ConsumerWidget {
  const DebtFormScreen({this.debtId, super.key});

  final String? debtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final currency = ref.watch(
      settingsControllerProvider.select((s) => s.value?.currencyCode),
    );
    final settingsFailed = ref.watch(
      settingsControllerProvider.select((s) => s.hasError),
    );
    final debts = ref.watch(debtsProvider);
    final title = Text(debtId == null ? l10n.newDebtTitle : l10n.editDebtTitle);
    if (settingsFailed || debts.hasError) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: ErrorRetryView(
          onRetry: () => ref
            ..invalidate(settingsControllerProvider)
            ..invalidate(debtsProvider),
        ),
      );
    }
    if (currency == null || !debts.hasValue) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final existing = debtId == null
        ? null
        : debts.requireValue.where((d) => d.id == debtId).firstOrNull;
    if (debtId != null && existing == null) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: Center(child: Text(l10n.errorGeneric)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: title),
      body: _DebtForm(
        key: ValueKey(debtId),
        existing: existing,
        currencyCode: currency,
      ),
    );
  }
}

enum _Field { name, balance, apr, minPercent, minFloor, promoApr }

class _DebtForm extends ConsumerStatefulWidget {
  const _DebtForm({
    required this.existing,
    required this.currencyCode,
    super.key,
  });

  final Debt? existing;
  final String currencyCode;

  @override
  ConsumerState<_DebtForm> createState() => _DebtFormState();
}

class _DebtFormState extends ConsumerState<_DebtForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<_Field, TextEditingController> _controllers;
  late DebtType _type;
  late bool _allowsOverpayment;
  late bool _hasPromo;
  late int _promoUntil;
  Map<_Field, String> _errors = const {};
  bool _saving = false;

  /// Loans are entered as one fixed monthly payment, unless an existing
  /// loan was saved with a percentage minimum.
  bool get _fixedPayment =>
      _type == DebtType.loan &&
      (widget.existing?.minPaymentPercentBps ?? 0) == 0;

  @override
  void initState() {
    super.initState();
    final locale = ref.read(formatLocaleProvider);
    final d = widget.existing;
    String money(Money m) => formatAmountInput(m, locale);
    String percent(int bps) => formatPercentInput(bps, locale);
    _controllers = {
      _Field.name: TextEditingController(text: d?.name ?? ''),
      _Field.balance: TextEditingController(
        text: d == null ? '' : money(d.balance),
      ),
      _Field.apr: TextEditingController(
        text: d == null ? '' : percent(d.aprBps),
      ),
      _Field.minPercent: TextEditingController(
        text: d == null ? '' : percent(d.minPaymentPercentBps),
      ),
      _Field.minFloor: TextEditingController(
        text: d == null ? '' : money(d.minPaymentFloor),
      ),
      _Field.promoApr: TextEditingController(
        text: percent(d?.promo?.aprBps ?? 0),
      ),
    };
    _type = d?.type ?? DebtType.creditCard;
    _allowsOverpayment =
        d?.allowsOverpayment ?? defaultAllowsOverpayment(_type);
    _hasPromo = d?.promo != null;
    _promoUntil = promoEndYearMonth(
      d?.promo?.months ?? 12,
      ref.read(clockProvider)(),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final example = formatAmountInput(
      Money(123456 ~/ 100 * 100, widget.currencyCode),
      locale,
    );
    final now = ref.watch(clockProvider)();
    final promoEnds = [
      for (var m = 1; m <= kMaxPromoMonths; m++) promoEndYearMonth(m, now),
    ];

    String? amount(String? text, {required bool required}) {
      final value = text ?? '';
      if (!required && value.trim().isEmpty) return null;
      return parseAmountMinor(
                value,
                currencyCode: widget.currencyCode,
                locale: locale,
              ) ==
              null
          ? l10n.errorInvalidAmount(example)
          : null;
    }

    String? percent(String? text, {required bool required}) {
      final value = text ?? '';
      if (!required && value.trim().isEmpty) return null;
      return parsePercentBps(value, locale) == null
          ? l10n.errorInvalidPercent(formatPercentInput(1990, locale))
          : null;
    }

    Widget field(
      _Field f,
      String label, {
      String? Function(String?)? validator,
      TextInputType? keyboard,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey(f),
        controller: _controllers[f],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: keyboard,
        validator: validator,
        forceErrorText: _errors[f],
        onChanged: (_) {
          if (_errors.containsKey(f)) {
            setState(() => _errors = {..._errors}..remove(f));
          }
        },
      ),
    );

    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          field(_Field.name, l10n.fieldName),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<DebtType>(
              key: const ValueKey('type'),
              initialValue: _type,
              decoration: InputDecoration(
                labelText: l10n.fieldType,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final t in DebtType.values)
                  DropdownMenuItem(
                    value: t,
                    child: Text(debtTypeLabel(l10n, t)),
                  ),
              ],
              onChanged: (t) => setState(() {
                _type = t!;
                // Suggest the usual choice for new debts only, never
                // overriding a saved one.
                if (widget.existing == null) {
                  _allowsOverpayment = defaultAllowsOverpayment(_type);
                }
              }),
            ),
          ),
          field(
            _Field.balance,
            l10n.fieldBalance,
            keyboard: numberKeyboard,
            validator: (v) => amount(v, required: true),
          ),
          field(
            _Field.apr,
            l10n.fieldApr,
            keyboard: numberKeyboard,
            validator: (v) => percent(v, required: true),
          ),
          if (_fixedPayment)
            field(
              _Field.minFloor,
              l10n.fieldMonthlyPayment,
              keyboard: numberKeyboard,
              validator: (v) => amount(v, required: true),
            )
          else ...[
            field(
              _Field.minPercent,
              l10n.fieldMinPercent,
              keyboard: numberKeyboard,
              validator: (v) => percent(v, required: false),
            ),
            field(
              _Field.minFloor,
              l10n.fieldMinFloor,
              keyboard: numberKeyboard,
              validator: (v) => amount(v, required: false),
            ),
          ],
          SwitchListTile(
            key: const ValueKey('minimumsOnly'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.fieldMinimumsOnly),
            subtitle: Text(
              defaultAllowsOverpayment(_type)
                  ? l10n.fieldMinimumsOnlyHint
                  : l10n.fieldMinimumsOnlyNote,
            ),
            value: !_allowsOverpayment,
            onChanged: (v) => setState(() => _allowsOverpayment = !v),
          ),
          SwitchListTile(
            key: const ValueKey('promo'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.fieldPromo),
            subtitle: Text(l10n.fieldPromoHint),
            value: _hasPromo,
            onChanged: (v) => setState(() => _hasPromo = v),
          ),
          if (_hasPromo) ...[
            field(
              _Field.promoApr,
              l10n.fieldPromoApr,
              keyboard: numberKeyboard,
              validator: (v) => percent(v, required: true),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<int>(
                key: const ValueKey('promoUntil'),
                initialValue: _promoUntil,
                decoration: InputDecoration(
                  labelText: l10n.fieldPromoUntil,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final end in promoEnds)
                    DropdownMenuItem(
                      value: end,
                      child: Text(
                        DateFormat.yMMMM(locale)
                            .format(DateTime(end ~/ 100, end % 100)),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _promoUntil = v!),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    // A field rejected last time keeps its message until it is edited.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final locale = ref.read(formatLocaleProvider);
    final code = widget.currencyCode;
    int amount(_Field f) =>
        parseAmountMinor(
          _controllers[f]!.text,
          currencyCode: code,
          locale: locale,
        ) ??
        0;
    int percent(_Field f) =>
        parsePercentBps(_controllers[f]!.text, locale) ?? 0;

    final now = ref.read(clockProvider)();
    final debt = Debt(
      id: widget.existing?.id ?? '',
      name: _controllers[_Field.name]!.text.trim(),
      type: _type,
      balance: Money(amount(_Field.balance), code),
      aprBps: percent(_Field.apr),
      minPaymentPercentBps: _fixedPayment ? 0 : percent(_Field.minPercent),
      minPaymentFloor: Money(amount(_Field.minFloor), code),
      allowsOverpayment: _allowsOverpayment,
      promo: _hasPromo
          ? Promo(
              aprBps: percent(_Field.promoApr),
              months: promoMonthsLeft(_promoUntil, now),
            )
          : null,
    );

    setState(() => _saving = true);
    final actions = ref.read(debtActionsProvider.notifier);
    final outcome = await runGuarded(
      context,
      () => widget.existing == null ? actions.add(debt) : actions.update(debt),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (outcome) {
      case DebtSaved():
        context.pop();
      case DebtRejected(:final errors, :final listErrors):
        _showErrors(errors, listErrors);
      case null:
        break; // runGuarded already told the user
    }
  }

  void _showErrors(
    Set<DebtValidationError> errors,
    Set<DebtListValidationError> listErrors,
  ) {
    final l10n = context.l10n;
    final byField = <_Field, String>{};
    for (final e in errors) {
      switch (e) {
        case DebtValidationError.nameEmpty:
          byField[_Field.name] = l10n.errorNameEmpty;
        case DebtValidationError.balanceNotPositive:
          byField[_Field.balance] = l10n.errorBalanceNotPositive;
        case DebtValidationError.balanceTooLarge:
          byField[_Field.balance] = l10n.errorTooLarge;
        case DebtValidationError.aprOutOfRange:
          byField[_Field.apr] = l10n.errorRateRange;
        case DebtValidationError.minPaymentPercentOutOfRange:
          byField[_Field.minPercent] = l10n.errorPercentRange;
        case DebtValidationError.minPaymentFloorNegative:
          byField[_Field.minFloor] = l10n.errorFloorNegative;
        case DebtValidationError.minPaymentFloorTooLarge:
          byField[_Field.minFloor] = l10n.errorTooLarge;
        case DebtValidationError.offerOnNonCard ||
            DebtValidationError.offerFeeOutOfRange ||
            DebtValidationError.offerPromoAprOutOfRange ||
            DebtValidationError.offerPromoMonthsOutOfRange ||
            DebtValidationError.offerCreditNotPositive ||
            DebtValidationError.offerCreditTooLarge ||
            DebtValidationError.offerCurrencyMismatch:
          break; // the form has no offer fields until Task 5
        case DebtValidationError.floorCurrencyMismatch:
          break; // not reachable from this form: one currency throughout
        case DebtValidationError.promoAprOutOfRange:
          byField[_Field.promoApr] = l10n.errorRateRange;
        case DebtValidationError.promoMonthsOutOfRange:
          break; // the month list only offers 1 to kMaxPromoMonths months
      }
    }
    setState(() => _errors = byField);
    if (listErrors.contains(DebtListValidationError.tooMany)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorTooManyDebts(kMaxDebts))),
      );
    }
  }
}
