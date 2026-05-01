import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/repositories/retos_repository.dart';
import '../../core/widgets/pro_paywall.dart';
import '../../core/widgets/scanner_loading.dart';
import '../../core/widgets/app_refresh_indicator.dart';

class PracticaScreen extends ConsumerStatefulWidget {
  const PracticaScreen({super.key});

  @override
  ConsumerState<PracticaScreen> createState() => _PracticaScreenState();
}

class _PracticaScreenState extends ConsumerState<PracticaScreen> {
  static bool _sessionScanDone = false;
  late bool _showInitialScanner;
  bool _showIntro = false;

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
    _checkIntroStatus();
  }

  Future<void> _checkIntroStatus() async {
    final prefs = await SharedPreferences.getInstance();

    if (mounted) {
      setState(() {
        _showIntro = !(prefs.getBool('seen_practice_intro') ?? false);
      });
    }
  }

  Future<void> _completeIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_practice_intro', true);
    setState(() {
      _showIntro = false;
    });
  }

  Future<void> _handleRefresh() async {
    ref.invalidate(technologiesProvider);
    ref.invalidate(practiceSessionsProvider);
    ref.invalidate(userProfileProvider);

    await Future.wait([
      ref.read(technologiesProvider.future),
      ref.read(practiceSessionsProvider.future),
      ref.read(userProfileProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final techAsync = ref.watch(technologiesProvider);
    final sessionsAsync = ref.watch(practiceSessionsProvider);

    if (_showInitialScanner) {
      return const Scaffold(body: ScannerLoading());
    }

    if (_showIntro) {
      return _buildIntroView();
    }

    return _buildMainContent(techAsync, sessionsAsync);
  }

  Widget _buildIntroView() {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 32.0,
              vertical: 24.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Icon(
                  Icons.model_training_rounded,
                  size: 80,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 32),
                Text(
                  'MODO PRÁCTICA',
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: theme.colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Mejora tus habilidades entre los desafíos diarios. Practica a tu ritmo y sigue tu progreso.',
                  style: textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                Text(
                  'CÓMO FUNCIONA',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                _buildIntroItem(
                  Icons.code_rounded,
                  'Resuelve desafíos de código uno a uno para desarrollar tus habilidades.',
                ),
                const SizedBox(height: 24),
                _buildIntroItem(
                  Icons.trending_up_rounded,
                  'Gana XP con cada práctica para subir en el ranking.',
                ),
                const SizedBox(height: 24),
                _buildIntroItem(
                  Icons.speed_rounded,
                  'Rastrea tu progreso y mejora tu velocidad con el tiempo.',
                ),
                const SizedBox(height: 48),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _completeIntro,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'COMENZAR PRÁCTICA',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntroItem(IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 24, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent(
    AsyncValue<List<String>> techAsync,
    AsyncValue<List<Map<String, dynamic>>> sessionsAsync,
  ) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final userAsync = ref.watch(userProfileProvider);
    final user = userAsync.value;
    final bool isPro =
        user?['is_pro'] == true ||
        user?['is_pro'] == 1 ||
        user?['is_pro']?.toString() == '1' ||
        user?['is_pro']?.toString() == 'true';

    return Scaffold(
      appBar: AppBar(title: const Text('Práctica Libre')),
      body: Stack(
        children: [
          Positioned.fill(
            child: AppRefreshIndicator(
              onRefresh: _handleRefresh,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  top: 16.0,
                  bottom: !isPro && (sessionsAsync.value?.length ?? 0) > 3
                      ? 180.0
                      : 16.0, // Espacio para el footer transparente
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Paywall Section (Oculta para PRO)
                    if (!isPro)
                      Card(
                        elevation: 0,
                        color: theme.colorScheme.primaryContainer.withOpacity(
                          0.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: theme.colorScheme.primary,
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Desbloquea +100 Retos Exclusivos',
                                style: textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Prepárate para las entrevistas técnicas más exigentes. Suscríbete por Bs 20,99/mes o ahorra con el plan anual.',
                                style: textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                ),
                                onPressed: () {
                                  _showPaywall(context);
                                },
                                child: const Text('Desbloquear PRO ahora'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!isPro) const SizedBox(height: 32),

                    // Available Technologies
                    Text('Tecnologías', style: textTheme.titleLarge),
                    const SizedBox(height: 16),

                    techAsync.when(
                      skipLoadingOnRefresh: true,
                      loading: () => const SizedBox.shrink(),
                      error: (err, stack) =>
                          Text('Error al cargar tecnologías: $err'),
                      data: (techs) {
                        if (techs.isEmpty) {
                          return const Text('Nuevas tecnologías próximamente.');
                        }
                        return Wrap(
                          spacing: 8,
                          runSpacing: 12,
                          children: techs
                              .map(
                                (tech) => _buildTechChip(
                                  context,
                                  tech,
                                  _getIconForTech(tech),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),

                    const SizedBox(height: 32),
                    // Session History
                    Text('Historial de Sesiones', style: textTheme.titleLarge),
                    const SizedBox(height: 16),
                    sessionsAsync.when(
                      skipLoadingOnRefresh: true,
                      loading: () => const SizedBox.shrink(),
                      error: (err, stack) =>
                          Text('Error al cargar historial: $err'),
                      data: (sessions) {
                        if (sessions.isEmpty) {
                          return const Card(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                'Aún no tienes sesiones. ¡Empieza a practicar!',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
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
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (!isPro && (sessionsAsync.value?.length ?? 0) > 3)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withOpacity(0.12),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(30),
                      ),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 0.5,
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Desbloquea historial ilimitado y domina el código',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 4,
                              ),
                              onPressed: () {
                                _showPaywall(context);
                              },
                              child: const Text(
                                'SER PRO AHORA',
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
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTechChip(BuildContext context, String label, IconData icon) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Icon(icon, size: 16, color: theme.colorScheme.onPrimary),
      label: Text(
        label,
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
      backgroundColor: theme.colorScheme.primary,
      onPressed: () {
        _showLevelSelectorModal(context, label);
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide.none,
      elevation: 2,
      shadowColor: theme.colorScheme.primary.withOpacity(0.4),
    );
  }

  void _showLevelSelectorModal(BuildContext context, String technology) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            MediaQuery.of(context).padding.bottom + 24,
          ),
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(0.2),
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Selecciona Dificultad',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                technology.toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _buildDifficultyButton(
                context,
                technology,
                'BEGINNER',
                'Trainee / Junior',
                Icons.child_care_rounded,
              ),
              const SizedBox(height: 12),
              _buildDifficultyButton(
                context,
                technology,
                'INTERMEDIATE',
                'Semi-Senior',
                Icons.psychology_rounded,
              ),
              const SizedBox(height: 12),
              _buildDifficultyButton(
                context,
                technology,
                'ADVANCED',
                'Senior',
                Icons.rocket_launch_rounded,
              ),
              const SizedBox(height: 12),
              _buildDifficultyButton(
                context,
                technology,
                'EXPERT',
                'Expert / Guru',
                Icons.workspace_premium_rounded,
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDifficultyButton(
    BuildContext context,
    String technology,
    String level,
    String label,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: FilledButton.tonal(
        onPressed: () {
          Navigator.pop(context);
          context.push(
            '/solving',
            extra: {'technology': technology, 'level': level},
          );
        },
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.primary.withOpacity(0.5),
            ),
          ],
        ),
      ),
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
    final int successStatus = session['is_success'] ?? 0;
    final isSuccess = successStatus == 1;
    final isAbandoned = successStatus == -1;
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
          color: isAbandoned
              ? Colors.orange.withOpacity(0.3)
              : theme.colorScheme.outlineVariant.withOpacity(0.4),
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
                  color: isAbandoned
                      ? Colors.orange.withOpacity(0.1)
                      : theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '#$number',
                  style: TextStyle(
                    color: isAbandoned
                        ? Colors.orange
                        : theme.colorScheme.primary,
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
                        color: isAbandoned ? Colors.orange.shade200 : null,
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
                          child: isAbandoned
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.orange.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'ABANDONADO',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: Colors.orange,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.5,
                                            ),
                                      ),
                                    ],
                                  ),
                                )
                              : (attempts > 3
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary
                                              .withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
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
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
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
                                        children: List.generate(attempts, (
                                          index,
                                        ) {
                                          final isLast = index == attempts - 1;
                                          final color = (isLast && isSuccess)
                                              ? Colors.green
                                              : Colors.grey.withOpacity(0.5);
                                          return Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: color,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          );
                                        }),
                                      )),
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
                isSuccess
                    ? Icons.check_circle
                    : (isAbandoned ? Icons.flag_rounded : Icons.cancel),
                color: isSuccess
                    ? Colors.green
                    : (isAbandoned ? Colors.orange : Colors.red),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForTech(String tech) {
    return Icons.terminal_rounded;
  }

  void _showPaywall(BuildContext context) {
    ProPaywall.show(context);
  }
}
