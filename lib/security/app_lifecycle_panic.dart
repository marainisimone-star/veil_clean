import 'package:flutter/widgets.dart';

/// V4.2 DEV-SAFE:
/// In sviluppo NON reagiamo al lifecycle.
/// Il lock/panic deve essere esplicito (bottone, passphrase, ecc).
///
/// In produzione mobile questa classe potrà essere riattivata.
class AppLifecyclePanic extends StatelessWidget {
  const AppLifecyclePanic({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // In DEV: nessun observer, nessun lock automatico
    return child;
  }
}
