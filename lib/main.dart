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

      final results = await Future.wait([
        ref.read(retosRepositoryProvider).initDatabase(),
        ref
            .read(notificationServiceProvider)
            .init(
              onPayload: (payload) {
                if (payload == '/diario') {
                  ref.read(goRouterProvider).go(payload!);
                }
              },
            ),
        ref.read(authRepositoryProvider).checkAuthState(client),
      ]);

      final user = results[2] as AuthUser?;

      if (user != null) {
        ref.read(currentUserProvider.notifier).update(user);

        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('notifications_enabled') ?? false) {
          try {
            final userProfile = await ref.read(userProfileProvider.future);
            final streak = userProfile?['streak_count'] as int? ?? 0;

            final challenges = await ref.read(dailyChallengesProvider.future);
            final completedToday =
                challenges.isNotEmpty &&
                challenges.first['is_completed'] == true;

            await ref
                .read(notificationServiceProvider)
                .scheduleDailyReminder(streak, completedToday: completedToday);
          } catch (_) {}
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

class SplashLoadingScreen extends StatefulWidget {
  const SplashLoadingScreen({super.key});

  @override
  State<SplashLoadingScreen> createState() => _SplashLoadingScreenState();
}

class _SplashLoadingScreenState extends State<SplashLoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _fadeAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.05),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Hero(
                  tag: 'logo',
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.2),
                          blurRadius: 40,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipOval(child: Image.asset('assets/logotipo.png')),
                  ),
                ),
                const SizedBox(height: 40),
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [Colors.white, Colors.white.withOpacity(0.5)],
                  ).createShader(bounds),
                  child: Text(
                    'DEV RETOS',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 160,
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.white.withOpacity(0.05),
                          color: theme.colorScheme.primary,
                          minHeight: 2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Text(
                          'Sincronizando retos...',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white38,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
