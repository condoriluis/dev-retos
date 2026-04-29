import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ProPaywall {
  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: _ProPaywallContent(),
      ),
    );
  }
}

class _ProPaywallContent extends StatefulWidget {
  const _ProPaywallContent();

  @override
  State<_ProPaywallContent> createState() => _ProPaywallContentState();
}

class _ProPaywallContentState extends State<_ProPaywallContent> {
  bool _isAnnualSelected = true;
  bool _isLoading = false;

  Future<void> _handleSubscription() async {
    setState(() => _isLoading = true);

    // Simular latencia de red con Google Play
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;
    setState(() => _isLoading = false);

    // Mostrar la ventana "Falsa" de Google Play
    _showMockGooglePlaySheet();
  }

  void _showMockGooglePlaySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (context) => _MockGooglePlayPurchaseSheet(
        price: _isAnnualSelected ? 'Bs 169.99' : 'Bs 20.99',
        period: _isAnnualSelected ? 'cada año' : 'cada mes',
        onSuccess: () {
          Navigator.pop(context); // Cerrar sheet de Google
          _showSuccessAndClose();
        },
      ),
    );
  }

  void _showSuccessAndClose() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ProSuccessDialog(
        onFinished: () {
          Navigator.pop(ctx); // Cerrar diálogo
          if (mounted) Navigator.pop(context); // Cerrar Paywall
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 650,
          maxHeight: size.height * 0.85,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(
                  Colors.amber.withOpacity(0.05),
                  theme.colorScheme.surface,
                ),
                Color.alphaBlend(
                  Colors.amber.withOpacity(0.12),
                  theme.colorScheme.surface,
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.amber.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 32.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(
                            Icons.workspace_premium,
                            size: 72,
                            color: Colors.amber,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Desbloquea Dev Retos PRO',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          _buildFeatureRow(
                            context,
                            Icons.all_inclusive,
                            'Práctica ilimitada',
                            'Sin límites diarios. Practica todos los lenguajes que quieras.',
                          ),
                          const SizedBox(height: 20),
                          _buildFeatureRow(
                            context,
                            Icons.shield,
                            'Streak Shield',
                            'Protege tu racha automáticamente una vez por semana.',
                          ),
                          const SizedBox(height: 20),
                          _buildFeatureRow(
                            context,
                            Icons.star,
                            'Acceso Total',
                            'Cada reto actual, más acceso prioritario a todas las funciones nuevas.',
                          ),
                          const SizedBox(height: 40),
                          _buildPlanCard(
                            title: 'Suscripción Anual',
                            price: 'Bs 169.99/año',
                            sub: 'Aproximadamente Bs 14.17 por mes',
                            isPopular: true,
                            isSelected: _isAnnualSelected,
                            onTap: () =>
                                setState(() => _isAnnualSelected = true),
                          ),
                          const SizedBox(height: 12),
                          _buildPlanCard(
                            title: 'Suscripción Mensual',
                            price: 'Bs 20.99/mes',
                            sub: '',
                            isPopular: false,
                            isSelected: !_isAnnualSelected,
                            onTap: () =>
                                setState(() => _isAnnualSelected = false),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            height: 46,
                            child: FilledButton(
                              onPressed: _isLoading ? null : _handleSubscription,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black,
                                elevation: 4,
                                shadowColor: Colors.amber.withOpacity(0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Text(
                                      'SUSCRIBIRME AHORA',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Ahora no, gracias',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'El pago se cargará a tu cuenta de Google Play. La suscripción se renueva automáticamente a menos que la canceles al menos 24 horas antes del fin del periodo actual.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 2),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 0,
                            children: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  context.push('/terms');
                                },
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text(
                                  'Términos',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white60,
                                  ),
                                ),
                              ),
                              Text(
                                '•',
                                style: TextStyle(
                                  color: Colors.white24,
                                  fontSize: 12,
                                  height: 2.5,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  context.push('/privacy');
                                },
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text(
                                  'Privacidad',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white60,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Botón Cerrar (X) arriba a la derecha
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  icon: Icon(
                    Icons.close,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.amber, size: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlanCard({
    required String title,
    required String price,
    required String sub,
    required bool isPopular,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? Colors.amber
                : theme.colorScheme.outline.withOpacity(0.5),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? Colors.amber.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isPopular)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'MEJOR PRECIO | AHORRA 33%',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle, color: Colors.amber, size: 20)
                else
                  Icon(
                    Icons.circle_outlined,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                sub,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProSuccessDialog extends StatelessWidget {
  final VoidCallback onFinished;

  const _ProSuccessDialog({required this.onFinished});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(Colors.amber.withOpacity(0.2), const Color(0xFF121212)),
              const Color(0xFF121212),
            ],
          ),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.amber.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withOpacity(0.1),
              blurRadius: 40,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.amber.withOpacity(0.2)),
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: Colors.amber,
                size: 64,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '¡YA ERES PRO!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.amber,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Has desbloqueado todo el potencial de Dev Retos. Prepárate para dominar el código sin límites.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.5, fontSize: 15),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: onFinished,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'EMPEZAR MI EXPERIENCIA PRO',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MockGooglePlayPurchaseSheet extends StatelessWidget {
  final String price;
  final String period;
  final VoidCallback onSuccess;

  const _MockGooglePlayPurchaseSheet({
    required this.price,
    required this.period,
    required this.onSuccess,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF202124),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/logotipo.png',
                  width: 44,
                  height: 44,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 44,
                    height: 44,
                    color: Colors.blue,
                    child: const Icon(Icons.code, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dev Retos: Aprende Código',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'Google Play',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Suscripción PRO', style: TextStyle(color: Colors.white, fontSize: 15)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(price, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(period, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Row(
            children: [
              Icon(Icons.payment, color: Colors.grey, size: 20),
              SizedBox(width: 12),
              Text('Visa •••• 4242', style: TextStyle(color: Colors.white, fontSize: 14)),
              Spacer(),
              Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: onSuccess,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00A251),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: const Text('Comprar con un toque', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security, color: Colors.grey, size: 14),
              SizedBox(width: 8),
              Text('Pago seguro con Google Pay', style: TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
