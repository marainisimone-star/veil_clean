import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'data/local_storage.dart';
import 'routes/app_router.dart';
import 'services/notification_service.dart';
import 'services/firebase_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStorage.init();

  try {
    await FirebaseBackend.I.init();
  } catch (_) {}

  try {
    await NotificationService.I.init();
  } catch (_) {}

  // IMPORTANT: su Windows evita crash/blur spam se non inizializzi window_manager
  try {
    await windowManager.ensureInitialized();
  } catch (_) {}

  runApp(const VeilCleanApp());
}

class VeilCleanApp extends StatelessWidget {
  const VeilCleanApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1C2030),
      brightness: Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Veil',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF6F4F0),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: scheme.onSurface,
        ),
      ),
      onGenerateRoute: AppRouter.onGenerateRoute,
      initialRoute: '/',
    );
  }
}
