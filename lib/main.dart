import 'package:dev_retos/core/repositories/auth_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/database/turso_client.dart';
import 'core/repositories/retos_repository.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/connectivity_provider.dart';
import 'core/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/widgets/no_connection_screen.dart';
import 'firebase_options.dart';

void main() async {
  final stopwatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();

  await Future.wait([
    dotenv.load(fileName: ".env"),
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    MobileAds.instance.initialize(),
    initializeDateFormatting('es_ES', null),
  ]);

  print(
    '🚀 Inicialización completada (Firebase + AdMob) en: ${stopwatch.elapsedMilliseconds}ms',
  );
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final startTime = DateTime.now();

    final client = ref.read(tursoClientProvider);
    try {
      await client.connect();
      await ref.read(retosRepositoryProvider).initDatabase();
      print('Base de datos inicializada!');

      // Inicializar Notificaciones
      await ref
          .read(notificationServiceProvider)
          .init(
            onPayload: (payload) {
              if (payload == '/diario') {
                print('🔔 Tapped Notification! Navegando a $payload');
                ref.read(goRouterProvider).go(payload!);
              }
            },
          );

      final user = await ref
          .read(authRepositoryProvider)
          .checkAuthState(client);
      if (user != null) {
        ref.read(currentUserProvider.notifier).update(user);

        final prefs = await SharedPreferences.getInstance();
        final notifsEnabled = prefs.getBool('notifications_enabled') ?? false;
        if (notifsEnabled) {
          try {
            final userProfile = await ref.read(userProfileProvider.future);
            final streak = userProfile?['streak_count'] as int? ?? 0;
            await ref
                .read(notificationServiceProvider)
                .scheduleDailyReminder(streak);
          } catch (e) {
            print('Error sincronizando racha para notificaciones: $e');
          }
        }
      }

      ref.invalidate(dailyChallengesProvider);
    } catch (e) {
      print('Error de conexión inicial: $e');
    }

    final elapsed = DateTime.now().difference(startTime);
    if (elapsed.inMilliseconds < 400) {
      await Future.delayed(
        Duration(milliseconds: 400 - elapsed.inMilliseconds),
      );
    }

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return MaterialApp(
        title: 'Dev Retos',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const SplashLoadingScreen(),
      );
    }

    final goRouter = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'Dev Retos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: goRouter,
      builder: (context, child) {
        final isOnline = ref.watch(isOnlineProvider);
        if (!isOnline) {
          return const NoConnectionScreen();
        }
        return child!;
      },
    );
  }
}

class SplashLoadingScreen extends StatelessWidget {
  const SplashLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.5),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/logotipo.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              'Dev Retos',
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.white12,
                  color: theme.colorScheme.primary,
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Preparando entorno...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
