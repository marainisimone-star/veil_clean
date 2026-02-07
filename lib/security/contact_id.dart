class ContactId {
  /// Normalizza un telefono in una forma stabile (solo cifre).
  /// Esempi:
  ///  "+1 (202) 555-0123" -> "12025550123"
  ///  "202-555-0123"      -> "2025550123"
  static String normalizePhone(String input) {
    final digitsOnly = input.replaceAll(RegExp(r'[^0-9]'), '');
    return digitsOnly;
  }

  /// Key stabile per salvataggio policy contatto.
  /// Per ora usiamo il telefono normalizzato.
  /// In futuro potremo usare un contactId nativo del device.
  static String keyFromPhone(String phone) {
    final p = normalizePhone(phone);
    return 'p:$p';
  }
}
