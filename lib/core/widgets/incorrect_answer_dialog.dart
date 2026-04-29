import 'dart:async';
import 'package:flutter/material.dart';

class IncorrectAnswerDialog extends StatefulWidget {
  final int remainingAttempts;

  const IncorrectAnswerDialog({super.key, required this.remainingAttempts});

  /// Muestra el diálogo de respuesta incorrecta de forma profesional.
  static void show(BuildContext context, int remainingAttempts) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) =>
          IncorrectAnswerDialog(remainingAttempts: remainingAttempts),
    );
  }

  @override
  State<IncorrectAnswerDialog> createState() => _IncorrectAnswerDialogState();
}

class _IncorrectAnswerDialogState extends State<IncorrectAnswerDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _opacityAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _controller.forward();

    // Auto-cerrado rápido (1.5 segundos) para no interrumpir el flujo
    _autoCloseTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: FadeTransition(
          opacity: _opacityAnimation,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(
                  0xFF1A1A1A,
                ), // Fondo ultra oscuro profesional
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: theme.colorScheme.error.withOpacity(0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.error.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      color: theme.colorScheme.error,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'RESPUESTA INCORRECTA',
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No te rindas, analiza el código de nuevo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.remainingAttempts < 0 ? '∞' : '${widget.remainingAttempts}',
                            style: TextStyle(
                              color: widget.remainingAttempts < 0 ? Colors.amber : theme.colorScheme.error,
                              fontSize: 56,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.remainingAttempts < 0 
                                ? 'INTENTOS ILIMITADOS'
                                : (widget.remainingAttempts <= 1
                                    ? 'INTENTO RESTANTE'
                                    : 'INTENTOS RESTANTES'),
                            style: TextStyle(
                              color: widget.remainingAttempts < 0 ? Colors.amber.withOpacity(0.7) : Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
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
      ),
    );
  }
}
