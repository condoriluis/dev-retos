import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/repositories/retos_repository.dart';

class StreakDetailsScreen extends ConsumerStatefulWidget {
  const StreakDetailsScreen({super.key});

  @override
  ConsumerState<StreakDetailsScreen> createState() =>
      _StreakDetailsScreenState();
}

class _StreakDetailsScreenState extends ConsumerState<StreakDetailsScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey _globalKey = GlobalKey();
  bool _isSharing = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _shareStreakImage() async {
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
      final imagePath = '${directory.path}/dev-retos-racha.png';

      final file = File(imagePath);
      await file.writeAsBytes(pngBytes);

      final user = ref.read(userProfileProvider).value;
      final streak = user?['current_streak'] ?? 0;

      await Share.shareXFiles(
        [XFile(imagePath)],
        text:
            '🔥 ¡Llevo $streak días de racha programando en Dev Retos! 🚀 ¿Crees que puedas superarme?',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userAsync = ref.watch(userProfileProvider);
    final weeklyProgressAsync = ref.watch(weeklyProgressProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            RepaintBoundary(
              key: _globalKey,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.alphaBlend(
                        Colors.orange.withOpacity(0.05),
                        theme.colorScheme.surface,
                      ),
                      Color.alphaBlend(
                        Colors.orange.withOpacity(0.12),
                        theme.colorScheme.surface,
                      ),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.15),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    userAsync.when(
                      data: (user) {
                        final streak = user?['current_streak'] ?? 0;
                        return Column(
                          children: [
                            Text(
                              '$streak',
                              style: theme.textTheme.displayLarge?.copyWith(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 80,
                              ),
                            ),
                            Text(
                              'DÍAS DE RACHA',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.orange.withOpacity(0.8),
                                letterSpacing: 4,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) => const Text('Error al cargar racha'),
                    ),
                    const SizedBox(height: 48),
                    weeklyProgressAsync.when(
                      data: (progress) {
                        // Determinar el día protegido por el escudo:
                        // last_shield_used es el día que activó el shield,
                        // el día protegido es ese mismo día -1 (ayer respecto al shield)
                        DateTime? shieldedDay;
                        final lastShieldStr = userAsync
                            .value?['last_shield_used']
                            ?.toString();
                        if (lastShieldStr != null) {
                          final lastShield = DateTime.tryParse(lastShieldStr);
                          if (lastShield != null) {
                            shieldedDay = lastShield.subtract(
                              const Duration(days: 1),
                            );
                          }
                        }
                        return _buildWeeklyProgressRow(
                          progress,
                          shieldedDay: shieldedDay,
                        );
                      },
                      loading: () => _buildWeeklyProgressRow(
                        List.filled(7, false),
                        isSkeleton: true,
                      ),
                      error: (_, __) => const Text('No disponible'),
                    ),
                    const SizedBox(height: 24),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.white, Colors.white70],
                      ).createShader(bounds),
                      child: Text(
                        '¡SIGUE ASÍ!',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            ScaleTransition(
              scale: _pulseAnimation,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _isSharing ? null : _shareStreakImage,
                  icon: _isSharing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.share),
                  label: Text(
                    _isSharing ? 'GENERANDO...' : 'COMPARTIR TU RACHA',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'CONTINUAR',
                style: TextStyle(color: Colors.white54, letterSpacing: 1.2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyProgressRow(
    List<bool> progress, {
    bool isSkeleton = false,
    DateTime? shieldedDay,
  }) {
    final daysLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Normalizar shieldedDay a medianoche para comparar por fecha
    final shieldedDate = shieldedDay != null
        ? DateTime(shieldedDay.year, shieldedDay.month, shieldedDay.day)
        : null;

    // Ventana deslizante: empezamos hace 6 días para que el séptimo sea HOY
    final firstDay = today.subtract(const Duration(days: 6));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(7, (index) {
          final currentDay = firstDay.add(Duration(days: index));
          final diffFromToday = today.difference(currentDay).inDays;
          final currentDayNorm = DateTime(
            currentDay.year,
            currentDay.month,
            currentDay.day,
          );

          final isShielded =
              !isSkeleton &&
              shieldedDate != null &&
              currentDayNorm == shieldedDate;

          final isCompleted = 
              !isSkeleton && 
              !isShielded && 
              diffFromToday >= 0 && 
              diffFromToday < 7 && 
              progress[diffFromToday];
          
          final isToday = diffFromToday == 0;
          final dayLabel = daysLabels[currentDay.weekday - 1];

          return Column(
            children: [
              Text(
                dayLabel,
                style: TextStyle(
                  color: isToday
                      ? Colors.white
                      : isCompleted
                      ? Colors.green
                      : isShielded
                      ? Colors.greenAccent
                      : Colors.white54,
                  fontWeight: (isToday || isShielded || isCompleted)
                      ? FontWeight.bold
                      : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSkeleton
                      ? Colors.white.withOpacity(0.05)
                      : isCompleted
                      ? Colors.green.withOpacity(0.2)
                      : isShielded
                      ? Colors.greenAccent.withOpacity(0.15)
                      : Colors.white.withAlpha(25),
                  border: Border.all(
                    color: !isSkeleton && isCompleted
                        ? Colors.green
                        : !isSkeleton && isShielded
                        ? Colors.greenAccent.withOpacity(0.6)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: !isSkeleton && isCompleted
                    ? const Icon(Icons.check, color: Colors.green, size: 18)
                    : !isSkeleton && isShielded
                    ? const Icon(
                        Icons.shield,
                        color: Colors.greenAccent,
                        size: 16,
                      )
                    : !isSkeleton && isToday
                    ? const Center(
                        child: Icon(
                          Icons.circle,
                          size: 6,
                          color: Colors.orange,
                        ),
                      )
                    : null,
              ),
            ],
          );
        }),
      ),
    );
  }
}
