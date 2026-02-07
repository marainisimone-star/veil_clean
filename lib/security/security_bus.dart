import 'dart:async';

class SecurityBus {
  SecurityBus._();

  static final StreamController<void> _hardLockCtrl =
      StreamController<void>.broadcast();

  static Stream<void> get hardLockStream => _hardLockCtrl.stream;

  static void hardLock() {
    if (!_hardLockCtrl.isClosed) _hardLockCtrl.add(null);
  }
}
