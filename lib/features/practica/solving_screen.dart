import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dev_retos/core/providers/guest_provider.dart';
import 'package:dev_retos/core/repositories/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/repositories/retos_repository.dart';
import '../../core/services/ai_challenge_service.dart';
import '../../core/services/admob_service.dart';
import '../shared/widgets/code_viewer.dart';
import '../../core/widgets/pro_paywall.dart';
import '../../core/services/security_service.dart';
import '../../core/widgets/incorrect_answer_dialog.dart';
import '../../core/widgets/solution_revealed_dialog.dart';

class SolvingScreen extends ConsumerStatefulWidget {
  final String technology;
  final String level;
  final String? challengeId;

  const SolvingScreen({
    super.key,
    required this.technology,
    required this.level,
    this.challengeId,
  });

  @override
  ConsumerState<SolvingScreen> createState() => _SolvingScreenState();
}

class _SolvingScreenState extends ConsumerState<SolvingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Map<String, dynamic>? _challenge;
  bool _isLoading = true;
  bool _isCheckingAccess = true;
  bool _canPlay = false;
  final _answerController = TextEditingController();
  bool _isSubmitting = false;
  bool _isSolutionVisible = false;
  String _correctAnswer = '';
  bool _usedHelp = false;
  bool _isSuccess = false;
  bool _isFailure = false;
  int _xpEarned = 0;
  int _timeTaken = 0;

  // Lógica de competitividad
  int _attempts = 0;
  DateTime? _startTime;
  Timer? _uiTimer;
  static const int _maxAttempts = 3;
  int _accumulatedSeconds = 0;
  DateTime? _activeStartTime;

  final GlobalKey _globalKey = GlobalKey();
  bool _isSharing = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SecurityService.setSecureMode(true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAccessAndFetch();
    });
  }

  Future<void> _checkAccessAndFetch() async {
    final user = ref.read(currentUserProvider);
    final guestId = ref.read(guestIdProvider);
    final userId = user?.id ?? guestId;

    final repo = ref.read(retosRepositoryProvider);

    setState(() => _isCheckingAccess = true);
    final hasAccess = await repo.canUserPlayChallenge(userId);

    if (!mounted) return;

    if (!hasAccess) {
      setState(() {
        _isCheckingAccess = false;
        _canPlay = false;
      });
      return;
    }

    setState(() {
      _isCheckingAccess = false;
      _canPlay = true;
    });

    _fetchChallenge();
  }

  Future<void> _fetchChallenge() async {
    final repo = ref.read(retosRepositoryProvider);
    final aiService = ref.read(aiChallengeServiceProvider);

    setState(() => _isLoading = true);

    final user = ref.read(currentUserProvider);
    final guestId = ref.read(guestIdProvider);
    final userId = user?.id ?? guestId;

    Map<String, dynamic>? result;

    if (widget.challengeId != null) {
      result = await repo.getChallengeById(widget.challengeId!);
    } else {
      result = await repo.getOrGeneratePracticeChallenge(
        widget.technology,
        widget.level,
        userId,
        aiService,
      );
    }

    if (mounted) {
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Límites de IA excedidos o red sin respuesta.'),
          ),
        );
        Navigator.pop(context);
      } else {
        setState(() {
          _challenge = result;
          _isLoading = false;
        });
        // Una vez que el reto está listo, manejamos el tiempo
        _initTimer();
      }
    }
  }

  Future<void> _initTimer() async {
    if (_challenge == null) return;
    final prefs = await SharedPreferences.getInstance();
    final String key = 'practice_accum_${_challenge!['id']}';

    _accumulatedSeconds = prefs.getInt(key) ?? 0;
    _startTime = DateTime.now(); // flag to indicate timer is running
    _activeStartTime = DateTime.now();

    // Iniciar el temporizador de la interfaz
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _clearTimer() async {
    if (_challenge == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('practice_accum_${_challenge!['id']}');
    await prefs.remove(
      'practice_start_${_challenge!['id']}',
    ); // Clean up old keys
  }

  int _getElapsedTime() {
    if (_startTime == null) return 0;
    int currentActive = 0;
    if (_activeStartTime != null) {
      currentActive = DateTime.now().difference(_activeStartTime!).inSeconds;
    }
    return _accumulatedSeconds + currentActive;
  }

  String _getFormattedTime() {
    final seconds = _getElapsedTime();
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _submitAnswer() async {
    final answer = _answerController.text;
    if (answer.isEmpty) return;

    final user = ref.read(currentUserProvider);
    final guestId = ref.read(guestIdProvider);
    final userId = user?.id ?? guestId;

    setState(() => _isSubmitting = true);
    final repo = ref.read(retosRepositoryProvider);

    final int timeTaken = _getElapsedTime();

    final result = await repo.submitAnswer(
      _challenge!['id'],
      answer,
      userId,
      timeTaken,
      usedHelp: _usedHelp,
      knownAnswer: _challenge!['correct_answer']?.toString(),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.isCorrect) {
      _uiTimer?.cancel();
      await _clearTimer();

      ref.invalidate(userProfileProvider);
      ref.invalidate(userStatsProvider);
      ref.invalidate(userSessionsProvider);
      ref.invalidate(practiceSessionsProvider);
      ref.invalidate(weeklyProgressProvider);
      ref.invalidate(globalRankingProvider);
      ref.invalidate(dailyRankingProvider);

      setState(() {
        _isSuccess = true;
        _xpEarned = result.xpEarned;
        _timeTaken = timeTaken;
      });
    } else {
      final user = ref.read(userProfileProvider).value;
      final isPro =
          user?['is_pro'] == true ||
          user?['is_pro'] == 1 ||
          user?['is_pro']?.toString() == '1';

      setState(() {
        _attempts++;
      });

      if (!isPro && _attempts >= _maxAttempts) {
        _uiTimer?.cancel();
        await _clearTimer();
        setState(() {
          _isFailure = true;
          _timeTaken = timeTaken;
        });
      } else {
        // Si es PRO, pasamos un número negativo o muy alto para que el diálogo sepa que es infinito
        IncorrectAnswerDialog.show(
          context,
          isPro ? -1 : (_maxAttempts - _attempts),
        );
      }
    }
  }

  Widget _buildSuccessView(ThemeData theme, TextTheme textTheme, bool isPro) {
    final m = (_timeTaken ~/ 60).toString().padLeft(2, '0');
    final s = (_timeTaken % 60).toString().padLeft(2, '0');
    final attemptsUsed = _attempts + 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          RepaintBoundary(
            key: _globalKey,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
              child: Column(
                children: [
                  // ── Header ──
                  Text(
                    'Práctica Completada',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.greenAccent,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '¡Buen trabajo! Descifraste el código.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // ── XP Card ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.amber.withOpacity(0.15),
                          Colors.orange.withOpacity(0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.withOpacity(0.4)),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            color: Colors.amber,
                            size: 36,
                          ),
                          const SizedBox(width: 8),
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '+$_xpEarned ',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.amber,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                TextSpan(
                                  text: 'XP GANADOS',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.withOpacity(0.8),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Stats Card ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withOpacity(
                          0.5,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildStat(
                                'TU TIEMPO',
                                '$m:$s',
                                Icons.timer_outlined,
                                Colors.blue,
                              ),
                            ),
                            Container(
                              height: 40,
                              width: 1,
                              color: Colors.white10,
                            ),
                            Expanded(
                              child: _buildStat(
                                'INTENTOS',
                                isPro ? '∞' : '$attemptsUsed',
                                Icons.check_circle_outline,
                                isPro ? Colors.amber : Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Cuadrados de intentos o infinito
                        if (isPro)
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.all_inclusive,
                                color: Colors.amber,
                                size: 24,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'MODO PRÁCTICA PRO',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(attemptsUsed, (i) {
                              final isLast = i == attemptsUsed - 1;
                              return Container(
                                width: 20,
                                height: 20,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: isLast ? Colors.green : Colors.white24,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              );
                            }),
                          ),
                        const SizedBox(height: 16),
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
                            (_challenge?['level'] ?? '')
                                .toString()
                                .toUpperCase(),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),

          // ── Botón Compartir ──
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
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'HECHO',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
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

  Widget _buildFailureView(ThemeData theme, TextTheme textTheme, bool isPro) {
    final m = (_timeTaken ~/ 60).toString().padLeft(2, '0');
    final s = (_timeTaken % 60).toString().padLeft(2, '0');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          // ── Header ──
          const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 72),
          const SizedBox(height: 12),
          Text(
            '¡Sigue Practicando!',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Agotaste los 3 intentos. Cada fallo es un paso más hacia el dominio.',
            style: textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // ── Stats Card ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildStat(
                        'TU TIEMPO',
                        '$m:$s',
                        Icons.timer_outlined,
                        Colors.blue,
                      ),
                    ),
                    Container(height: 40, width: 1, color: Colors.white10),
                    Expanded(
                      child: _buildStat(
                        'INTENTOS',
                        isPro ? '∞' : '$_maxAttempts',
                        Icons.close_rounded,
                        isPro ? Colors.amber : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Mostrar progreso o infinito
                if (isPro)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.all_inclusive, color: Colors.amber, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'MODO PRÁCTICA PRO',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_maxAttempts, (i) {
                      return Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    (_challenge?['level'] ?? '').toString().toUpperCase(),
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Botón Volver ──
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text(
                'VOLVER',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 1.1,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: const Icon(Icons.rocket_launch_rounded),
            label: const Text(
              'INTENTAR OTRO',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SecurityService.setSecureMode(false);
    _uiTimer?.cancel();
    _answerController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_activeStartTime != null) {
        _accumulatedSeconds += DateTime.now()
            .difference(_activeStartTime!)
            .inSeconds;
        _activeStartTime = null;
        if (_challenge != null) {
          SharedPreferences.getInstance().then((prefs) {
            prefs.setInt(
              'practice_accum_${_challenge!['id']}',
              _accumulatedSeconds,
            );
          });
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_startTime != null) {
        _activeStartTime = DateTime.now();
      }
    }
  }

  void _watchAdForTicket() async {
    final adMob = ref.read(adMobServiceProvider);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            const Text('Cargando anuncio...'),
          ],
        ),
      ),
    );

    // Esperar si el anuncio aún no está cargado (máximo 5 segundos)
    if (!adMob.isAdLoaded) {
      adMob.loadRewardedAd();
      int attempts = 0;
      while (!adMob.isAdLoaded && attempts < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
      }
    }

    if (mounted)
      Navigator.of(context, rootNavigator: true).pop(); // Cerrar diálogo

    final wasShown = adMob.showRewardedAd(
      onRewardEarned: () async {
        final user = ref.read(currentUserProvider);
        final guestId = ref.read(guestIdProvider);
        final userId = user?.id ?? guestId;

        final repo = ref.read(retosRepositoryProvider);
        await repo.grantAdRewardTicket(userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Excelente! Has ganado una práctica extra.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      },
      onAdClosed: () {
        _checkAccessAndFetch();
      },
    );

    if (!wasShown && mounted) {
      final String reason = adMob.lastErrorCode == 3
          ? 'No hay anuncios disponibles (Código 3: No Fill). Esto es normal en apps nuevas o emuladores.'
          : 'Error al mostrar anuncio: ${adMob.lastErrorMessage} (Cod: ${adMob.lastErrorCode})';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _confirmShowSolution() {
    if (_isSolutionVisible || _challenge == null) return;

    final userAsync = ref.read(userProfileProvider);
    final user = userAsync.value;
    final bool isPro =
        user?['is_pro'] == true ||
        user?['is_pro'] == 1 ||
        user?['is_pro']?.toString() == '1' ||
        user?['is_pro']?.toString() == 'true';

    if (isPro) {
      _revealSolutionInstantly();
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
              _watchAdForAnswer();
            },
            child: const Text('VER ANUNCIO'),
          ),
        ],
      ),
    );
  }

  void _watchAdForAnswer() async {
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

    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    if (!mounted) return;

    final wasShown = adMob.showRewardedAd(
      onRewardEarned: () async {
        final repo = ref.read(retosRepositoryProvider);
        final answer = await repo.getCorrectAnswer(_challenge!['id']);

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
        // No necesitamos hacer nada especial al cerrar
      },
    );

    if (!wasShown && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El anuncio no está disponible. Reintenta en breve.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _revealSolutionInstantly() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final repo = ref.read(retosRepositoryProvider);
    final answer = await repo.getCorrectAnswer(_challenge!['id']);

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final userProfile = ref.watch(userProfileProvider).value;
    final isPro =
        userProfile?['is_pro'] == true ||
        userProfile?['is_pro'] == 1 ||
        userProfile?['is_pro']?.toString() == '1';

    if (_isCheckingAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('Comprobando Acceso...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_canPlay) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        extendBodyBehindAppBar: true,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.colorScheme.primary.withOpacity(0.05),
                theme.colorScheme.surface,
              ],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 32.0,
                vertical: 24.0,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icono Animado / Estilizado
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 120,
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Icon(
                        Icons.bolt_rounded,
                        size: 80,
                        color: Colors.amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Límite Diario Alcanzado',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Has usado todas las prácticas gratuitas de hoy. Suscríbete para acceso ilimitado o mira un anuncio para desbloquear una más.',
                    style: textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Botón PRO con Gradiente
                  Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFFD700),
                          Color(0xFFFFA500),
                        ], // Gold Gradient
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () => ProPaywall.show(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'SUSCRIBIRSE PARA ILIMITADO',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Botón Anuncio
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _watchAdForTicket,
                      icon: const Icon(Icons.play_circle_filled_rounded),
                      label: const Text('VER ANUNCIO POR UNA MÁS'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: theme.colorScheme.outline.withOpacity(0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Quizás más tarde',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Práctica: ${widget.technology}')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 32),
                Text(
                  'Preparando tu desafío...',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Estamos buscando los mejores retos disponibles para potenciar tus habilidades.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isSuccess) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Práctica Completada'),
          automaticallyImplyLeading: false,
        ),
        body: _buildSuccessView(theme, textTheme, isPro),
      );
    }

    if (_isFailure) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('¡Sigue Practicando!'),
          automaticallyImplyLeading: false,
        ),
        body: _buildFailureView(theme, textTheme, isPro),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Reto ${widget.technology}'),
        actions: [
          IconButton(
            onPressed: _confirmShowSolution,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'PRÁCTICA',
                        style: textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: theme.colorScheme.primary.withOpacity(0.7),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color: Colors.greenAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _getFormattedTime(),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Fila: Intentos Restantes + Nivel
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.primary.withOpacity(0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'INTENTOS',
                                style: textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (isPro)
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.all_inclusive,
                                      color: Colors.amber,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'ILIMITADOS',
                                      style: TextStyle(
                                        color: Colors.amber.withOpacity(0.9),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Row(
                                  children: List.generate(_maxAttempts, (
                                    index,
                                  ) {
                                    final remaining = _maxAttempts - _attempts;
                                    final isFilled = index < remaining;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isFilled
                                              ? theme.colorScheme.primary
                                              : Colors.transparent,
                                          border: Border.all(
                                            color: theme.colorScheme.primary
                                                .withOpacity(
                                                  isFilled ? 1.0 : 0.3,
                                                ),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Card NIVEL
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondary.withOpacity(
                              0.15,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.secondary.withOpacity(
                                0.5,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NIVEL',
                                style: textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _challenge!['level'] ?? '',
                                style: textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.secondary,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _challenge!['title'],
                    style: textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _challenge!['question'],
                    style: textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  CodeViewer(
                    code: _challenge!['code_snippet'] ?? '',
                    technology: widget.technology,
                  ),
                  if (_isSolutionVisible) ...[
                    const SizedBox(height: 16),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.amber.withOpacity(0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.lightbulb,
                                color: Colors.amber,
                                size: 20,
                              ),
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
                  const SizedBox(height: 24),

                  TextField(
                    controller: _answerController,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: 'Escribe tu respuesta aqui . ...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _answerController,
                    builder: (context, value, child) {
                      final bool isEmpty = value.text.trim().isEmpty;
                      return SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: (_isSubmitting || isEmpty)
                              ? null
                              : _submitAnswer,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
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
                                  ),
                                )
                              : const Text(
                                  'ENVIAR',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
      final imagePath = '${directory.path}/dev-retos-practica.png';

      final file = File(imagePath);
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(imagePath)],
        text:
            '¡He completado una sesión de práctica en Dev Retos 🚀! Dominando el nivel ${_challenge?['level']} en ${widget.technology}.',
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
}
