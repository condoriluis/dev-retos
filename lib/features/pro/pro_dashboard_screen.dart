import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../core/repositories/retos_repository.dart';
import '../../core/repositories/auth_repository.dart';
import '../../core/widgets/scanner_loading.dart';

final proWeeklyXPProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return [];

      final rawData = await ref
          .read(retosRepositoryProvider)
          .getWeeklyXPProgress(user.id);

      // Normalizar para que SIEMPRE haya 7 días (últimos 7 días)
      final List<Map<String, dynamic>> normalizedData = [];
      final now = DateTime.now();

      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final dateStr = DateFormat('yyyy-MM-dd').format(date);

        final dayData = rawData.firstWhere(
          (d) => d['day'] == dateStr,
          orElse: () => {'day': dateStr, 'xp': 0},
        );

        normalizedData.add(dayData);
      }

      return normalizedData;
    });

final proMasteryProvider = FutureProvider.autoDispose<Map<String, double>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return {};
  return ref.read(retosRepositoryProvider).getTechnologyMastery(user.id);
});

final proAccuracyProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return {'successes': 0, 'failures': 0};
  return ref.read(retosRepositoryProvider).getUserAccuracyStats(user.id);
});

class ProDashboardScreen extends ConsumerStatefulWidget {
  const ProDashboardScreen({super.key});

  @override
  ConsumerState<ProDashboardScreen> createState() => _ProDashboardScreenState();
}

class _ProDashboardScreenState extends ConsumerState<ProDashboardScreen>
    with SingleTickerProviderStateMixin {
  bool _isAnalyzing = true;
  final GlobalKey _globalKey = GlobalKey();
  bool _isSharing = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _startAnalysis();
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

  void _startAnalysis() async {
    final stopwatch = Stopwatch()..start();
    try {
      // Esperar a que todos los providers tengan datos
      await Future.wait([
        ref.read(proWeeklyXPProvider.future),
        ref.read(proMasteryProvider.future),
        ref.read(proAccuracyProvider.future),
      ]);
    } catch (e) {
      debugPrint('Error preloading dashboard: $e');
    }

    final elapsed = stopwatch.elapsedMilliseconds;
    // Reducido a 800ms para una experiencia ultra fluida
    if (elapsed < 800) {
      await Future.delayed(Duration(milliseconds: 800 - elapsed));
    }

    if (mounted) {
      setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _shareAnalytics() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);

    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final boundary =
          _globalKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return;

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final directory = await getTemporaryDirectory();
      final imagePath = '${directory.path}/dev-retos-analytics.png';
      final file = File(imagePath);
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(imagePath)],
        text:
            '🚀 Mi evolución técnica en Dev Retos. ¡Analizando mis límites para ser mejor developer! 💻🔥',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al compartir: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'ANALÍTICAS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: _isAnalyzing
            ? const _AnalyzingView()
            : _DashboardView(
                globalKey: _globalKey,
                isSharing: _isSharing,
                onShare: _shareAnalytics,
                pulseAnimation: _pulseAnimation,
              ),
      ),
    );
  }
}

