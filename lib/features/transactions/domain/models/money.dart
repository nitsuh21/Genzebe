class Money {
  const Money({
    required this.minorUnits,
    this.currency = 'ETB',
  });

  final int minorUnits;
  final String currency;

  double get majorUnits => minorUnits / 100.0;

  Money operator +(Money other) {
    _assertCurrency(other);
    return Money(minorUnits: minorUnits + other.minorUnits, currency: currency);
  }

  Money operator -(Money other) {
    _assertCurrency(other);
    return Money(minorUnits: minorUnits - other.minorUnits, currency: currency);
  }

  void _assertCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError('Currency mismatch: $currency != ${other.currency}');
    }
  }
}
