import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/repositories/retos_repository.dart';
import '../../core/repositories/auth_repository.dart';
import '../../core/widgets/scanner_loading.dart';

final aiHistoryProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return [];
      return ref.read(retosRepositoryProvider).getAiChallengeHistory(user.id);
    });

class AiHistoryScreen extends ConsumerWidget {
  const AiHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context);
    final historyAsync = ref.watch(aiHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Retos IA'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(aiHistoryProvider),
          ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const ScannerLoading(),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (challenges) {
          if (challenges.isEmpty) {
            return _buildEmptyState(context);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: challenges.length,
            itemBuilder: (context, index) {
              final challenge = challenges[index];
              return _buildChallengeCard(context, challenge);
            },
          );
        },
      ),
    );
  }

  Widget _buildChallengeCard(
    BuildContext context,
    Map<String, dynamic> challenge,
  ) {
    final theme = Theme.of(context);
    final isSuccess = challenge['is_success'] == true;
    final createdAt =
        DateTime.tryParse(challenge['created_at']) ?? DateTime.now();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSuccess
              ? Colors.green.withOpacity(0.3)
              : theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: (isSuccess ? Colors.green : Colors.blue).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.auto_awesome,
            color: isSuccess ? Colors.green : Colors.blue,
            size: 24,
          ),
        ),
        title: Text(
          challenge['title'] ?? 'Reto IA',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    challenge['technology'] ?? 'Unknown',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('dd MMM yyyy').format(createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: FilledButton(
          onPressed: () {
            // Navegar a SolvingScreen en modo práctica con este reto
            context.push(
              '/practica/solving',
              extra: {
                'id': challenge['id'],
                'technology': challenge['technology'],
                'level': challenge['level'],
                'isAi': true,
              },
            );
          },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('REINTENTAR', style: TextStyle(fontSize: 11)),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 80,
            color: theme.colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          const Text(
            'Aún no has generado retos con IA',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Usa el Escáner IA para crear retos personalizados.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => context.go('/practica'),
            icon: const Icon(Icons.psychology),
            label: const Text('IR A PRÁCTICA'),
          ),
        ],
      ),
    );
  }
}
