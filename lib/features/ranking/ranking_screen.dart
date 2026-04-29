import 'package:dev_retos/core/providers/guest_provider.dart';
import 'package:dev_retos/core/repositories/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:country_flags/country_flags.dart';
import '../../core/repositories/retos_repository.dart';
import '../../core/widgets/scanner_loading.dart';
import '../../core/widgets/app_refresh_indicator.dart';

class RankingScreen extends ConsumerStatefulWidget {
  const RankingScreen({super.key});

  @override
  ConsumerState<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends ConsumerState<RankingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    ref.invalidate(globalRankingProvider);
    ref.invalidate(dailyRankingProvider);
    await Future.wait([
      ref.read(globalRankingProvider.future),
      ref.read(dailyRankingProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ranking Global'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Histórico'),
            Tab(text: 'Hoy'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRankingList(context, ref, isHistorical: true),
          _buildRankingList(context, ref, isHistorical: false),
        ],
      ),
    );
  }

  Widget _buildRankingList(
    BuildContext context,
    WidgetRef ref, {
    required bool isHistorical,
  }) {
    final rankingAsync = isHistorical
        ? ref.watch(globalRankingProvider)
        : ref.watch(dailyRankingProvider);
    final user = ref.watch(currentUserProvider);
    final guestId = ref.watch(guestIdProvider);
    final currentUserId = user?.id ?? guestId;

    return rankingAsync.when(
      loading: () => const ScannerLoading(),
      error: (err, stack) =>
          Center(child: Text('Error al cargar ranking: $err')),
      data: (users) {
        if (users.isEmpty) {
          return const Center(
            child: Text('Aún no hay competidores. ¡Sé el primero!'),
          );
        }

        final topThree = users.length >= 3 ? users.sublist(0, 3) : users;
        final remainingUsers = users.length > 3 ? users.sublist(3) : [];

        return AppRefreshIndicator(
          onRefresh: _handleRefresh,
          slivers: [
            // Podio de los 3 mejores
            SliverToBoxAdapter(
              child: _buildPodium(context, topThree, currentUserId),
            ),

            // Lista del resto de usuarios
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final user = remainingUsers[index];
                  final position = index + 4;
                  return _buildRankingItem(
                    context,
                    user,
                    position,
                    currentUserId,
                  );
                }, childCount: remainingUsers.length),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPodium(
    BuildContext context,
    List<dynamic> topThree,
    String? currentUserId,
  ) {
    if (topThree.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 2do Lugar (Izquierda)
          if (topThree.length >= 2)
            _buildPedestal(context, topThree[1], 2, 100, currentUserId),

          const SizedBox(width: 8),

          // 1er Lugar (Centro - Más alto)
          _buildPedestal(context, topThree[0], 1, 140, currentUserId),

          const SizedBox(width: 8),

          // 3er Lugar (Derecha)
          if (topThree.length >= 3)
            _buildPedestal(context, topThree[2], 3, 85, currentUserId),
        ],
      ),
    );
  }

  Widget _buildPedestal(
    BuildContext context,
    dynamic user,
    int position,
    double height,
    String? currentUserId,
  ) {
    final theme = Theme.of(context);
    final isFirst = position == 1;
    final isMe = user['id'] == currentUserId;
    final isPro =
        user['is_pro'] == true ||
        user['is_pro'] == 1 ||
        user['is_pro']?.toString() == '1';

    final color = position == 1
        ? Colors.amber
        : position == 2
        ? Colors.grey.shade400
        : Colors.orange.shade800;

    final String trophyEmoji = isFirst
        ? '🏆'
        : position == 2
        ? '🥈'
        : '🥉';

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icono Trofeo
          Text(trophyEmoji, style: TextStyle(fontSize: isFirst ? 36 : 28)),
          const SizedBox(height: 2),
          // Nombre de Usuario + Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  user['username']?.toString() ?? '???',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isFirst ? 13 : 11,
                    color: isMe
                        ? theme.colorScheme.primary
                        : (isFirst
                              ? Colors.amber
                              : theme.colorScheme.onSurface),
                  ),
                ),
              ),
              if (isPro) ...[
                const SizedBox(width: 2),
                const Icon(Icons.verified, color: Colors.blue, size: 14),
              ],
            ],
          ),
          if (isMe)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'TÚ',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          const SizedBox(height: 2),
          // El Pedestal (Bloque Rectangular) con la bandera en la esquina
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: height,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color.withOpacity(0.8), color.withOpacity(0.4)],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '#$position',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${user['xp']} XP',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: CountryFlag.fromCountryCode(
                  _getCountryCode(user['country']),
                  theme: const ImageTheme(
                    width: 20,
                    height: 20,
                    shape: Circle(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRankingItem(
    BuildContext context,
    dynamic user,
    int position,
    String? currentUserId,
  ) {
    final theme = Theme.of(context);
    final isMe = user['id'] == currentUserId;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isMe
            ? theme.colorScheme.primary.withOpacity(0.15)
            : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isMe
              ? theme.colorScheme.primary.withOpacity(0.5)
              : theme.colorScheme.outlineVariant.withOpacity(0.5),
          width: 1.0,
        ),
      ),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        horizontalTitleGap: 8,
        minLeadingWidth: 24,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: SizedBox(
          width: 32,
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
              children: [
                TextSpan(
                  text: '#',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                TextSpan(
                  text: '$position',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
        title: Row(
          children: [
            CountryFlag.fromCountryCode(
              _getCountryCode(user['country']),
              theme: const ImageTheme(width: 20, height: 20, shape: Circle()),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '@${user['username']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isMe ? FontWeight.bold : FontWeight.w600,
                  color: isMe ? theme.colorScheme.primary : null,
                ),
              ),
            ),
            if (user['is_pro'] == true) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified, color: Colors.blue, size: 16),
            ],
          ],
        ),
        subtitle: isMe
            ? Text(
                '¡Eres tú!',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
              )
            : null,
        trailing: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '${user['xp']}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isMe
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
              TextSpan(
                text: ' XP',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isMe
                      ? theme.colorScheme.primary
                      : theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
}
