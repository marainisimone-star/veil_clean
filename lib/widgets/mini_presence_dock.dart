import 'package:flutter/material.dart';

import '../data/local_storage.dart';
import '../routes/app_routes.dart';

enum PresenceMode { messaging, social }

class MiniPresenceDock extends StatefulWidget {
  const MiniPresenceDock({
    super.key,
    required this.mode,
    this.compact = false,
  });

  final PresenceMode mode;
  final bool compact;

  @override
  State<MiniPresenceDock> createState() => _MiniPresenceDockState();
}

class _MiniPresenceDockState extends State<MiniPresenceDock> {
  static const String _kDockMin = 'veil_presence_dock_min_v1';
  bool _minimized = false;

  @override
  void initState() {
    super.initState();
    _minimized = LocalStorage.getString(_kDockMin) == '1';
  }

  void _toggleMinimize() {
    final next = !_minimized;
    setState(() => _minimized = next);
    LocalStorage.setString(_kDockMin, next ? '1' : '0');
  }

  void _openOther() {
    final route =
        widget.mode == PresenceMode.messaging ? AppRoutes.vetrine : AppRoutes.inbox;
    Navigator.pushNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 600;
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final border = scheme.outlineVariant.withAlpha((0.45 * 255).round());
    final title = widget.mode == PresenceMode.messaging ? 'Social' : 'Messaging';
    final subtitle = widget.mode == PresenceMode.messaging
        ? 'Showcases: 2 trending'
        : 'Chats: 3 unread';
    final badge = widget.mode == PresenceMode.messaging ? '2' : '3';

    if (isNarrow) {
      return _iconDock(scheme, fg, muted, border, title, badge);
    }

    if (_minimized) {
      return InkWell(
        onTap: _openOther,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              _badge(badge, scheme, fg),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Expand',
                onPressed: _toggleMinimize,
                icon: Icon(Icons.unfold_more, size: 16, color: muted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.compact) {
      final width = 200.0;
      final height = 72.0;
      return Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((0.06 * 255).round()),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      _badge(badge, scheme, fg),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: muted, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            TextButton(
              onPressed: _openOther,
              child: const Text('Open'),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.06 * 255).round()),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(title, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              _badge(badge, scheme, fg),
              const Spacer(),
              IconButton(
                tooltip: 'Minimize',
                onPressed: _toggleMinimize,
                icon: Icon(Icons.unfold_less, size: 16, color: muted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: muted, fontSize: 11)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _openOther,
              child: const Text('Open'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, ColorScheme scheme, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary.withAlpha((0.12 * 255).round()),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(color: fg, fontSize: 10)),
    );
  }

  Widget _iconDock(
    ColorScheme scheme,
    Color fg,
    Color muted,
    Color border,
    String title,
    String badge,
  ) {
    return InkWell(
      onTap: () => _openMiniPanel(scheme, fg, muted, border, title),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 56,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(widget.mode == PresenceMode.messaging ? Icons.storefront_outlined : Icons.chat_bubble_outline,
                size: 18, color: muted),
            Positioned(
              right: 6,
              top: 6,
              child: _badge(badge, scheme, fg),
            ),
          ],
        ),
      ),
    );
  }

  void _openMiniPanel(
    ColorScheme scheme,
    Color fg,
    Color muted,
    Color border,
    String title,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    _badge(widget.mode == PresenceMode.messaging ? '2' : '3', scheme, fg),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.mode == PresenceMode.messaging ? 'Showcases: 2 trending' : 'Chats: 3 unread',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _openOther();
                    },
                    child: const Text('Open'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
