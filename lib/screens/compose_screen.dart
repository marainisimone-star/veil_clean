import 'package:flutter/material.dart';
import '../routes/app_routes.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/bottom_nav_strip.dart';

class ComposeScreen extends StatelessWidget {
  const ComposeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    return BackgroundScaffold(
      style: VeilBackgroundStyle.inbox,
      bottomNavigationBar: const BottomNavStrip(current: BottomNavTab.chats),
      appBar: AppBar(
        title: const Text('Compose'),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Start a new chat',
                  style: TextStyle(color: fg, fontSize: 18),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      AppRoutes.newConversation,
                    ),
                    child: const Text('New conversation'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: fg,
                      side: BorderSide(color: muted),
                    ),
                    child: const Text('Back to Inbox'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
