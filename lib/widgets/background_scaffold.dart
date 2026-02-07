import 'package:flutter/material.dart';

/// Stili di background centralizzati.
///
/// NOTA: includo anche `main` per compatibilità (in passato era usato come "generico").
/// Se in futuro vuoi ripulire, possiamo rimuoverlo quando siamo certi che nessuno lo usa più.
enum VeilBackgroundStyle {
  onboarding,
  lock,
  inbox,
  main,
  thread,
}

class BackgroundScaffold extends StatelessWidget {
  const BackgroundScaffold({
    super.key,
    required this.child,
    required this.style,
    this.appBar,
    this.padding,
    this.safeArea = true,
  });

  final Widget child;
  final VeilBackgroundStyle style;

  /// FIX V4: ora supporta `appBar:` come uno Scaffold standard.
  final PreferredSizeWidget? appBar;

  final EdgeInsetsGeometry? padding;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final bg = _backgroundFor(style);

    Widget body = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bg.colors,
          stops: bg.stops,
        ),
      ),
        child: Container(
          // Overlay leggero per coerenza e leggibilità.
          // (NO withOpacity: usiamo withAlpha per evitare deprecation)
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
              Colors.white.withAlpha((0.35 * 255).round()),
              Colors.white.withAlpha((0.10 * 255).round()),
              ],
            ),
          ),
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
        ),
      ),
    );

    if (safeArea) {
      body = SafeArea(child: body);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F4F0),
      appBar: appBar,
      body: body,
    );
  }

  _VeilBg _backgroundFor(VeilBackgroundStyle s) {
    switch (s) {
      case VeilBackgroundStyle.onboarding:
        return const _VeilBg(
          colors: [
            Color(0xFFF8F5F0),
            Color(0xFFF2EEE8),
            Color(0xFFEDE7DF),
          ],
          stops: [0.0, 0.55, 1.0],
        );

      case VeilBackgroundStyle.lock:
        return const _VeilBg(
          colors: [
            Color(0xFFF7F4EF),
            Color(0xFFF0ECE5),
            Color(0xFFE9E3DB),
          ],
          stops: [0.0, 0.55, 1.0],
        );

      case VeilBackgroundStyle.inbox:
        return const _VeilBg(
          colors: [
            Color(0xFFF8F6F2),
            Color(0xFFF1EDE6),
            Color(0xFFEAE4DC),
          ],
          stops: [0.0, 0.6, 1.0],
        );

      case VeilBackgroundStyle.main:
        // Alias "generico" (compatibilità). Lo mappo a inbox.
        return const _VeilBg(
          colors: [
            Color(0xFFF8F6F2),
            Color(0xFFF1EDE6),
            Color(0xFFEAE4DC),
          ],
          stops: [0.0, 0.6, 1.0],
        );

      case VeilBackgroundStyle.thread:
        return const _VeilBg(
          colors: [
            Color(0xFFF7F4EF),
            Color(0xFFF0ECE5),
            Color(0xFFE9E3DB),
          ],
          stops: [0.0, 0.6, 1.0],
        );
    }
  }
}

class _VeilBg {
  const _VeilBg({required this.colors, required this.stops});

  final List<Color> colors;
  final List<double> stops;
}
