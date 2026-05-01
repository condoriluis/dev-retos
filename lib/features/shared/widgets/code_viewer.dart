import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

class CodeViewer extends StatefulWidget {
  final String code;
  final String technology;

  const CodeViewer({super.key, required this.code, required this.technology});

  @override
  State<CodeViewer> createState() => _CodeViewerState();
}

class _CodeViewerState extends State<CodeViewer> {
  double _fontSize = 14.0;
  static const double _minFontSize = 10.0;
  static const double _maxFontSize = 24.0;

  void _increaseFontSize() {
    if (_fontSize < _maxFontSize) setState(() => _fontSize += 2.0);
  }

  void _decreaseFontSize() {
    if (_fontSize > _minFontSize) setState(() => _fontSize -= 2.0);
  }

  String _getLanguage(String tech) {
    final t = tech.toLowerCase();
    if (t.contains('javascript') || t.contains('js')) return 'javascript';
    if (t.contains('python')) return 'python';
    if (t.contains('dart') || t.contains('flutter')) return 'dart';
    if (t.contains('java') && !t.contains('javascript')) return 'java';
    if (t.contains('kotlin')) return 'kotlin';
    if (t.contains('swift')) return 'swift';
    if (t.contains('php')) return 'php';
    if (t.contains('c++') || t.contains('cpp')) return 'cpp';
    if (t.contains('go')) return 'go';
    if (t.contains('rust')) return 'rust';
    if (t.contains('html')) return 'html';
    if (t.contains('css')) return 'css';
    if (t.contains('sql')) return 'sql';
    if (t.contains('linux') || t.contains('bash') || t.contains('shell')) {
      return 'bash';
    }
    return 'plaintext';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = _getLanguage(widget.technology);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1B26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF13131A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _dot(const Color(0xFFFF5F56)),
                    const SizedBox(width: 6),
                    _dot(const Color(0xFFFFBD2E)),
                    const SizedBox(width: 6),
                    _dot(const Color(0xFF27C93F)),
                    const SizedBox(width: 14),
                    const Icon(
                      Icons.code_rounded,
                      size: 14,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.technology.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white54,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _buildZoomButton(
                      icon: Icons.remove_circle_outline,
                      onPressed: _decreaseFontSize,
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${_fontSize.toInt()}px',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _buildZoomButton(
                      icon: Icons.add_circle_outline,
                      onPressed: _increaseFontSize,
                    ),
                  ],
                ),
              ],
            ),
          ),

          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width,
                ),
                child: HighlightView(
                  widget.code.trim(),
                  language: lang,
                  theme: monokaiSublimeTheme,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  textStyle: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: _fontSize,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _buildZoomButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Icon(icon, size: 20, color: Colors.white54),
        ),
      ),
    );
  }
}