class _AnalyzingView extends StatelessWidget {
  const _AnalyzingView();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        const ScannerLoading(),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.blueAccent, Colors.cyanAccent],
              ).createShader(bounds),
              child: const Text(
                'SINCRONIZANDO...',
                style: TextStyle(
                  letterSpacing: 4,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Extrayendo patrones de crecimiento técnico',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}

class _DashboardView extends ConsumerWidget {
  final GlobalKey globalKey;
  final bool isSharing;
  final VoidCallback onShare;
  final Animation<double> pulseAnimation;

  const _DashboardView({
    required this.globalKey,
    required this.isSharing,
    required this.onShare,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final weeklyXP = ref.watch(proWeeklyXPProvider);
    final mastery = ref.watch(proMasteryProvider);
    final accuracy = ref.watch(proAccuracyProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RepaintBoundary(
            key: globalKey,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 6),
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
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 16),

                  _buildSection(
                    context,
                    'CRECIMIENTO XP',
                    Icons.trending_up,
                    weeklyXP.when(
                      data: (data) => _XPLineChart(data: data),
                      loading: () => const SizedBox(height: 200),
                      error: (e, s) => Text('Error: $e'),
                    ),
                  ),

                  const SizedBox(height: 24),

                  _buildSection(
                    context,
                    'PRECISIÓN DE ACIERTOS',
                    Icons.ads_click,
                    accuracy.when(
                      data: (data) => _AccuracyPieChart(data: data),
                      loading: () => const SizedBox(height: 150),
                      error: (e, s) => const Icon(Icons.error),
                    ),
                  ),

                  const SizedBox(height: 24),

                  _buildSection(
                    context,
                    'DOMINIO POR TECNOLOGÍA',
                    Icons.code,
                    mastery.when(
                      data: (data) => _TechBarChart(data: data),
                      loading: () => const SizedBox(height: 150),
                      error: (e, s) => const Icon(Icons.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ScaleTransition(
            scale: pulseAnimation,
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: isSharing ? null : onShare,
                icon: isSharing
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
                  isSharing ? 'GENERANDO...' : 'COMPARTIR EVOLUCIÓN',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'VOLVER',
              style: TextStyle(color: Colors.white38, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
          ),
          child: const Icon(Icons.insights, color: Colors.blueAccent, size: 28),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RENDIMIENTO TÉCNICO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              Text(
                'Basado en tus últimos 7 días',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    IconData icon,
    Widget child,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.blueAccent.withOpacity(0.8)),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(height: title == 'CRECIMIENTO XP' ? 200 : 150, child: child),
        ],
      ),
    );
  }
}

class _XPLineChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _XPLineChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text('Sin datos esta semana'));

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          enabled: false,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) =>
                Colors.blueAccent.withOpacity(0.8),
            tooltipRoundedRadius: 6,
            showOnTopOfTheChartBoxArea: false,
            fitInsideHorizontally: true,
            tooltipMargin: 4,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 2,
            ),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toInt()} XP',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 8,
                  ),
                );
              }).toList();
            },
          ),
        ),
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 ||
                    index >= data.length ||
                    value != index.toDouble()) {
                  return const SizedBox();
                }
                final dateStr = data[index]['day']?.toString() ?? '';
                final date = DateTime.tryParse(dateStr) ?? DateTime.now();
                final dayShort = DateFormat('E', 'es_ES').format(date);

                // Forzar formato L, M, M, J, V, S, D
                String label = dayShort[0].toUpperCase();
                if (label == 'X')
                  label = 'M'; // Caso de Miércoles en algunos locales

                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: index == 6
                          ? Colors.blueAccent
                          : Colors.white.withOpacity(0.3),
                      fontSize: 10,
                      fontWeight: index == 6
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        showingTooltipIndicators: data.asMap().keys.map((index) {
          return ShowingTooltipIndicators([
            LineBarSpot(
              LineChartBarData(
                spots: data.asMap().entries.map((e) {
                  return FlSpot(
                    e.key.toDouble(),
                    (e.value['xp'] as int).toDouble(),
                  );
                }).toList(),
              ),
              0,
              FlSpot(index.toDouble(), (data[index]['xp'] as int).toDouble()),
            ),
          ]);
        }).toList(),
        lineBarsData: [
          LineChartBarData(
            spots: data.asMap().entries.map((e) {
              return FlSpot(
                e.key.toDouble(),
                (e.value['xp'] as int).toDouble(),
              );
            }).toList(),
            isCurved: true,
            color: Colors.blueAccent,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Colors.blueAccent.withOpacity(0.2),
                  Colors.blueAccent.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccuracyPieChart extends StatefulWidget {
  final Map<String, int> data;
  const _AccuracyPieChart({required this.data});

  @override
  State<_AccuracyPieChart> createState() => _AccuracyPieChartState();
}

class _AccuracyPieChartState extends State<_AccuracyPieChart> {
  int touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final total = widget.data['successes']! + widget.data['failures']!;
    if (total == 0) {
      return const Center(
        child: Text(
          'Sin retos',
          style: TextStyle(color: Colors.white24, fontSize: 10),
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            pieTouchData: PieTouchData(
              touchCallback: (FlTouchEvent event, pieTouchResponse) {
                setState(() {
                  if (!event.isInterestedForInteractions ||
                      pieTouchResponse == null ||
                      pieTouchResponse.touchedSection == null) {
                    touchedIndex = -1;
                    return;
                  }
                  touchedIndex =
                      pieTouchResponse.touchedSection!.touchedSectionIndex;
                });
              },
            ),
            sectionsSpace: 4,
            centerSpaceRadius: 30,
            sections: [
              PieChartSectionData(
                color: Colors.greenAccent,
                value: widget.data['successes']!.toDouble(),
                title: touchedIndex == 0 ? '${widget.data['successes']}' : '',
                radius: touchedIndex == 0 ? 18 : 12,
                titleStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              PieChartSectionData(
                color: touchedIndex == 1
                    ? Colors.redAccent
                    : Colors.redAccent.withOpacity(0.4),
                value: widget.data['failures']!.toDouble(),
                title: touchedIndex == 1 ? '${widget.data['failures']}' : '',
                radius: touchedIndex == 1 ? 16 : 8,
                titleStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${((widget.data['successes']! / total) * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const Text(
              'ÉXITO',
              style: TextStyle(
                fontSize: 7,
                color: Colors.white38,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TechBarChart extends StatelessWidget {
  final Map<String, double> data;
  const _TechBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty)
      return const Center(
        child: Text(
          'Sin datos',
          style: TextStyle(color: Colors.white24, fontSize: 10),
        ),
      );

    final techNames = data.keys.toList();

    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= techNames.length)
                  return const SizedBox();
                final name = techNames[index];
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Transform.rotate(
                    angle: -45 * 3.14159 / 180,
                    child: Text(
                      name.length > 10 ? '${name.substring(0, 8)}...' : name,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: data.entries.toList().asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value.value,
                color: Colors.blueAccent.withOpacity(0.7),
                width: 12,
                borderRadius: BorderRadius.circular(4),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: 10,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
