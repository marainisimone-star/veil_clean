import 'package:flutter/material.dart';

import '../routes/app_routes.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/bottom_nav_strip.dart';

class HomeHubScreen extends StatefulWidget {
  const HomeHubScreen({super.key});

  @override
  State<HomeHubScreen> createState() => _HomeHubScreenState();
}

enum _HubPrimary { messaging, social }

class _HomeHubScreenState extends State<HomeHubScreen> {
  _HubPrimary _primary = _HubPrimary.messaging;
  bool _minimizeSecondary = false;

  void _swap() {
    setState(() {
      _primary =
          _primary == _HubPrimary.messaging ? _HubPrimary.social : _HubPrimary.messaging;
    });
  }

  void _toggleMinimize() {
    setState(() => _minimizeSecondary = !_minimizeSecondary);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final border = scheme.outlineVariant.withAlpha((0.45 * 255).round());

    final messagingPanel = _panel(
      title: 'Messaging',
      subtitle: 'Conversazioni recenti',
      badge: '3',
      onOpen: () => Navigator.pushNamed(context, AppRoutes.inbox),
      onMakePrimary: _primary == _HubPrimary.messaging ? null : _swap,
      items: const [
        'Giornata · Ok, ci sentiamo nel pomeriggio',
        'Angela · Possiamo sentirci domani?',
        'Team · Documento ricevuto',
      ],
      fg: fg,
      muted: muted,
      scheme: scheme,
      border: border,
    );

    final socialPanel = _panel(
      title: 'Showcases',
      subtitle: 'Trend and quality',
      badge: '2',
      onOpen: () => Navigator.pushNamed(context, AppRoutes.vetrine),
      onMakePrimary: _primary == _HubPrimary.social ? null : _swap,
      items: const [
        'Science · High quality, medium mass',
        'Culture · High mass, medium quality',
      ],
      fg: fg,
      muted: muted,
      scheme: scheme,
      border: border,
    );

    return BackgroundScaffold(
      style: VeilBackgroundStyle.inbox,
      appBar: AppBar(
        title: Text('Veil', style: TextStyle(color: fg)),
        foregroundColor: fg,
        actions: [
          TextButton(
            onPressed: _swap,
            child: Text('Swap', style: TextStyle(color: fg)),
          ),
          TextButton(
            onPressed: _toggleMinimize,
            child: Text(
              _minimizeSecondary ? 'Expand' : 'Minimize',
              style: TextStyle(color: fg),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNavStrip(current: BottomNavTab.chats),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final primaryPanel =
              _primary == _HubPrimary.messaging ? messagingPanel : socialPanel;
          final secondaryPanel =
              _primary == _HubPrimary.messaging ? socialPanel : messagingPanel;

          if (_minimizeSecondary) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(child: primaryPanel),
                  const SizedBox(height: 12),
                  _minimizedBar(
                    title: _primary == _HubPrimary.messaging ? 'Showcases' : 'Messaging',
                    badge: _primary == _HubPrimary.messaging ? '2' : '3',
                    fg: fg,
                    scheme: scheme,
                    border: border,
                    onTap: _swap,
                  ),
                ],
              ),
            );
          }

          if (wide) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(flex: 7, child: primaryPanel),
                  const SizedBox(width: 16),
                  Expanded(flex: 4, child: secondaryPanel),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(child: primaryPanel),
                const SizedBox(height: 16),
                SizedBox(height: 240, child: secondaryPanel),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _panel({
    required String title,
    required String subtitle,
    required String badge,
    required VoidCallback onOpen,
    required VoidCallback? onMakePrimary,
    required List<String> items,
    required Color fg,
    required Color muted,
    required ColorScheme scheme,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primary.withAlpha((0.12 * 255).round()),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(badge, style: TextStyle(color: fg, fontSize: 11)),
              ),
              const Spacer(),
              if (onMakePrimary != null)
                TextButton(
                  onPressed: onMakePrimary,
                  child: const Text('Make primary'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(color: border),
              itemBuilder: (_, i) {
                return Text(items[i], style: TextStyle(color: fg, fontSize: 13));
              },
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onOpen,
              child: const Text('Open'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _minimizedBar({
    required String title,
    required String badge,
    required Color fg,
    required ColorScheme scheme,
    required Color border,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary.withAlpha((0.12 * 255).round()),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(badge, style: TextStyle(color: fg, fontSize: 11)),
            ),
            const Spacer(),
            Icon(Icons.swap_horiz, color: fg),
          ],
        ),
      ),
    );
  }
}
