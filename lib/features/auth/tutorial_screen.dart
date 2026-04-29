import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:audioplayers/audioplayers.dart';
import '../shared/widgets/code_viewer.dart';

class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key});

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> {
  int _step = 0;
  final _answerController = TextEditingController();
  int _countdown = 3;
  Timer? _transitionTimer;
  Timer? _mockTimer;
  int _tutorialSeconds = 0;
  final _audioPlayer = AudioPlayer();

  Future<void> _playCountdownSound() async {
    try {
      if (_audioPlayer.state == PlayerState.playing) {
        await _audioPlayer.stop();
      }
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(AssetSource('sounds/countdown.mp3'));
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }
  }

  // Mock data for tutorial
  final String _tutorialCode = "print(3 + 2)";
  final String _correctAnswer = "5";

  void _nextStep() {
    if (_step < 4) {
      setState(() => _step++);
      if (_step == 3) {
        _startMockTimer();
      }
    }
  }

  void _startMockTimer() {
    _mockTimer?.cancel();
    _mockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _step >= 3 && _step <= 4) {
        setState(() => _tutorialSeconds++);
      } else {
        timer.cancel();
      }
    });
  }

  String _getFormattedTime() {
    final minutes = _tutorialSeconds ~/ 60;
    final seconds = _tutorialSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _checkAnswer() {
    if (_answerController.text.trim() == _correctAnswer) {
      setState(() {
        _step = 5;
      });
      _startSuccessSequence();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Casi! Inténtalo de nuevo. ¿Cuánto es 3 + 2?'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _startSuccessSequence() {
    // Paso 5: ¡Correcto!
    _transitionTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _step = 6); // Paso 6: Ya sabes la lógica

      _transitionTimer = Timer(const Duration(milliseconds: 2000), () {
        if (mounted) setState(() => _step = 7); // Paso 7: Pero la velocidad...

        _transitionTimer = Timer(const Duration(milliseconds: 2000), () {
          if (mounted) setState(() => _step = 8); // Paso 8: Prepárate

          _transitionTimer = Timer(const Duration(milliseconds: 1500), () {
            if (mounted) setState(() => _step = 9); // Paso 9: LISTO

            _transitionTimer = Timer(const Duration(milliseconds: 1000), () {
              if (mounted) {
                setState(() => _step = 10); // Paso 10: Countdown
                // Play the sound ONCE here, let the full 3+ second audio play
                _playCountdownSound();
              }

              _transitionTimer = Timer.periodic(const Duration(seconds: 1), (
                timer,
              ) {
                if (!mounted) {
                  timer.cancel();
                  return;
                }
                if (_countdown > 1) {
                  setState(() => _countdown--);
                } else {
                  timer.cancel();
                  _audioPlayer.stop();
                  context.go('/diario');
                }
              });
            });
          });
        });
      });
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    _transitionTimer?.cancel();
    _mockTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Si estamos en la secuencia final de transición
    if (_step >= 5) {
      return _buildSuccessSequence(theme);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _step >= 3
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text(
                'TUTORIAL',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  fontSize: 13,
                ),
              ),
              centerTitle: false,
              actions: [
                // Intentos ooo (Solo visible en pasos 1, 3 y 4 o según flujo)
                if (_step == 1 || _step >= 3)
                  Row(
                    children: List.generate(
                      3,
                      (index) => Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                // Temporizador (Visible desde el paso 3)
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: Colors.greenAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getFormattedTime(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_step < 4) const SizedBox(height: 40),

                  // Muestra los componentes según el paso o todos en el paso 4
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.0, 0.2),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                    child: _buildStepContent(theme),
                  ),

                  const SizedBox(height: 40),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.0, 0.2),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                    child: _step < 4
                        ? _buildTutorialCard(theme)
                        : const SizedBox.shrink(key: ValueKey('empty_card')),
                  ),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.0, 0.2),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                    child: _step == 4
                        ? Column(
                            key: const ValueKey('submit_btn'),
                            children: [
                              const SizedBox(height: 40),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: FilledButton(
                                  onPressed: _checkAnswer,
                                  child: const Text(
                                    'ENVIAR RESPUESTA',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(key: ValueKey('empty_btn')),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(ThemeData theme) {
    if (_step == 4) {
      return Column(
        key: const ValueKey('step4'),
        children: [
          _buildAttemptsUI(theme),
          const SizedBox(height: 24),
          _buildCodeUI(theme),
          const SizedBox(height: 32),
          _buildInputUI(theme),
        ],
      );
    }

    switch (_step) {
      case 0:
        return _buildCodeUI(theme, key: const ValueKey('step0'));
      case 1:
        return _buildAttemptsUI(theme, key: const ValueKey('step1'));
      case 2:
        return _buildInputUI(theme, key: const ValueKey('step2'));
      case 3:
        return Column(
          key: const ValueKey('step3'),
          children: [
            const Icon(
              Icons.timer_outlined,
              size: 80,
              color: Colors.greenAccent,
            ),
            const SizedBox(height: 16),
            Text(
              _getFormattedTime(),
              style: theme.textTheme.displayMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCodeUI(ThemeData theme, {Key? key}) {
    final isHighlight = _step == 0;
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (isHighlight)
            BoxShadow(
              color: theme.colorScheme.primary.withOpacity(0.3),
              blurRadius: 30,
              spreadRadius: 2,
            ),
        ],
      ),
      child: CodeViewer(code: _tutorialCode, technology: 'python'),
    );
  }

  Widget _buildInputUI(ThemeData theme, {Key? key}) {
    final isHighlight = _step == 2;
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          if (isHighlight)
            BoxShadow(
              color: theme.colorScheme.primary.withOpacity(0.2),
              blurRadius: 20,
              spreadRadius: 1,
            ),
        ],
      ),
      child: TextField(
        controller: _answerController,
        enabled: _step == 4,
        readOnly: _step < 4,
        style: const TextStyle(fontFamily: 'monospace', color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Escribe tu respuesta aquí...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          prefixIcon: const Icon(
            Icons.keyboard_arrow_right,
            color: Colors.greenAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildAttemptsUI(ThemeData theme, {Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(_step == 1 ? 0.3 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(_step == 1 ? 1.0 : 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'INTENTOS: ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 8),
          ...List.generate(
            3,
            (index) => Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(
                  _step == 1 ? 1.0 : 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialCard(ThemeData theme) {
    String title = "";
    String desc = "";

    switch (_step) {
      case 0:
        title = "Lee el código";
        desc =
            "Un fragmento de código aparecerá aquí. Tu misión: descubrir qué imprime.\n\n💡 Puedes hacer pinch para hacer zoom si el código es pequeño.";
        break;
      case 1:
        title = "Intentos Limitados";
        desc =
            "Solo tienes 3 intentos por reto. ¡Cada fallo cuenta!\n\nSi te quedas sin intentos, perderás el progreso del reto.";
        break;
      case 2:
        title = "Escribe tu respuesta";
        desc =
            "Escribe la salida exacta que produciría el programa.\n\nRecuerda: los espacios y saltos de línea cuentan.";
        break;
      case 3:
        title = "El Tiempo Corre";
        desc =
            "El reloj empieza cuando inicias el reto. ¡Los más rápidos suben en el ranking global!";
        break;
    }

    return Card(
      color: theme.colorScheme.surfaceVariant.withOpacity(0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.topCenter,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(-0.2, 0.0), // from left to right
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                title,
                key: ValueKey('title_$_step'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 600), // staggering effect
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.topCenter,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.3), // from bottom to top
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                desc,
                key: ValueKey('desc_$_step'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _nextStep,
                child: const Text('CONTINUAR'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessSequence(ThemeData theme) {
    String message = "";
    if (_step == 5) message = "¡Excelente! Respuesta correcta.";
    if (_step == 6) message = "Ahora ya sabes cómo resolver el código...";
    if (_step == 7)
      message =
          "Pero en el mundo real, la velocidad y la precisión lo son todo.";
    if (_step == 8) message = "Prepárate para tu primer reto diario.";
    if (_step == 9) message = "¡LISTO!";
    if (_step >= 10) message = "$_countdown";

    final size = MediaQuery.of(context).size;
    final isCountdown = _step >= 10;
    final isReady = _step == 9;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Text(
              message,
              key: ValueKey(message),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isCountdown
                    ? (size.width * 0.4).clamp(120, 200)
                    : isReady
                    ? (size.width * 0.15).clamp(48, 80)
                    : 28,
                fontWeight: FontWeight.w900,
                color: (isCountdown || isReady)
                    ? theme.colorScheme.primary
                    : Colors.white,
                fontStyle: _step < 9 ? FontStyle.italic : FontStyle.normal,
                letterSpacing: isReady ? 4 : 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
