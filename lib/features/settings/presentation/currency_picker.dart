import 'package:debt_destroyer/core/currencies.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CurrencyPicker extends ConsumerWidget {
  const CurrencyPicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(formatLocaleProvider);
    return DropdownButtonFormField<String>(
      key: const ValueKey('currency'),
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: context.l10n.settingsCurrency,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final code in currencyChoices(value))
          DropdownMenuItem(
            value: code,
            child: Text(
              currencyLabel(code, locale),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (code) {
        if (code != null) onChanged(code);
      },
    );
  }
}
