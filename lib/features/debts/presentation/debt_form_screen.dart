import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/core/widgets/rate_field.dart';
import 'package:debt_destroyer/features/debts/domain/loan_helper.dart';
import 'package:debt_destroyer/features/debts/domain/promo_dates.dart';
import 'package:debt_destroyer/features/debts/presentation/debt_type_tiles.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
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

enum _Field {
  name,
  balance,
  apr,
  minPercent,
  minFloor,
  promoApr,
  offerFee,
  offerPromoApr,
  offerPromoMonths,
  offerCredit,
}

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
  late bool _hasOffer;
  late bool _hasOfferPromo;
  Map<_Field, String> _errors = const {};
  bool _saving = false;

  /// The loan helper's Last payment (month 1–12, and year); an input only,
  /// never saved.
  int? _lastMonth;
  int? _lastYear;

  /// Why the loan helper couldn't work it out, and the figure it's about.
  /// Advice shown under that field, never a form error: it can't block
  /// Save, and editing any of the loan's figures clears it.
  ({LoanFigure figure, String message})? _helperMessage;

  /// The figure the loan helper last filled in, until any of the four is
  /// edited.
  LoanFigure? _workedOut;

  static const Set<_Field> _loanFields = {
    _Field.balance,
    _Field.apr,
    _Field.minFloor,
  };

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
    final offer = d?.transferOffer;
    String money(Money m) => formatAmountInput(m, locale);
    String percent(int bps) => formatPercentInput(bps, locale);
    _controllers = {
      _Field.name: TextEditingController(text: d?.name ?? ''),
      _Field.balance: TextEditingController(
        text: d == null ? '' : money(d.balance),
      ),
      _Field.apr: RateController(aprBps: d?.aprBps, locale: locale),
      _Field.minPercent: TextEditingController(
        text: d == null ? '' : percent(d.minPaymentPercentBps),
      ),
      _Field.minFloor: TextEditingController(
        text: d == null ? '' : money(d.minPaymentFloor),
      ),
      _Field.promoApr: RateController(
        aprBps: d?.promo?.aprBps ?? 0,
        locale: locale,
      ),
      _Field.offerFee: TextEditingController(
        text: offer == null ? '' : percent(offer.feeBps),
      ),
      _Field.offerPromoApr: RateController(
        aprBps: offer?.promo?.aprBps ?? 0,
        locale: locale,
      ),
      _Field.offerPromoMonths: TextEditingController(
        text: offer?.promo == null ? '' : '${offer!.promo!.months}',
      ),
      _Field.offerCredit: TextEditingController(
        text: offer == null ? '' : money(offer.availableCredit),
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
    _hasOffer = offer != null;
    _hasOfferPromo = offer?.promo != null;
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
          helperText:
              _helperFor(f) ?? (_workedOutHere(f) ? l10n.loanWorkedOut : null),
          helperStyle: _helperFor(f) == null ? null : _adviceStyle(context),
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        keyboardType: keyboard,
        validator: validator,
        forceErrorText: _errors[f],
        onChanged: (_) => _edited(f),
      ),
    );

    Widget rate(_Field f, String aprLabel, String monthlyLabel) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RateField(
        controller: _controllers[f]! as RateController,
        fieldKey: ValueKey(f),
        aprLabel: aprLabel,
        monthlyLabel: monthlyLabel,
        forceErrorText: _errors[f],
        helperText:
            _helperFor(f) ?? (_workedOutHere(f) ? l10n.loanWorkedOut : null),
        helperStyle: _helperFor(f) == null ? null : _adviceStyle(context),
        onChanged: (_) => _edited(f),
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
            child: DebtTypeTiles(
              selected: _type,
              onChanged: (t) => setState(() {
                _type = t;
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
          rate(_Field.apr, l10n.fieldApr, l10n.fieldAprMonthly),
          if (_fixedPayment) ...[
            field(
              _Field.minFloor,
              l10n.fieldMonthlyPayment,
              keyboard: numberKeyboard,
              validator: (v) => amount(v, required: true),
            ),
            _lastPayment(context, locale, now),
            _helperButton(context),
          ] else ...[
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
            rate(
              _Field.promoApr,
              l10n.fieldPromoApr,
              l10n.fieldPromoAprMonthly,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<int>(
                key: const ValueKey('promoUntil'),
                isExpanded: true,
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
          if (isTransferable(_type)) ...[
            SwitchListTile(
              key: const ValueKey('offer'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.fieldOffer),
              subtitle: Text(l10n.fieldOfferHint),
              value: _hasOffer,
              onChanged: (v) => setState(() => _hasOffer = v),
            ),
            if (_hasOffer) ...[
              field(
                _Field.offerFee,
                l10n.fieldOfferFee,
                keyboard: numberKeyboard,
                validator: (v) => percent(v, required: true),
              ),
              SwitchListTile(
                key: const ValueKey('offerPromo'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.fieldOfferPromo),
                value: _hasOfferPromo,
                onChanged: (v) => setState(() => _hasOfferPromo = v),
              ),
              if (_hasOfferPromo) ...[
                rate(
                  _Field.offerPromoApr,
                  l10n.fieldOfferPromoApr,
                  l10n.fieldOfferPromoAprMonthly,
                ),
                field(
                  _Field.offerPromoMonths,
                  l10n.fieldOfferPromoMonths,
                  keyboard: TextInputType.number,
                  validator: (v) => parseWholeNumber(v ?? '') == null
                      ? l10n.errorWholeNumber
                      : null,
                ),
              ],
              field(
                _Field.offerCredit,
                l10n.fieldOfferCredit,
                keyboard: numberKeyboard,
                validator: (v) => amount(v, required: true),
              ),
            ],
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(l10n.save),
          ),
          if (widget.existing case final debt?) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : () => _markPaidOff(debt.id),
              child: Text(l10n.markPaidOff),
            ),
          ],
        ],
      ),
    );
  }

  /// The helper's advice for [f], if it's about that field.
  String? _helperFor(_Field f) {
    final advice = _helperMessage;
    if (advice == null) return null;
    final here = switch (advice.figure) {
      LoanFigure.balance => f == _Field.balance,
      LoanFigure.rate => f == _Field.apr,
      LoanFigure.payment => f == _Field.minFloor,
      LoanFigure.lastPayment => false,
    };
    return here ? advice.message : null;
  }

  TextStyle _adviceStyle(BuildContext context) =>
      TextStyle(color: Theme.of(context).colorScheme.error);

  bool _workedOutHere(_Field f) => switch (_workedOut) {
    LoanFigure.balance => f == _Field.balance,
    LoanFigure.rate => f == _Field.apr,
    LoanFigure.payment => f == _Field.minFloor,
    _ => false,
  };

  /// A field was typed in: clear its forced error, and the helper's note if
  /// it's one of the loan's figures (which also re-counts the filled ones).
  void _edited(_Field f) {
    final loan = _fixedPayment && _loanFields.contains(f);
    if (!_errors.containsKey(f) && !loan) return;
    setState(() {
      _errors = {..._errors}..remove(f);
      if (loan) {
        _workedOut = null;
        _helperMessage = null;
      }
    });
  }

  bool get _hasLastPayment => _lastMonth != null && _lastYear != null;

  int _filledLoanFigures() => [
    for (final f in _loanFields) _controllers[f]!.text.trim().isNotEmpty,
    _hasLastPayment,
  ].where((filled) => filled).length;

  Widget _lastPayment(BuildContext context, String locale, DateTime now) {
    final l10n = context.l10n;
    void picked(void Function() change) => setState(() {
      change();
      _helperMessage = null;
      _workedOut = null;
    });
    final note = _workedOut == LoanFigure.lastPayment
        ? l10n.loanWorkedOut
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.fieldLastPayment,
          helperText: _helperMessage?.figure == LoanFigure.lastPayment
              ? _helperMessage!.message
              : note,
          helperStyle: _helperMessage?.figure == LoanFigure.lastPayment
              ? _adviceStyle(context)
              : null,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        // Side by side, sharing the width: long month names shorten rather
        // than overflow at large text.
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: DropdownButton<int>(
                key: const ValueKey('lastPaymentMonth'),
                isExpanded: true,
                value: _lastMonth,
                hint: Text(l10n.fieldMonth),
                items: [
                  for (var m = 1; m <= 12; m++)
                    DropdownMenuItem(
                      value: m,
                      child: Text(
                        DateFormat.MMMM(locale).format(DateTime(2000, m)),
                      ),
                    ),
                ],
                onChanged: (m) => picked(() => _lastMonth = m),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: DropdownButton<int>(
                key: const ValueKey('lastPaymentYear'),
                isExpanded: true,
                value: _lastYear,
                hint: Text(l10n.fieldYear),
                items: [
                  for (var y = now.year; y <= now.year + 100; y++)
                    DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged: (y) => picked(() => _lastYear = y),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _helperButton(BuildContext context) {
    final l10n = context.l10n;
    final filled = _filledLoanFigures();
    if (filled == 4) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.loanHelperHint,
            style: TextStyle(fontSize: 13, color: context.colors.ink2),
          ),
          const SizedBox(height: 6),
          OutlinedButton(
            key: const ValueKey('workItOut'),
            onPressed: filled == 3 ? _workItOut : null,
            child: Text(
              filled == 3 ? l10n.loanWorkItOut : l10n.loanFillAnyThree,
            ),
          ),
        ],
      ),
    );
  }

  /// Fills in the one missing loan figure (spec §3.2).
  void _workItOut() {
    final l10n = context.l10n;
    final locale = ref.read(formatLocaleProvider);
    final code = widget.currencyCode;
    final now = ref.read(clockProvider)();
    final example = formatAmountInput(Money(123400, code), locale);
    final rateController = _controllers[_Field.apr]! as RateController;

    // The three filled in must each be valid first.
    final problems = <_Field, String>{};
    Money? money(_Field f) {
      final text = _controllers[f]!.text;
      if (text.trim().isEmpty) return null;
      final minor = parseAmountMinor(text, currencyCode: code, locale: locale);
      if (minor == null) problems[f] = l10n.errorInvalidAmount(example);
      return minor == null ? null : Money(minor, code);
    }

    final balance = money(_Field.balance);
    final payment = money(_Field.minFloor);
    int? aprBps;
    if (rateController.text.trim().isNotEmpty) {
      aprBps = rateController.aprBps(locale);
      if (aprBps == null) {
        problems[_Field.apr] = l10n.errorInvalidRate(
          rateController.unit == RateUnit.month
              ? formatMonthlyRateInput(19000, locale)
              : formatPercentInput(1990, locale),
        );
      }
    }
    if (problems.isNotEmpty) {
      setState(() => _errors = {..._errors, ...problems});
      return;
    }
    final result = workOutLoan(
      now: now,
      balance: balance,
      aprBps: aprBps,
      payment: payment,
      lastPaymentYearMonth: _hasLastPayment
          ? _lastYear! * 100 + _lastMonth!
          : null,
    );
    switch (result) {
      case LoanFilled(:final figure):
        setState(() {
          switch (figure) {
            case LoanFigure.balance:
              _controllers[_Field.balance]!.text = formatAmountInput(
                result.balance!,
                locale,
              );
            case LoanFigure.rate:
              rateController.setAprBps(result.aprBps!, locale);
            case LoanFigure.payment:
              _controllers[_Field.minFloor]!.text = formatAmountInput(
                result.payment!,
                locale,
              );
            case LoanFigure.lastPayment:
              _lastYear = result.lastPaymentYearMonth! ~/ 100;
              _lastMonth = result.lastPaymentYearMonth! % 100;
          }
          _workedOut = figure;
          _helperMessage = null;
          _errors = {..._errors}
            ..remove(_Field.balance)
            ..remove(_Field.apr)
            ..remove(_Field.minFloor);
        });
      case LoanNotPossible(:final figure, :final problem):
        final message = switch (problem) {
          LoanProblem.neverClears => l10n.loanNeverClears,
          LoanProblem.rateTooHigh => l10n.loanRateTooHigh,
          LoanProblem.rateBelowZero => l10n.loanRateBelowZero,
          LoanProblem.outOfRange =>
            figure == LoanFigure.lastPayment &&
                    _hasLastPayment &&
                    monthsUntil(_lastYear! * 100 + _lastMonth!, now) < 1
                ? l10n.loanLastPaymentTooSoon
                : l10n.loanOutOfRange,
        };
        setState(() {
          _workedOut = null;
          _helperMessage = (figure: figure, message: message);
        });
      case null:
        break; // the button only works with exactly three filled in
    }
  }

  /// The same as a check-in with this debt at 0 (spec §4.4).
  Future<void> _markPaidOff(String id) async {
    setState(() => _saving = true);
    final done = await runGuarded(context, () async {
      await ref.read(progressControllerProvider.notifier).markPaidOff(id);
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (done ?? false) context.go(Routes.cleared(id));
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
    int rate(_Field f) =>
        (_controllers[f]! as RateController).aprBps(locale) ?? 0;

    final now = ref.read(clockProvider)();
    final debt = Debt(
      id: widget.existing?.id ?? '',
      name: _controllers[_Field.name]!.text.trim(),
      type: _type,
      balance: Money(amount(_Field.balance), code),
      aprBps: rate(_Field.apr),
      minPaymentPercentBps: _fixedPayment ? 0 : percent(_Field.minPercent),
      minPaymentFloor: Money(amount(_Field.minFloor), code),
      allowsOverpayment: _allowsOverpayment,
      promo: _hasPromo
          ? Promo(
              aprBps: rate(_Field.promoApr),
              months: promoMonthsLeft(_promoUntil, now),
            )
          : null,
      transferOffer: _hasOffer && isTransferable(_type)
          ? TransferOffer(
              feeBps: percent(_Field.offerFee),
              promo: _hasOfferPromo
                  ? Promo(
                      aprBps: rate(_Field.offerPromoApr),
                      months:
                          parseWholeNumber(
                            _controllers[_Field.offerPromoMonths]!.text,
                          ) ??
                          0,
                    )
                  : null,
              availableCredit: Money(amount(_Field.offerCredit), code),
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
    final locale = ref.read(formatLocaleProvider);
    // A rate over 100% APR, worded in the unit it was typed in.
    String rateRange(_Field f) => rateRangeMessage(
      l10n,
      (_controllers[f]! as RateController).unit,
      locale,
    );
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
          byField[_Field.apr] = rateRange(_Field.apr);
        case DebtValidationError.minPaymentPercentOutOfRange:
          byField[_Field.minPercent] = l10n.errorPercentRange;
        case DebtValidationError.minPaymentFloorNegative:
          byField[_Field.minFloor] = l10n.errorFloorNegative;
        case DebtValidationError.minPaymentFloorTooLarge:
          byField[_Field.minFloor] = l10n.errorTooLarge;
        case DebtValidationError.offerFeeOutOfRange:
          byField[_Field.offerFee] = l10n.errorPercentRange;
        case DebtValidationError.offerPromoAprOutOfRange:
          byField[_Field.offerPromoApr] = rateRange(_Field.offerPromoApr);
        case DebtValidationError.offerPromoMonthsOutOfRange:
          byField[_Field.offerPromoMonths] = l10n.errorOfferMonths(
            kMaxPromoMonths,
          );
        case DebtValidationError.offerCreditNotPositive:
          byField[_Field.offerCredit] = l10n.errorOfferCredit;
        case DebtValidationError.offerCreditTooLarge:
          byField[_Field.offerCredit] = l10n.errorTooLarge;
        case DebtValidationError.offerOnNonCard:
        case DebtValidationError.offerCurrencyMismatch:
          break; // not reachable: the form drops offers on non-cards and
        // uses one currency
        case DebtValidationError.floorCurrencyMismatch:
          break; // not reachable from this form: one currency throughout
        case DebtValidationError.promoAprOutOfRange:
          byField[_Field.promoApr] = rateRange(_Field.promoApr);
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
