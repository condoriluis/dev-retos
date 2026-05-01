import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:dev_retos/core/providers/guest_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/repositories/retos_repository.dart';
import '../../core/repositories/auth_repository.dart';
import '../../core/providers/countdown_provider.dart';
import '../../core/services/admob_service.dart';
import '../../core/widgets/scanner_loading.dart';
import '../../core/widgets/pro_paywall.dart';
import '../../core/widgets/incorrect_answer_dialog.dart';
import '../shared/widgets/code_viewer.dart';
import '../perfil/streak_details_view.dart';
import '../../core/services/security_service.dart';
import '../../core/widgets/solution_revealed_dialog.dart';
import '../../core/widgets/app_refresh_indicator.dart';

final attemptsProvider =
    FutureProvider.family<int, ({String challengeId, String userId})>((
      ref,
      params,
    ) async {
      final repo = ref.watch(retosRepositoryProvider);
      return repo.getChallengeAttempts(params.challengeId, params.userId);
    });

class DiarioScreen extends ConsumerStatefulWidget {
  const DiarioScreen({super.key});

  @override
  ConsumerState<DiarioScreen> createState() => _DiarioScreenState();
}

class _DiarioScreenState extends ConsumerState<DiarioScreen>
    with SingleTickerProviderStateMixin {
  final _answerController = TextEditingController();
  bool _isSubmitting = false;
  bool _isChallengeStarted = false;
  DateTime? _challengeStartTime;

  late Stopwatch _sessionStopwatch;
  Timer? _sessionTimer;
  String _elapsedTimeStr = "00:00";
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isSolutionVisible = false;
  String _correctAnswer = '';
  bool _usedHelp = false;

  final GlobalKey _globalKey = GlobalKey();
  bool _isSharing = false;
  bool _isTimerPaused = false;

  @override
  void initState() {
    super.initState();
    SecurityService.setSecureMode(true);
    _sessionStopwatch = Stopwatch();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Intentar reanudar reto si existe persistencia
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndResumeChallenge();
    });
  }

  Future<void> _checkAndResumeChallenge() async {
    final challenges = ref.read(dailyChallengesProvider).value;
    if (challenges != null && challenges.isNotEmpty) {
      final challenge = challenges.first;
      // Solo reanudar si NO está completado
      if (challenge['is_completed'] != true) {
        final prefs = await SharedPreferences.getInstance();
        final startTimeMs = prefs.getInt('challenge_start_${challenge['id']}');

        if (startTimeMs != null) {
          final startTime = DateTime.fromMillisecondsSinceEpoch(startTimeMs);
          setState(() {
            _challengeStartTime = startTime;
            _isChallengeStarted = true;
          });
          _startTimer();
        }
      }
    }
  }

  Future<void> _startChallenge() async {
    final challenges = ref.read(dailyChallengesProvider).value;
    if (challenges == null || challenges.isEmpty) return;

    final challengeId = challenges.first['id'];
    final now = DateTime.now();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'challenge_start_$challengeId',
      now.millisecondsSinceEpoch,
    );

    setState(() {
      _challengeStartTime = now;
      _isChallengeStarted = true;
    });
    _sessionStopwatch.start();
    _startTimer();
  }

  void _startTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _challengeStartTime == null) {
        timer.cancel();
        return;
      }
      if (_isTimerPaused) return;

      final duration = DateTime.now().difference(_challengeStartTime!);
      final minutes = duration.inMinutes.toString().padLeft(2, '0');
      final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
      setState(() {
        _elapsedTimeStr = "$minutes:$seconds";
      });
    });
  }

  void _showStreakDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const StreakDetailsScreen()),
    );
  }

  void _watchAdForExtraAttempt() async {
    final adMob = ref.read(adMobServiceProvider);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    if (!adMob.isAdLoaded) {
      adMob.loadRewardedAd();
      int attempts = 0;
      while (!adMob.isAdLoaded && attempts < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
      }
    }

    if (!mounted) return;

    final wasShown = adMob.showRewardedAd(
      onRewardEarned: () async {
        final user = ref.read(currentUserProvider);
        if (user == null) return;
        final repo = ref.read(retosRepositoryProvider);
        await repo.grantAdRewardTicket(user.id);

        ref.invalidate(userProfileProvider);

        // Reanudar temporizador si estaba pausado
        if (mounted) {
          setState(() {
            _isTimerPaused = false;
            // Ajustar el _challengeStartTime para no contar el tiempo que estuvo pausado
            // Opcionalmente, para simplificar, solo reanudamos el stopwatch
          });
          _sessionStopwatch.start();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Intento extra desbloqueado! 🎟️')),
        );
      },
      onAdClosed: () {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      },
    );

    if (!wasShown && mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // cerrar el loader

      final String reason = adMob.lastErrorCode == 3
          ? 'No hay anuncios disponibles (Código 3: No Fill). Esto es normal en apps nuevas o no publicadas.'
          : 'Error al cargar anuncio: ${adMob.lastErrorMessage} (Cod: ${adMob.lastErrorCode})';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _watchAdForAnswer(String challengeId) async {
    final adMob = ref.read(adMobServiceProvider);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    if (!adMob.isAdLoaded) {
      adMob.loadRewardedAd();
      int attempts = 0;
      while (!adMob.isAdLoaded && attempts < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
      }
    }

    if (!mounted) return;

    final wasShown = adMob.showRewardedAd(
      onRewardEarned: () async {
        final repo = ref.read(retosRepositoryProvider);
        final answer = await repo.getCorrectAnswer(challengeId);

        if (mounted && answer != null) {
          setState(() {
            _correctAnswer = answer;
            _isSolutionVisible = true;
            _usedHelp = true;
            _answerController.text = answer;
          });
          SolutionRevealedDialog.show(context);
        }
      },
      onAdClosed: () {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      },
    );

    if (!wasShown && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El anuncio no está disponible. Reintenta en breve.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _revealSolutionInstantly(String challengeId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final repo = ref.read(retosRepositoryProvider);
    final answer = await repo.getCorrectAnswer(challengeId);

    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    if (mounted && answer != null) {
      setState(() {
        _correctAnswer = answer;
        _isSolutionVisible = true;
        _usedHelp = true;
        _answerController.text = answer;
      });
      SolutionRevealedDialog.show(context);
    }
  }

  @override
  void dispose() {
    SecurityService.setSecureMode(false);
    _answerController.dispose();
    _sessionTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _showXPInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final size = MediaQuery.sizeOf(context);
        final isWide = size.width > 600;
        final horizontalGap = (size.width * 0.07).clamp(20.0, 40.0);

        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide ? 500 : double.infinity,
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      theme.colorScheme.primary.withOpacity(0.08),
                      theme.colorScheme.surface,
                    ),
                    Color.alphaBlend(
                      theme.colorScheme.primary.withOpacity(0.18),
                      theme.colorScheme.surface,
                    ),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                  width: 1.2,
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                horizontalGap,
                12,
                horizontalGap,
                MediaQuery.of(context).padding.bottom + 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(
                          0.3,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.amber.withOpacity(0.2),
                          ),
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          color: Colors.amber,
                          size: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '¿Cómo funciona el XP?',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: (size.width * 0.05).clamp(20.0, 24.0),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'El XP ganado contribuye a tu ranking global y racha de aprendizaje.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildXPSection(
                    context,
                    icon: Icons.today_rounded,
                    title: 'Reto Diario',
                    resolvedXP: '100 - 290 XP',
                    failedXP: '0 XP',
                    iconColor: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  _buildXPSection(
                    context,
                    icon: Icons.science_rounded,
                    title: 'Sesión de Práctica',
                    resolvedXP: '25 - 72 XP',
                    failedXP: '0 XP',
                    iconColor: theme.colorScheme.secondary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildXPSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String resolvedXP,
    required String failedXP,
    required Color iconColor,
  }) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final responsivePadding = (width * 0.05).clamp(16.0, 24.0);

    return Container(
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: iconColor.withOpacity(0.2), width: 1.0),
      ),
      padding: EdgeInsets.all(responsivePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildXPItem(
                  context,
                  'Resuelto',
                  resolvedXP,
                  Colors.green,
                ),
              ),
              Container(
                width: 1.5,
                height: 40,
                color: theme.colorScheme.outlineVariant.withOpacity(0.3),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: responsivePadding),
                  child: _buildXPItem(
                    context,
                    'Fallido',
                    failedXP,
                    theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildXPItem(
    BuildContext context,
    String label,
    String value,
    Color dotColor,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final theme = Theme.of(context);
            final sessionsAsync = ref.watch(dailySessionsProvider);
            final userAsync = ref.watch(userProfileProvider);
            final user = userAsync.value;
            final bool isPro =
                user?['is_pro'] == true ||
                user?['is_pro'] == 1 ||
                user?['is_pro']?.toString() == '1' ||
                user?['is_pro']?.toString() == 'true';

            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      theme.colorScheme.primary.withOpacity(0.08),
                      theme.colorScheme.surface,
                    ),
                    Color.alphaBlend(
                      theme.colorScheme.primary.withOpacity(0.18),
                      theme.colorScheme.surface,
                    ),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                  width: 1.2,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(
                          0.3,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.history_rounded,
                              color: theme.colorScheme.primary,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'Historial de Retos',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Flexible(
                    child: sessionsAsync.when(
                      data: (sessions) {
                        if (sessions.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text(
                                'Aún no tienes historial de retos.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shrinkWrap: true,
                          itemCount: sessions.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final session = sessions[index];
                            final isLocked = !isPro && index >= 3;
                            final sessionNumber = sessions.length - index;

                            return _buildHistoryCard(
                              context,
                              session,
                              number: sessionNumber,
                              isLocked: isLocked,
                            );
                          },
                        );
                      },
                      loading: () => SizedBox(
                        height: MediaQuery.of(context).size.height * 0.65,
                        child: const Center(child: ScannerLoading()),
                      ),
                      error: (err, _) => Text('Error: $err'),
                    ),
                  ),
                  if (!isPro) ...[
                    const SizedBox(height: 32),
                    // PRO CTA
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withOpacity(
                          0.2,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: theme.colorScheme.primary.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Desbloquea retos pasados y completa tu calendario',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 45,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                ProPaywall.show(context);
                              },
                              child: const Text(
                                'SER PRO',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryCard(
    BuildContext context,
    Map<String, dynamic> session, {
    required int number,
    required bool isLocked,
  }) {
    final theme = Theme.of(context);
    final tech = session['technology'] ?? 'Otro';
    final isSuccess = session['is_success'] == 1;
    final attempts = session['attempts'] ?? 1;

    // Formatear Fecha
    String formattedDate = '...';
    try {
      final dt = DateTime.parse(session['completed_at']);
      formattedDate = DateFormat('yyyy-MM-dd').format(dt);
    } catch (_) {}

    // Formatear Duración (00:45)
    final totalSecs = session['time_taken_seconds'] ?? 0;
    final mins = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSecs % 60).toString().padLeft(2, '0');
    final durationStr = '$mins:$secs';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: ImageFiltered(
        imageFilter: isLocked
            ? ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5)
            : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: Opacity(
          opacity: isLocked ? 0.7 : 1.0,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '#$number',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session['title'] ?? 'Reto',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${session['level']} • $tech',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: attempts > 3
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: theme.colorScheme.primary
                                          .withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isSuccess
                                            ? Icons.check_circle
                                            : Icons.cancel,
                                        size: 10,
                                        color: isSuccess
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$attempts Intentos',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: theme.colorScheme.primary,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                )
                              : Wrap(
                                  spacing: 3,
                                  runSpacing: 3,
                                  children: List.generate(attempts, (index) {
                                    final isLast = index == attempts - 1;
                                    final color = (isLast && isSuccess)
                                        ? Colors.green
                                        : Colors.grey.withOpacity(0.5);
                                    return Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    );
                                  }),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$formattedDate . $durationStr',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(
                          0.7,
                        ),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isSuccess ? Icons.check_circle : Icons.cancel,
                color: isSuccess ? Colors.green : Colors.red,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitAnswer(String challengeId) async {
    final answer = _answerController.text;
    if (answer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, escribe una respuesta primero.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    // Resolver ID de usuario (Real o Invitado)
    final userData = ref.read(userProfileProvider).value;
    final guestId = ref.read(guestIdProvider);
    final userId = userData != null ? userData['id'] : guestId;

    if (userId == null) {
      setState(() => _isSubmitting = false);
      return;
    }

    final elapsedSeconds = _sessionStopwatch.elapsed.inSeconds;
    final repo = ref.read(retosRepositoryProvider);
    final result = await repo.submitAnswer(
      challengeId,
      answer,
      userId,
      elapsedSeconds,
      usedHelp: _usedHelp,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.isCorrect) {
      _sessionStopwatch.stop();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('challenge_start_$challengeId');

      ref.invalidate(userProfileProvider);
      ref.invalidate(userStatsProvider);
      ref.invalidate(userSessionsProvider);
      ref.invalidate(dailySessionsProvider);
      ref.invalidate(weeklyProgressProvider);
      ref.invalidate(globalRankingProvider);
      ref.invalidate(dailyRankingProvider);
      ref.invalidate(
        attemptsProvider((challengeId: challengeId, userId: userId)),
      );
      ref.invalidate(dailyChallengesProvider);
      _answerController.clear();
    } else {
      final currentAttempts =
          ref
              .read(
                attemptsProvider((challengeId: challengeId, userId: userId)),
              )
              .value ??
          0;
      final remaining = 3 - (currentAttempts + 1);

      if (remaining <= 0) {
        _sessionStopwatch.stop();
        setState(() {
          _isTimerPaused = true;
        });
      }

      ref.invalidate(
        attemptsProvider((challengeId: challengeId, userId: userId)),
      );

      IncorrectAnswerDialog.show(context, remaining);
    }
  }

  Future<void> _abandonChallenge(String challengeId) async {
    final userData = ref.read(userProfileProvider).value;
    final guestId = ref.read(guestIdProvider);
    final userId = userData != null ? userData['id'] : guestId;

    if (userId == null) return;

    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(retosRepositoryProvider);
    _sessionStopwatch.stop();
    final elapsedSeconds = _sessionStopwatch.elapsed.inSeconds;
    setState(() {
      _isChallengeStarted = false;
    });
    _sessionStopwatch.reset();
    _answerController.clear();

    try {
      await repo.abandonChallenge(challengeId, userId, elapsedSeconds);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('challenge_start_$challengeId');

      container.invalidate(userProfileProvider);
      container.invalidate(userStatsProvider);
      container.invalidate(userSessionsProvider);
      container.invalidate(dailySessionsProvider);
      container.invalidate(weeklyProgressProvider);
      container.invalidate(globalRankingProvider);
      container.invalidate(dailyRankingProvider);
      container.invalidate(
        attemptsProvider((challengeId: challengeId, userId: userId)),
      );
      container.invalidate(dailyChallengesProvider);
    } catch (e) {
      debugPrint('Error silent abandon (diario): $e');
    }
  }

  Future<bool> _showAbandonConfirmationDialog(String? challengeId) async {
    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(
                    theme.colorScheme.primary.withOpacity(0.08),
                    theme.colorScheme.surface,
                  ),
                  Color.alphaBlend(
                    theme.colorScheme.primary.withOpacity(0.18),
                    theme.colorScheme.surface,
                  ),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    color: Colors.orange,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '¿Abandonar reto?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Si abandonas ahora, el reto se marcará como fallido y podrías perder tu racha de días.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'ME QUEDO',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          if (challengeId != null) {
                            _abandonChallenge(challengeId);
                          }
                          Navigator.pop(ctx, true);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'ABANDONAR',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  Future<void> _shareResultImage() async {
    if (_isSharing) return;

    setState(() => _isSharing = true);

    try {
      await Future.delayed(const Duration(milliseconds: 100));

      final boundary =
          _globalKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null)
        throw Exception('No se pudo encontrar el render boundary');

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null)
        throw Exception('No se pudo convertir la imagen a bytes');

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final directory = await getTemporaryDirectory();
      final imagePath = '${directory.path}/dev-retos-resultado.png';

      final file = File(imagePath);
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(imagePath)],
        text:
            '¡He completado mi Reto Diario en Dev Retos 🚀! ¿Crees que puedas superar mi tiempo y racha?',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al compartir: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  void _showShieldActivatedDialog(String userId) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF004D40), // Teal/Verde muy profundo
                  Color(0xFF00241B), // Casi negro verdoso
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
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shield,
                    color: Colors.greenAccent,
                    size: 50,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '¡Racha Protegida!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 10),
                RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.5,
                    ),
                    children: [
                      TextSpan(text: 'Ayer no completaste tu reto, pero tu '),
                      TextSpan(
                        text: 'Streak Shield PRO',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      TextSpan(text: ' ha evitado que pierdas tu racha.'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ref.read(retosRepositoryProvider).acknowledgeShield(userId);
                    ref.invalidate(userProfileProvider);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF004D40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 25,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'ENTENDIDO',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleRefresh() async {
    ref.invalidate(dailyChallengesProvider);
    ref.invalidate(userProfileProvider);

    final challenges = ref.read(dailyChallengesProvider).value;
    final user = ref.read(currentUserProvider);
    final guestId = ref.read(guestIdProvider);
    final userId = user?.id ?? guestId;

    if (challenges != null && challenges.isNotEmpty) {
      ref.invalidate(
        attemptsProvider((challengeId: challenges.first['id'], userId: userId)),
      );
    }

    await Future.wait([
      ref.read(dailyChallengesProvider.future),
      ref.read(userProfileProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final challengesAsync = ref.watch(dailyChallengesProvider);
    ref.watch(countdownProvider);
    final userAsync = ref.watch(userProfileProvider);

    ref.listen<AsyncValue<dynamic>>(userProfileProvider, (previous, next) {
      if (next.hasValue && next.value != null) {
        final user = next.value!;
        if (user['notified_shield'] == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showShieldActivatedDialog(user['id']);
            }
          });
        }
      }
    });

    bool isChallengeActive = false;
    String? currentChallengeId;
    if (challengesAsync.hasValue &&
        challengesAsync.value != null &&
        challengesAsync.value!.isNotEmpty) {
      final challenge = challengesAsync.value!.first;
      final bool isCompleted = challenge['is_completed'] == true;
      if (_isChallengeStarted && !isCompleted) {
        isChallengeActive = true;
        currentChallengeId = challenge['id'];
      }
    }

    return PopScope(
      canPop: !isChallengeActive,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final bool shouldPop = await _showAbandonConfirmationDialog(
          currentChallengeId,
        );
        if (shouldPop && mounted) {
          // En el diario, el reto es una vista interna, no una pantalla aparte.
          // Por lo tanto, no hacemos pop del Navigator, sino que reseteamos el estado local.
          setState(() => _isChallengeStarted = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: userAsync.when(
            data: (user) {
              final xp = user?['xp'] ?? 0;
              final streak = user?['current_streak'] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _showXPInfo,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.amber.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.bolt_rounded,
                              color: Colors.amber,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$xp',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _showStreakDetails,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_fire_department_rounded,
                              color: Colors.orange,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$streak',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          centerTitle: false,
          actions: [
            SizedBox(
              height: 32,
              child: FilledButton.icon(
                onPressed: _showHistory,
                icon: const Icon(Icons.history_rounded, size: 18),
                label: const Text(
                  'Historial',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: AppRefreshIndicator(
          onRefresh: _handleRefresh,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabecera de racha
                userAsync.when(
                  data: (user) {
                    final challenges = challengesAsync.value ?? [];
                    final bool isCompleted =
                        challenges.isNotEmpty &&
                        (challenges.first['is_completed'] == true);
                    final bool isAbandoned =
                        challenges.isNotEmpty &&
                        (challenges.first['is_abandoned'] == true);

                    if (!isCompleted) return const SizedBox.shrink();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            isAbandoned
                                ? '¡Reto Fallado!'
                                : '¡Ya lo conseguiste hoy!',
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isAbandoned
                                  ? theme.colorScheme.error
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAbandoned
                                ? 'Vuelve mañana para intentarlo de nuevo.'
                                : 'Vuelve mañana para un nuevo desafío.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: isAbandoned
                                  ? theme.colorScheme.error
                                  : Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                challengesAsync.when(
                  loading: () => const ScannerLoading(),
                  error: (err, stack) => Center(child: Text('Error: $err')),
                  data: (challenges) {
                    if (challenges.isEmpty)
                      return const Center(
                        child: Text('No hay retos para hoy.'),
                      );

                    final challengeData = challenges.first;
                    final userData = userAsync.value;
                    final bool isGuest = ref.watch(currentUserProvider) == null;
                    final String currentUserId = isGuest
                        ? ref.watch(guestIdProvider)
                        : (userData?['id'] ?? '');

                    final attemptsAsync = ref.watch(
                      attemptsProvider((
                        challengeId: challengeData['id'],
                        userId: currentUserId,
                      )),
                    );

                    final bool isCompleted =
                        challengeData['is_completed'] == true;

                    return Column(
                      children: [
                        if (!_isChallengeStarted && !isCompleted)
                          _buildChallengeIntro(theme, textTheme),

                        if (_isChallengeStarted && !isCompleted) ...[
                          _buildChallengeContent(
                            theme,
                            textTheme,
                            challengeData,
                          ),
                          const SizedBox(height: 20),
                          _buildChallengeInput(
                            theme,
                            textTheme,
                            challengeData,
                            attemptsAsync,
                            userAsync,
                          ),
                        ],

                        if (isCompleted)
                          _buildSuccessView(
                            theme,
                            textTheme,
                            challengeData,
                            attemptsAsync,
                            userAsync,
                          ),

                        if (isGuest) ...[
                          const SizedBox(height: 8),
                          _buildGuestConversionCTA(theme, textTheme),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- COMPONENTES DE UI ---

  Widget _buildChallengeIntro(ThemeData theme, TextTheme textTheme) {
    return Column(
      children: [
        const SizedBox(height: 0),
        Icon(
          Icons.rocket_launch_rounded,
          size: 80,
          color: theme.colorScheme.primary.withOpacity(0.8),
        ),
        const SizedBox(height: 24),
        Text(
          '¡El reto de hoy está listo!',
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Pon a prueba tu instinto de código.\n¿Qué tan rápido puedes resolverlo?',
            style: textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 48),
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: FilledButton.icon(
              onPressed: _startChallenge,
              icon: const Icon(Icons.play_arrow_rounded, size: 28),
              label: const Text(
                'INICIAR RETO',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildChallengeContent(
    ThemeData theme,
    TextTheme textTheme,
    dynamic challengeData,
  ) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "NIVEL: ${challengeData['level']}",
                style: textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: () => _confirmShowSolution(challengeData['id']),
              icon: Icon(
                _isSolutionVisible ? Icons.lightbulb : Icons.lightbulb_outline,
                color: _isSolutionVisible
                    ? Colors.amber
                    : Colors.amber.withOpacity(0.6),
              ),
              tooltip: 'Ver solución',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          challengeData['question'] ?? '',
          style: textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        CodeViewer(
          code: challengeData['code_snippet'] ?? '',
          technology: challengeData['technology'] ?? 'Código',
        ),
        if (_isSolutionVisible) ...[
          const SizedBox(height: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lightbulb, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'SOLUCIÓN REVELADA',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _correctAnswer,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Nota: Ganarás XP reducido tras usar la ayuda.',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _confirmShowSolution(String challengeId) {
    if (_isSolutionVisible) return;

    final userAsync = ref.read(userProfileProvider);
    final user = userAsync.value;
    final bool isPro =
        user?['is_pro'] == true ||
        user?['is_pro'] == 1 ||
        user?['is_pro']?.toString() == '1' ||
        user?['is_pro']?.toString() == 'true';

    if (isPro) {
      _revealSolutionInstantly(challengeId);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Ver Solución?'),
        content: const Text(
          'Mira un anuncio recompensado para revelar la respuesta. Al usar la ayuda ganarás un máximo de 10 XP.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _watchAdForAnswer(challengeId);
            },
            child: const Text('VER ANUNCIO'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestConversionCTA(ThemeData theme, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Quieres guardar tu racha?',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Inicia sesión para proteger tu progreso y estadísticas.',
                  style: textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: () => context.push('/login'),
            style: TextButton.styleFrom(
              backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'INICIAR SESIÓN',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengeInput(
    ThemeData theme,
    TextTheme textTheme,
    dynamic challengeData,
    AsyncValue<int> attemptsAsync,
    AsyncValue<dynamic> userAsync,
  ) {
    final bool isPro = userAsync.value?['is_pro'] == 1;

    return Column(
      children: [
        TextField(
          controller: _answerController,
          decoration: InputDecoration(
            hintText: 'Escribe tu respuesta...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: Colors.greenAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _elapsedTimeStr,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            () {
              final count =
                  attemptsAsync.value ?? (challengeData['attempts'] ?? 0);
              final tickets = userAsync.value?['reward_tickets'] ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: count >= 3
                      ? Colors.orange.withOpacity(0.1)
                      : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: count >= 3 ? Colors.orange : Colors.blue,
                  ),
                ),
                child: Text(
                  isPro
                      ? 'Intentos: Ilimitados ♾️'
                      : 'Intentos: $count/3${count >= 3 && tickets > 0 ? " (+1 Extra 🎟️)" : ""}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isPro
                        ? Colors.amber
                        : (count >= 3 ? Colors.orange : Colors.blue),
                  ),
                ),
              );
            }(),
          ],
        ),
        const SizedBox(height: 24),
        () {
          final count = attemptsAsync.value ?? (challengeData['attempts'] ?? 0);
          final tickets = userAsync.value?['reward_tickets'] ?? 0;
          final bool canTryAgain = count < 3 || tickets > 0 || isPro;

          if (!canTryAgain) {
            return Column(
              children: [
                const Text(
                  'Has agotado tus intentos gratuitos.',
                  style: TextStyle(color: Colors.orange),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _watchAdForExtraAttempt,
                    icon: const Icon(Icons.play_circle_fill),
                    label: const Text('VER ANUNCIO PARA +1 INTENTO'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () => _abandonChallenge(challengeData['id']),
                    icon: const Icon(Icons.close_rounded, color: Colors.grey),
                    label: const Text(
                      'TERMINAR RETO',
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.withOpacity(0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          return ValueListenableBuilder<TextEditingValue>(
            valueListenable: _answerController,
            builder: (context, value, child) {
              final bool isEmpty = value.text.trim().isEmpty;
              return SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: (_isSubmitting || isEmpty)
                      ? null
                      : () => _submitAnswer(challengeData['id']),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'ENVIAR',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              );
            },
          );
        }(),
      ],
    );
  }

  Widget _buildSuccessView(
    ThemeData theme,
    TextTheme textTheme,
    dynamic challengeData,
    AsyncValue<int> attemptsAsync,
    AsyncValue<dynamic> userAsync,
  ) {
    final bool isAbandoned = challengeData['is_abandoned'] == true;

    return Column(
      children: [
        RepaintBoundary(
          key: _globalKey,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isAbandoned
                          ? theme.colorScheme.error.withOpacity(0.5)
                          : theme.colorScheme.outlineVariant.withOpacity(0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (isAbandoned)
                        () {
                          final count = challengeData['attempts'] ?? 0;
                          final timeTaken = challengeData['time_taken'] ?? 0;
                          final m = (timeTaken / 60).floor().toString().padLeft(
                            2,
                            '0',
                          );
                          final s = (timeTaken % 60).toString().padLeft(2, '0');
                          return Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildMinimalStat(
                                      'TU TIEMPO',
                                      "$m:$s",
                                      Icons.timer_outlined,
                                      isAbandoned ? Colors.grey : Colors.blue,
                                    ),
                                  ),
                                  Container(
                                    height: 40,
                                    width: 1,
                                    color: Colors.white10,
                                  ),
                                  Expanded(
                                    child: _buildMinimalStat(
                                      'INTENTOS USADOS',
                                      '$count',
                                      isAbandoned
                                          ? Icons.cancel_outlined
                                          : Icons.check_circle_outline,
                                      isAbandoned
                                          ? theme.colorScheme.error
                                          : Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(count, (index) {
                                  final isLast = index == count - 1;
                                  return Container(
                                    width: 20,
                                    height: 20,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 2.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isLast
                                          ? (isAbandoned
                                                ? Colors.white24
                                                : Colors.green)
                                          : Colors.white24,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          );
                        }(),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          challengeData['level'].toString().toUpperCase(),
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (userAsync.value != null) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GestureDetector(
                      onTap: _showStreakDetails,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.cyan.shade900.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.cyan.shade400.withOpacity(0.3),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.local_fire_department,
                                color: Colors.orange,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Racha de ${userAsync.value?['current_streak'] ?? 0} días',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.cyan.shade400,
                                        ),
                                  ),
                                  Text(
                                    '¡No la pierdas!',
                                    style: TextStyle(
                                      color: Colors.cyan.shade600,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildSuccessFooter(theme, userAsync),
      ],
    );
  }

  Widget _buildSuccessFooter(ThemeData theme, AsyncValue<dynamic> userAsync) {
    final countdownAsync = ref.watch(countdownProvider);
    return Column(
      children: [
        ScaleTransition(
          scale: _pulseAnimation,
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isSharing ? null : _shareResultImage,
              icon: _isSharing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.share_rounded),
              label: Text(
                _isSharing ? 'GENERANDO...' : 'COMPARTIR RESULTADO',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 1.1,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildNextChallengeCountdown(theme, countdownAsync.value),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => context.go('/practica'),
          icon: const Icon(Icons.rocket_launch_rounded),
          label: const Text(
            'PRACTICAR AHORA',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1.2,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.primary,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          ),
        ),
      ],
    );
  }

  Widget _buildNextChallengeCountdown(ThemeData theme, String? countdown) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.timer_outlined,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'Siguiente en: ${countdown ?? '--:--:--'}',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
              fontWeight: FontWeight.w500,
              fontSize: 14,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color == Colors.grey ? Colors.grey : Colors.white,
            fontSize: 24,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
