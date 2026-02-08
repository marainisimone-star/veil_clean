import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../routes/app_routes.dart';

import '../screens/gate_screen.dart';
import '../screens/lock_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/inbox_screen.dart';
import '../screens/thread_screen.dart';
import '../screens/contacts_screen.dart';
import '../screens/new_conversation_screen.dart';
import '../security/panic_lock_screen.dart';
import '../security/panic_controller.dart';

class AppRouter {
  AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.gate:
        return MaterialPageRoute(builder: (_) => const GateScreen(), settings: settings);

      case AppRoutes.lock:
        return MaterialPageRoute(builder: (_) => const LockScreen(), settings: settings);

      case AppRoutes.onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingScreen(), settings: settings);

      case AppRoutes.auth:
        return MaterialPageRoute(builder: (_) => const AuthScreen(), settings: settings);

      case AppRoutes.panic:
        final arg = settings.arguments;
        final reason = (arg is PanicReason) ? arg : PanicReason.unknown;
        return MaterialPageRoute(
          builder: (_) => PanicLockScreen(reason: reason),
          settings: settings,
        );

      case AppRoutes.inbox:
        return MaterialPageRoute(builder: (_) => const InboxScreen(), settings: settings);

      case AppRoutes.contacts:
        return MaterialPageRoute(builder: (_) => const ContactsScreen(), settings: settings);

      case AppRoutes.newConversation:
        return MaterialPageRoute(builder: (_) => const NewConversationScreen(), settings: settings);

      case AppRoutes.thread:
        final arg = settings.arguments;
        if (arg is Conversation) {
          return MaterialPageRoute(
            builder: (_) => ThreadScreen(conversation: arg),
            settings: settings,
          );
        }
        return MaterialPageRoute(builder: (_) => const InboxScreen(), settings: settings);

      default:
        // fallback
        return MaterialPageRoute(builder: (_) => const GateScreen(), settings: settings);
    }
  }
}
