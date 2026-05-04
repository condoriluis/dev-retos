import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:country_flags/country_flags.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/repositories/retos_repository.dart';
import '../../core/repositories/auth_repository.dart';
import '../../core/services/notification_service.dart';
import '../../core/widgets/pro_paywall.dart';
import '../../core/widgets/scanner_loading.dart';
import '../../core/widgets/app_refresh_indicator.dart';

class PerfilScreen extends ConsumerStatefulWidget {
  const PerfilScreen({super.key});

  @override
  ConsumerState<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends ConsumerState<PerfilScreen> {
  static bool _sessionScanDone = false;
  late bool _showInitialScanner;
  bool _notificationsEnabled = true;
  String? _selectedCountry;
  String? _newUsername;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _availabilityError;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _showInitialScanner = !_sessionScanDone;
    if (_showInitialScanner) {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() => _showInitialScanner = false);
          _sessionScanDone = true;
        }
      });
    }
    _loadNotificationPreferences();
  }

  Future<void> _loadNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? false;
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final notificationService = ref.read(notificationServiceProvider);

    if (value) {
      final granted = await notificationService.requestPermissions();
      if (granted) {
        final userProfile = ref.read(userProfileProvider).value;
        final currentStreak = userProfile?['streak_count'] as int? ?? 0;

        await notificationService.scheduleDailyReminder(currentStreak);
        await notificationService.showInstantNotification(
          title: 'Recordatorio Activado',
          body:
              '¡Todo listo! Te avisaremos todos los días a las 9:00 AM para tu reto diario.',
        );
        await prefs.setBool('notifications_enabled', true);
        setState(() => _notificationsEnabled = true);
      } else {
        setState(() => _notificationsEnabled = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permisos de notificación denegados.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } else {
      await notificationService.cancelAllNotifications();
      await prefs.setBool('notifications_enabled', false);
      setState(() => _notificationsEnabled = false);
    }
  }

  final List<String> _latamCountries = [
    'Argentina',
    'Bolivia',
    'Brasil',
    'Chile',
    'Colombia',
    'Ecuador',
    'México',
    'Paraguay',
    'Perú',
    'Uruguay',
    'Venezuela',
  ];

  String _getCountryCode(String? country) {
    const codes = {
      'Argentina': 'AR',
      'Bolivia': 'BO',
      'Brasil': 'BR',
      'Chile': 'CL',
      'Colombia': 'CO',
      'Ecuador': 'EC',
      'México': 'MX',
      'Paraguay': 'PY',
      'Perú': 'PE',
      'Uruguay': 'UY',
      'Venezuela': 'VE',
    };
    return codes[country] ?? 'BO';
  }

  Future<void> _handleRefresh() async {
    ref.invalidate(userProfileProvider);
    ref.invalidate(weeklyProgressProvider);

    await ref.read(userProfileProvider.future);
  }

  Future<void> _handleLogout() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D21),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: theme.colorScheme.primary.withOpacity(0.2),
            width: 1,
          ),
        ),
        title: const Text(
          'Cerrar Sesión',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: const Text(
            '¿Estás seguro que deseas cerrar tu sesión actual?',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'CERRAR SESIÓN',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(authRepositoryProvider).signOut();
      ref.read(currentUserProvider.notifier).update(null);
      if (mounted) context.go('/auth');
    }
  }

  Future<void> _handleDeleteAccount() async {
    final userProfile = ref.read(userProfileProvider).value;
    final isPro =
        userProfile != null &&
        (userProfile['is_pro'] == true ||
            userProfile['is_pro'] == 1 ||
            userProfile['is_pro']?.toString() == '1' ||
            userProfile['is_pro']?.toString() == 'true');

    final message = isPro
        ? 'Esta acción es irreversible. Se eliminarán todos tus datos de progreso y tu acceso PRO definitivamente. ¿Deseas continuar?'
        : 'Esta acción es irreversible. Se eliminarán todos tus datos de progreso definitivamente. ¿Deseas continuar?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D21),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.redAccent.withOpacity(0.3), width: 1),
        ),
        title: const Text(
          'Eliminar Cuenta',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(message, style: const TextStyle(color: Colors.white70)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'ELIMINAR DEFINITIVAMENTE',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final user = ref.read(currentUserProvider);
        if (user != null) {
          await ref.read(authRepositoryProvider).deleteAccount();
          await ref.read(retosRepositoryProvider).deleteUserAccount(user.id);

          ref.read(currentUserProvider.notifier).update(null);
          if (mounted) context.go('/auth');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error al eliminar cuenta. Re-autentícate e intenta de nuevo: $e',
              ),
            ),
          );
        }
      }
    }
  }

  void _checkUsername(String value, String currentId) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (value == currentId) {
      setState(() {
        _isUsernameAvailable = null;
        _isCheckingUsername = false;
        _availabilityError = null;
      });
      return;
    }

    if (value.trim().length < 3) {
      setState(() {
        _isUsernameAvailable = false;
        _availabilityError = 'Mínimo 3 caracteres';
      });
      return;
    }

    if (value.contains(' ')) {
      setState(() {
        _isUsernameAvailable = false;
        _availabilityError = 'Sin espacios permitidos';
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _availabilityError = null;
    });

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final available = await ref
          .read(retosRepositoryProvider)
          .isUsernameAvailable(value, currentId);
      if (mounted) {
        setState(() {
          _isUsernameAvailable = available;
          _isCheckingUsername = false;
          _availabilityError = available
              ? null
              : 'Este username ya está en uso';
        });
      }
    });
  }

  Future<void> _submitNewUsername(String newUsername, String userId) async {
    if (newUsername.trim().length < 3 || newUsername.contains(' ')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Username inválido. Mínimo 3 letras sin espacios.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final repo = ref.read(retosRepositoryProvider);
    final errorMsg = await repo.updateUsername(userId, newUsername.trim());

    if (mounted) {
      if (errorMsg != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Username actualizado exitosamente.'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _isUsernameAvailable = null;
          _newUsername = null;
          _availabilityError = null;
          _isCheckingUsername = false;
        });
        ref.invalidate(userProfileProvider);
        ref.invalidate(globalRankingProvider);
        ref.invalidate(dailyRankingProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final userAsync = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mi Perfil')),
      body:
          (_showInitialScanner || (userAsync.isLoading && !userAsync.hasValue))
          ? const ScannerLoading()
          : userAsync.when(
              loading: () => const ScannerLoading(),
              error: (err, stack) =>
                  Center(child: Text('Error al cargar perfil: $err')),
              data: (user) {
                final bool isGuest = ref.watch(currentUserProvider) == null;

                if (isGuest || user == null) {
                  final xp = user?['xp'] ?? 0;
                  final streak = user?['current_streak'] ?? 0;

                  return Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 450),
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      theme.colorScheme.primary,
                                      theme.colorScheme.secondary,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: theme.colorScheme.primary
                                          .withOpacity(0.3),
                                      blurRadius: 20,
                                      spreadRadius: 2,
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
                              const SizedBox(height: 24),
                              Text(
                                'Tu Perfil',
                                style: textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                xp > 0 || streak > 0
                                    ? '¡Increíble! Ya llevas $xp XP y una racha de $streak días como invitado. Inicia sesión ahora para guardar tu progreso permanentemente.'
                                    : 'Inicia sesión para guardar tus stats, rachas y competir globalmente en el ranking de Devs.',
                                textAlign: TextAlign.center,
                                style: textTheme.bodyLarge?.copyWith(
                                  color: Colors.white70,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 40),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () => context.push('/login'),
                                  icon: const Icon(Icons.login),
                                  label: const Text(
                                    'INICIAR SESIÓN',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () => context.push('/login'),
                                child: const Text(
                                  '¿No tienes cuenta? Regístrate',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }

                final isPro =
                    user['is_pro'] == true ||
                    user['is_pro'] == 1 ||
                    user['is_pro']?.toString() == '1' ||
                    user['is_pro']?.toString() == 'true';

                final lastUpdateStr = user['last_username_update'];
                final lastUpdate = lastUpdateStr != null
                    ? DateTime.tryParse(lastUpdateStr)
                    : null;

                String remainingMsg = "";
                bool canChangeUsername = true;

                if (lastUpdate != null) {
                  final targetDate = lastUpdate.add(const Duration(days: 7));
                  final remaining = targetDate.difference(DateTime.now());
                  canChangeUsername = remaining.isNegative;

                  if (!canChangeUsername) {
                    final daysLeft = (remaining.inHours / 24.0).ceil();
                    if (daysLeft > 1) {
                      remainingMsg =
                          'Podrás volver a actualizar en $daysLeft días.';
                    } else if (daysLeft == 1 && remaining.inHours > 24) {
                      remainingMsg = 'Podrás volver a actualizar en 1 día.';
                    } else {
                      remainingMsg =
                          'Podrás volver a actualizar en ${remaining.inHours} horas.';
                    }
                  }
                }

                return AppRefreshIndicator(
                  onRefresh: _handleRefresh,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.surface,
                                border: Border.all(
                                  color: theme.colorScheme.primary.withOpacity(
                                    0.5,
                                  ),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(8),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/logotipo.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.account_circle,
                                    size: 70,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '@${user['username']}',
                                  style: textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (isPro) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.verified,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                                ] else ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'FREE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user['name'] ?? 'Usuario',
                              style: textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (isPro) ...[
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: () => _showProInfoDialog(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.blue.shade700,
                                        Colors.blue.shade400,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(25),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.verified_user,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'PRO',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 2),
                              TextButton(
                                onPressed: () => ProPaywall.show(context),
                                child: const Text(
                                  'Mejorar a PRO',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 14),
                        Text('Estadísticas', style: textTheme.titleMedium),
                        const SizedBox(height: 16),

                        () {
                          final played = user['played'] ?? 0;
                          final won = user['won'] ?? 0;
                          final bestTime = user['best_time'] ?? '--:--';
                          final streak = user['current_streak'] ?? 0;

                          return GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 2.2,
                            children: [
                              _buildStatCard(
                                context,
                                'Jugados',
                                played.toString(),
                              ),
                              _buildStatCard(
                                context,
                                'Ganados',
                                won.toString(),
                              ),
                              _buildStatCard(
                                context,
                                'Racha Actual',
                                '$streak días',
                                trailing: isPro
                                    ? _buildCompactShield(context, user)
                                    : null,
                              ),
                              _buildStatCard(context, 'Mejor Tiempo', bestTime),
                            ],
                          );
                        }(),

                        const SizedBox(height: 16),
                        _buildProZone(context, isPro),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              'Actualizar Username',
                              style: textTheme.titleMedium,
                            ),
                            const SizedBox(width: 0),
                            IconButton(
                              icon: Icon(
                                Icons.info_outline,
                                size: 16,
                                color: canChangeUsername
                                    ? theme.colorScheme.primary
                                    : Colors.grey,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: canChangeUsername
                                  ? () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => Dialog(
                                          backgroundColor: Colors.transparent,
                                          child: Container(
                                            padding: const EdgeInsets.all(24),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Color.alphaBlend(
                                                    theme.colorScheme.primary
                                                        .withOpacity(0.08),
                                                    theme.colorScheme.surface,
                                                  ),
                                                  Color.alphaBlend(
                                                    theme.colorScheme.primary
                                                        .withOpacity(0.18),
                                                    theme.colorScheme.surface,
                                                  ),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(28),
                                              border: Border.all(
                                                color: theme
                                                    .colorScheme
                                                    .outlineVariant
                                                    .withOpacity(0.5),
                                                width: 1.2,
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.info_outline,
                                                      color: Colors.white,
                                                      size: 28,
                                                    ),
                                                    const SizedBox(width: 16),
                                                    Text(
                                                      'Username',
                                                      style: theme
                                                          .textTheme
                                                          .titleLarge
                                                          ?.copyWith(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 20),
                                                const Text(
                                                  'Para mantener la integridad y consistencia de la comunidad, el cambio de nombre de usuario está limitado a una vez cada 7 días. \n\nPor favor, elige tu nuevo nombre cuidadosamente.',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 14,
                                                    height: 1.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 24),
                                                Center(
                                                  child: FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                    style: FilledButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.white,
                                                      foregroundColor: theme
                                                          .colorScheme
                                                          .primary,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 32,
                                                            vertical: 12,
                                                          ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      'ENTENDIDO',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  : null,
                              tooltip: canChangeUsername
                                  ? 'Información sobre cambios de username'
                                  : 'Cambio bloqueado temporalmente',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withOpacity(0.5),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!canChangeUsername)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 12.0,
                                      left: 4.0,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.timer_outlined,
                                          color: Colors.orange,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            remainingMsg,
                                            style: const TextStyle(
                                              color: Colors.orange,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: user['username'],
                                        enabled: canChangeUsername,
                                        readOnly: !canChangeUsername,
                                        maxLength: 15,
                                        decoration: InputDecoration(
                                          labelText: canChangeUsername
                                              ? 'Nuevo Username'
                                              : 'Username Actual',
                                          prefixText: '@',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              30,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              30,
                                            ),
                                            borderSide: BorderSide(
                                              color: theme
                                                  .colorScheme
                                                  .outlineVariant
                                                  .withOpacity(0.5),
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              30,
                                            ),
                                            borderSide: BorderSide(
                                              color: theme.colorScheme.primary,
                                              width: 2,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 12,
                                              ),
                                          isDense: true,
                                          counterText: "",
                                          filled: !canChangeUsername,
                                          fillColor: !canChangeUsername
                                              ? Colors.white.withOpacity(0.05)
                                              : null,
                                          errorText: _availabilityError,
                                          errorStyle: const TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 12,
                                          ),
                                          suffixIcon: canChangeUsername
                                              ? (_isCheckingUsername
                                                    ? const SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child: Padding(
                                                          padding:
                                                              EdgeInsets.all(
                                                                12.0,
                                                              ),
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                              ),
                                                        ),
                                                      )
                                                    : (_isUsernameAvailable ==
                                                              true
                                                          ? const Icon(
                                                              Icons
                                                                  .check_circle,
                                                              color:
                                                                  Colors.green,
                                                            )
                                                          : (_isUsernameAvailable ==
                                                                    false
                                                                ? const Icon(
                                                                    Icons.error,
                                                                    color: Colors
                                                                        .red,
                                                                  )
                                                                : null)))
                                              : const Icon(
                                                  Icons.lock_outline,
                                                  size: 18,
                                                  color: Colors.grey,
                                                ),
                                        ),
                                        onChanged: (val) {
                                          if (canChangeUsername) {
                                            _newUsername = val;
                                            _checkUsername(
                                              val,
                                              user['username'],
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                    if (canChangeUsername) ...[
                                      const SizedBox(width: 8),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: FilledButton(
                                          onPressed:
                                              (_isUsernameAvailable == true &&
                                                  !_isCheckingUsername)
                                              ? () {
                                                  final text =
                                                      _newUsername ??
                                                      user['username']
                                                          as String;
                                                  if (text !=
                                                      user['username']) {
                                                    _submitNewUsername(
                                                      text,
                                                      user['id'],
                                                    );
                                                  }
                                                }
                                              : null,
                                          child: const Text('Guardar'),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Última actualización: ${lastUpdate != null ? DateFormat('dd/MM/yyyy').format(lastUpdate) : "Nunca"}',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),
                        Text('Configuración', style: textTheme.titleMedium),
                        const SizedBox(height: 8),

                        Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withOpacity(0.5),
                            ),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                leading: Icon(
                                  Icons.email_outlined,
                                  color: theme.colorScheme.primary,
                                ),
                                title: const Text('Email'),
                                trailing: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 180,
                                  ),
                                  child: Text(
                                    user['email'] ?? '',
                                    style: const TextStyle(color: Colors.grey),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: Icon(
                                  Icons.public,
                                  color: theme.colorScheme.primary,
                                ),
                                title: const Text('País'),
                                trailing: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value:
                                        _latamCountries.contains(
                                          _selectedCountry ?? user['country'],
                                        )
                                        ? (_selectedCountry ?? user['country'])
                                              as String
                                        : 'Bolivia',
                                    items: _latamCountries
                                        .map(
                                          (String value) => DropdownMenuItem(
                                            value: value,
                                            child: Row(
                                              children: [
                                                CountryFlag.fromCountryCode(
                                                  _getCountryCode(value),
                                                  theme: const ImageTheme(
                                                    width: 18,
                                                    height: 18,
                                                    shape: Circle(),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(value),
                                              ],
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (newValue) async {
                                      if (newValue != null) {
                                        setState(
                                          () => _selectedCountry = newValue,
                                        );
                                        final success = await ref
                                            .read(retosRepositoryProvider)
                                            .updateCountry(
                                              user['id'],
                                              newValue,
                                            );
                                        if (success && mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'País guardado exitosamente',
                                              ),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                          ref.invalidate(userProfileProvider);
                                          ref.invalidate(globalRankingProvider);
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                activeThumbColor: theme.colorScheme.primary,
                                secondary: Icon(
                                  _notificationsEnabled
                                      ? Icons.notifications_active
                                      : Icons.notifications_outlined,
                                  color: _notificationsEnabled
                                      ? Colors.amber
                                      : theme.colorScheme.primary,
                                ),
                                title: const Text('Notificaciones'),
                                subtitle: const Text(
                                  'Recordatorio de retos diarios',
                                  style: TextStyle(fontSize: 11),
                                ),
                                value: _notificationsEnabled,
                                onChanged: _toggleNotifications,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),
                        Text('Cuenta', style: textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withOpacity(0.5),
                            ),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                leading: const Icon(
                                  Icons.logout,
                                  color: Colors.orange,
                                ),
                                title: const Text(
                                  'Cerrar Sesión',
                                  style: TextStyle(color: Colors.orange),
                                ),
                                onTap: _handleLogout,
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(
                                  Icons.delete_forever,
                                  color: Colors.redAccent,
                                ),
                                title: const Text(
                                  'Eliminar Cuenta',
                                  style: TextStyle(color: Colors.redAccent),
                                ),
                                onTap: _handleDeleteAccount,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () => context.push('/terms'),
                              child: const Text(
                                'Términos y Condiciones',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                '•',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => context.push('/privacy'),
                              child: const Text(
                                'Privacidad',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            'Versión 1.0.0 • XP Actual: ${user['xp']}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildCompactShield(BuildContext context, dynamic user) {
    final theme = Theme.of(context);
    final lastShieldStr = user['last_shield_used']?.toString();
    final lastShield = lastShieldStr != null
        ? DateTime.tryParse(lastShieldStr)
        : null;

    bool isAvailable = true;
    int daysLeft = 0;

    if (lastShield != null) {
      final now = DateTime.now();
      final todayDate = DateTime(now.year, now.month, now.day);
      final shieldDate = DateTime(
        lastShield.year,
        lastShield.month,
        lastShield.day,
      );
      final diff = todayDate.difference(shieldDate).inDays;

      if (diff < 7) {
        isAvailable = false;
        daysLeft = 7 - diff;
      }
    }

    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF004D40), // Teal/Verde muy profundo
                    const Color(0xFF00241B), // Casi negro verdoso
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.greenAccent.withOpacity(0.15),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.2),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isAvailable ? Icons.shield : Icons.shield_outlined,
                      color: isAvailable ? Colors.greenAccent : Colors.white38,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Escudo de Racha',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '(Streak Shield)',
                    style: TextStyle(
                      color: Colors.greenAccent.withOpacity(0.7),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isAvailable
                        ? 'Tu protección está activa. Si olvidas resolver el reto de un día, el escudo se sacrificará automáticamente para mantener tu racha intacta.'
                        : 'El escudo se utilizó recientemente para salvar tu racha. Se recarga automáticamente cada 7 días.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  if (!isAvailable) ...[
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Recargando escudo',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                'Día ${7 - daysLeft + 1} de 7',
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 1500),
                              curve: Curves.easeOutCubic,
                              tween: Tween<double>(
                                begin: 0,
                                end: (7 - daysLeft + 1) / 7,
                              ),
                              builder: (context, value, _) {
                                return LinearProgressIndicator(
                                  value: value,
                                  backgroundColor: Colors.white12,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Colors.orangeAccent,
                                      ),
                                  minHeight: 6,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Center(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF004D40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isAvailable
              ? Colors.green.withOpacity(0.2)
              : Colors.grey.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isAvailable ? Icons.shield : Icons.shield_outlined,
          color: isAvailable ? Colors.greenAccent : Colors.grey,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value, {
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildProZone(BuildContext context, bool isPro) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('EXPERIENCIAS', style: textTheme.titleMedium),
            const SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildProActionCard(
              context,
              title: 'Dashboard',
              subtitle: 'Analíticas avanzadas',
              icon: Icons.analytics_outlined,
              isPro: isPro,
              onTap: () {
                if (isPro) {
                  context.push('/pro-analytics');
                } else {
                  ProPaywall.show(context);
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isPro,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isPro
                ? theme.colorScheme.primary.withOpacity(0.1)
                : theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPro
                  ? theme.colorScheme.primary.withOpacity(0.3)
                  : theme.colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isPro ? icon : Icons.lock_outline,
                color: isPro ? theme.colorScheme.primary : Colors.grey,
                size: 24,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProInfoDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary,
                Color.alphaBlend(
                  Colors.black.withOpacity(0.4),
                  theme.colorScheme.primary,
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1.5,
            ),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: const Icon(
                    Icons.workspace_premium,
                    color: Colors.white,
                    size: 56,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Column(
                    children: [
                      const Text(
                        'Beneficios Dev Retos PRO',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildProInfoItem(
                        Icons.all_inclusive,
                        'Práctica Ilimitada',
                        'Resuelve tantos retos de práctica como quieras.',
                      ),
                      _buildProInfoItem(
                        Icons.shield,
                        'Streak Shield Activado',
                        'Tu racha se protege automáticamente una vez por semana.',
                      ),
                      _buildProInfoItem(
                        Icons.star_outline,
                        'Funciones Exclusivas',
                        'Acceso prioritario a todas las funciones nuevas.',
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: theme.colorScheme.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            '¡ENTENDIDO!',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProInfoItem(IconData icon, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.greenAccent, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  sub,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
