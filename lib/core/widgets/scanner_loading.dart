import 'package:flutter/material.dart';

class ScannerLoading extends StatefulWidget {
  final Widget? backgroundSkeleton;

  const ScannerLoading({super.key, this.backgroundSkeleton});

  @override
  State<ScannerLoading> createState() => _ScannerLoadingState();
}

class _ScannerLoadingState extends State<ScannerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // Animación repetitiva que escanea de arriba (0.0) a abajo (1.0)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: false);

    _animation = Tween<double>(begin: -0.1, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenHeight = size.height;
    final screenWidth = size.width;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Altura disponible en este contenedor específico
        final containerHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : screenHeight;

        return SizedBox(
          height: containerHeight,
          width: double.infinity,
          child: Stack(
            children: [
              if (widget.backgroundSkeleton != null)
                Opacity(opacity: 0.2, child: widget.backgroundSkeleton!)
              else
                const SizedBox.expand(),

              // Usar OverflowBox para que el scanner "ignore" el padding del padre
              Center(
                child: OverflowBox(
                  maxWidth: screenWidth,
                  minWidth: screenWidth,
                  maxHeight: containerHeight,
                  minHeight: containerHeight,
                  child: Stack(
                    children: [
                      // Sombra gradiente
                      AnimatedBuilder(
                        animation: _animation,
                        builder: (context, child) {
                          // Usar containerHeight para que la trayectoria sea la correcta
                          final top = containerHeight * _animation.value;
                          return Positioned(
                            top: top - 150,
                            left: 0,
                            right: 0,
                            height: 150,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.25),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      // Línea brillante
                      AnimatedBuilder(
                        animation: _animation,
                        builder: (context, child) {
                          // Usar containerHeight para que la trayectoria sea la correcta
                          final top = containerHeight * _animation.value;
                          return Positioned(
                            top: top,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    blurRadius: 14,
                                    spreadRadius: 4,
                                  ),
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.4),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
