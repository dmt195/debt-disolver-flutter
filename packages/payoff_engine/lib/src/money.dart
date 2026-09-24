import 'package:meta/meta.dart';

/// An amount of money in integer minor units (e.g. pence) of [currency].
@immutable
final class Money implements Comparable<Money> {
  const Money(this.minor, this.currency);

  const Money.zero(this.currency) : minor = 0;

  final int minor;

  /// ISO 4217 currency code, e.g. `GBP`.
  final String currency;

  bool get isZero => minor == 0;
  bool get isPositive => minor > 0;
  bool get isNegative => minor < 0;

  Money operator +(Money other) => Money(minor + _check(other).minor, currency);

  Money operator -(Money other) => Money(minor - _check(other).minor, currency);

  bool operator <(Money other) => minor < _check(other).minor;
  bool operator >(Money other) => minor > _check(other).minor;
  bool operator <=(Money other) => minor <= _check(other).minor;
  bool operator >=(Money other) => minor >= _check(other).minor;

  Money _check(Money other) {
    if (other.currency != currency) {
      throw ArgumentError('Currency mismatch: $currency vs ${other.currency}');
    }
    return other;
  }

  @override
  int compareTo(Money other) => minor.compareTo(_check(other).minor);

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => 'Money($minor $currency)';
}
