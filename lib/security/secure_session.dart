import 'dart:async';
import 'dart:typed_data';

/// V4: sessione con chiavi SOLO in RAM (Uint8List) e wipe best-effort.
/// Nota: in Dart non esiste garanzia "hard" di wipe (GC/copie), ma questa
/// implementazione evita String e fa zeroize dei buffer mutabili.
class SecureSession {
  SecureSession._();
  static final SecureSession I = SecureSession._();

  Uint8List? _masterKey; // es. 32 bytes
  Uint8List? _dataKey; // es. 32 bytes (derivata)
  bool _isLocked = true;

  final StreamController<bool> _lockedCtrl = StreamController<bool>.broadcast();

  bool get isLocked => _isLocked;
  Stream<bool> get locked$ => _lockedCtrl.stream;

  /// Imposta le chiavi in sessione.
  /// IMPORTANTE: passare SOLO Uint8List, non String/base64.
  void setKeys({required Uint8List masterKey, Uint8List? dataKey}) {
    wipeKeys();

    // Copia interna per controllare lifecycle e wipe.
    _masterKey = Uint8List.fromList(masterKey);
    if (dataKey != null) {
      _dataKey = Uint8List.fromList(dataKey);
    }
    _setLocked(false);
  }

  /// Recupera la masterKey se la sessione è sbloccata.
  Uint8List get masterKeyOrThrow {
    final k = _masterKey;
    if (_isLocked || k == null) {
      throw StateError('SecureSession locked or masterKey missing');
    }
    return k;
  }

  Uint8List? get dataKeyOrNull {
    if (_isLocked) return null;
    return _dataKey;
  }

  void lock() => _setLocked(true);

  void unlockOrThrow() {
    if (_masterKey == null) {
      throw StateError('Cannot unlock without keys');
    }
    _setLocked(false);
  }

  /// Best-effort RAM wipe: azzera i buffer mutabili e rilascia riferimenti.
  void wipeKeys() {
    _zeroize(_masterKey);
    _zeroize(_dataKey);
    _masterKey = null;
    _dataKey = null;
    _setLocked(true);

    // Best-effort: riallinea microtask queue.
    scheduleMicrotask(() {});
  }

  void dispose() {
    wipeKeys();
    _lockedCtrl.close();
  }

  void _setLocked(bool v) {
    if (_isLocked == v) return;
    _isLocked = v;
    _lockedCtrl.add(v);
  }

  static void _zeroize(Uint8List? b) {
    if (b == null) return;
    for (var i = 0; i < b.length; i++) {
      b[i] = 0;
    }
  }
}
