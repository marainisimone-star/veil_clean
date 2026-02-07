import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'secure_gate.dart';

class WindowBlurLock extends StatefulWidget {
  final Widget child;
  const WindowBlurLock({super.key, required this.child});

  @override
  State<WindowBlurLock> createState() => _WindowBlurLockState();
}

class _WindowBlurLockState extends State<WindowBlurLock> implements WindowListener {
  bool _armed = false;
  bool _cooldown = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(_LifecycleObserver(
      onState: (s) {
        if (!_armed) return;

        // ✅ Ignore lifecycle transitions while OS auth is active
        if (SecureGate.isAuthInProgress) {
          // ignore: avoid_print
          print('LIFECYCLE=$s (ignored: auth/grace)');
          return;
        }

        if (s == AppLifecycleState.inactive ||
            s == AppLifecycleState.paused ||
            s == AppLifecycleState.hidden) {
          _lockNow('lifecycle=$s');
        }
      },
    ));

    windowManager.addListener(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _armed = true;
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void _lockNow(String reason) {
    if (!_armed) return;
    if (SecureGate.isAuthInProgress) return;
    if (_cooldown) return;

    _cooldown = true;

    // ignore: avoid_print
    print('WIN_LOCK: $reason');

    SecureGate.lockSession();

    Timer(const Duration(milliseconds: 350), () {
      _cooldown = false;
    });
  }

  // ============ WindowListener ============
  @override
  void onWindowBlur() => _lockNow('onWindowBlur');

  @override
  void onWindowFocus() {}

  @override
  void onWindowClose() {}

  @override
  void onWindowResized() {}

  @override
  void onWindowMoved() {}

  // Compat / no-op
  @override
  void onWindowResize() {}

  @override
  void onWindowMove() {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowUnmaximize() {}

  @override
  void onWindowMinimize() {}

  @override
  void onWindowRestore() {}

  @override
  void onWindowEnterFullScreen() {}

  @override
  void onWindowLeaveFullScreen() {}

  @override
  void onWindowDocked() {}

  @override
  void onWindowUndocked() {}

  @override
  void onWindowEvent(String eventName) {}

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Observer minimalista per lifecycle senza dover "implements WidgetsBindingObserver"
class _LifecycleObserver extends WidgetsBindingObserver {
  final void Function(AppLifecycleState state) onState;

  _LifecycleObserver({required this.onState});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onState(state);
  }
}
