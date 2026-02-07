import 'dart:async';

import 'secure_session.dart';

enum PanicReason {
  userPressed,
  tooManyAttempts,
  appBackgrounded,
  tamperDetected,
  timeout,
  unknown,
}

/// V4: panic mode = wipe RAM keys + blocco operazioni + notifica UI.
class PanicController {
  PanicController._();
  static final PanicController I = PanicController._();

  final StreamController<PanicReason> _panicCtrl =
      StreamController<PanicReason>.broadcast();

  Stream<PanicReason> get panic$ => _panicCtrl.stream;

  bool _inPanic = false;
  bool get inPanic => _inPanic;

  void trigger(PanicReason reason) {
    if (_inPanic) return;
    _inPanic = true;

    // 1) wipe immediato delle chiavi in RAM
    SecureSession.I.wipeKeys();

    // 2) notifica listener (UI, navigator, ecc.)
    _panicCtrl.add(reason);
  }

  /// Chiamare SOLO dopo re-auth e re-derivation della key.
  void clearAfterReauth() {
    _inPanic = false;
  }

  void dispose() {
    _panicCtrl.close();
  }
}
