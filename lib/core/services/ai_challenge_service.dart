import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_challenge_service.g.dart';

class AiChallengeService {
  Future<Map<String, dynamic>?> generateChallenge(
    String technology,
    String level,
  ) async {
    String basePrompt = _buildPrompt(technology, level);

    final providers = [
      {
        "url": "https://api.groq.com/openai/v1/chat/completions",
        "key": dotenv.env['GROQ_API_KEY'],
        "model": "llama3-70b-8192",
      },
      {
        "url": "https://api.cerebras.ai/v1/chat/completions",
        "key": dotenv.env['CEREBRAS_API_KEY'],
        "model": "llama3.1-8b",
      },
      {
        "url": "https://openrouter.ai/api/v1/chat/completions",
        "key": dotenv.env['OPENROUTER_API_KEY'],
        "model": "mistralai/mixtral-8x7b-instruct",
      },
    ];

    for (final p in providers) {
      if (p['key'] == null || p['key']!.isEmpty) continue;

      final result = await _callApi(
        p['url']!,
        p['key']!,
        p['model']!,
        basePrompt,
      );

      if (result != null) {
        final sanitized = _sanitize(result, technology, level);
        if (_isValidChallenge(sanitized, technology, level)) {
          return sanitized;
        }
      }
    }

    return null;
  }

  String _buildPrompt(String tech, String level) {
    return '''
### ROLE: Senior $tech Expert
### TARGET LEVEL: $level
### TECHNOLOGY: $tech

Generate ONE professional and unique programming challenge.

STRICT RULES:
1. Question and Title MUST be in Spanish.
2. Output MUST be a single, valid JSON object.
3. DO NOT include any text before or after the JSON.
4. DO NOT repeat the level ($level) or technology ($tech) as plain text at the end.
5. code_snippet MUST contain EXACTLY ONE ___ (three underscores).
6. correct_answer must be the EXACT code to replace ___.
7. NO markdown formatting inside the JSON values.
8. NEVER generate syntax errors for the requested version (e.g. PHP 8.1+).

### REFERENCE EXAMPLE:
${_getGoldenExample(tech)}

LEVEL GUIDANCE ($level):
${_getLevelGuidance(level)}

TECH SPECIFIC FOCUS ($tech):
${_getTechFocus(tech)}

OUTPUT FORMAT:
{"title": "...", "question": "...", "code_snippet": "...", "correct_answer": "..."}
''';
  }

  String _getGoldenExample(String tech) {
    final Map<String, String> examples = {
      'Dart':
          '{"title": "Records", "question": "¿Cómo se accede al primer elemento posicional de un Record?", "code_snippet": "var r = (10, 20); print(r.___1);", "correct_answer": "\$"}',
      'Flutter':
          '{"title": "ValueNotifier", "question": "¿Qué propiedad se usa para actualizar el valor de un ValueNotifier?", "code_snippet": "notifier.___ = 10;", "correct_answer": "value"}',
      'SQL':
          '{"title": "Window Functions", "question": "¿Qué cláusula se usa para definir el grupo de filas en una función de ventana?", "code_snippet": "SELECT id, AVG(p) OVER(___ BY cat) FROM t;", "correct_answer": "PARTITION"}',
      'Python':
          '{"title": "List Comprehension", "question": "¿Qué palabra clave se usa para filtrar elementos en una lista comprimida?", "code_snippet": "[x for x in data ___ x > 0]", "correct_answer": "if"}',
      'JavaScript':
          '{"title": "Optional Chaining", "question": "¿Qué operador se usa para acceder a una propiedad de forma segura si el objeto es null?", "code_snippet": "const val = obj___prop;", "correct_answer": "?."}',
      'PHP':
          '{"title": "Null Coalescing", "question": "¿Qué operador se usa para asignar un valor por defecto si una variable es nula?", "code_snippet": "<?php \$name = \$input ___ \"Invitado\";", "correct_answer": "??"}',
      'Rust':
          '{"title": "Pattern Matching", "question": "¿Qué símbolo se usa como comodín para atrapar cualquier valor en un match?", "code_snippet": "match x { 1 => (), ___ => () }", "correct_answer": "_"}',
      'Java':
          '{"title": "Streams API", "question": "¿Qué método se usa para transformar elementos en un Stream?", "code_snippet": "list.stream().___(x -> x.toUpperCase());", "correct_answer": "map"}',
      'Kotlin':
          '{"title": "Safe Call", "question": "¿Qué operador se usa para llamar a un método solo si el objeto no es nulo?", "code_snippet": "user___.getName();", "correct_answer": "?"}',
      'Swift':
          '{"title": "Optional Binding", "question": "¿Qué palabra clave se usa para desenvolver un opcional de forma segura?", "code_snippet": "___ let name = optionalName { ... }", "correct_answer": "if"}',
      'C++':
          '{"title": "Smart Pointers", "question": "¿Qué tipo de puntero inteligente indica propiedad única?", "code_snippet": "std::___<int> p = std::make_unique<int>(10);", "correct_answer": "unique_ptr"}',
      'Go':
          '{"title": "Goroutines", "question": "¿Qué palabra clave inicia una ejecución concurrente?", "code_snippet": "___ worker();", "correct_answer": "go"}',
      'Linux':
          '{"title": "Permisos", "question": "¿Qué comando se usa para cambiar el propietario de un archivo?", "code_snippet": "sudo ___ user:group file.txt", "correct_answer": "chown"}',
      'HTML':
          '{"title": "Semántica", "question": "¿Qué etiqueta se usa para definir el contenido principal de un documento?", "code_snippet": "<___><h1>Título</h1></___>", "correct_answer": "main"}',
      'CSS':
          '{"title": "Flexbox", "question": "¿Qué propiedad define la dirección de los elementos en un contenedor flex?", "code_snippet": ".box { ___: column; }", "correct_answer": "flex-direction"}',
    };
    return examples[tech] ??
        '{"title": "Sintaxis", "question": "¿Qué palabra clave define una variable?", "code_snippet": "___ x = 10;", "correct_answer": "var"}';
  }

  String _getLevelGuidance(String level) {
    switch (level.toUpperCase()) {
      case 'JUNIOR':
      case 'BEGINNER':
        return 'Focus on basic syntax, common keywords, and fundamental language concepts.';
      case 'SEMI-SENIOR':
      case 'INTERMEDIATE':
        return 'Focus on best practices, standard library usage, and common design patterns.';
      case 'SENIOR':
      case 'ADVANCED':
        return 'Focus on performance, security, architecture, and complex edge cases.';
      case 'EXPERT':
        return 'Focus on deep internals, memory management, complex concurrency, and obscure but powerful features.';
      default:
        return 'Provide a balanced challenge for the level.';
    }
  }

  String _getTechFocus(String tech) {
    switch (tech) {
      case 'Dart':
        return 'Focus on Null Safety, Records, Mixins, Extension methods or Asynchronous patterns.';
      case 'Flutter':
        return 'Focus on Widget Lifecycle, BuildContext, InheritedWidgets or CustomPaint.';
      case 'SQL':
        return 'Focus on Window Functions, CTEs (WITH), complex JOINs or Subqueries.';
      case 'Python':
        return 'Focus on Decorators, Generators, List Comprehensions or Dunder methods.';
      case 'JavaScript':
        return 'Focus on Closures, Promises, Destructuring, Proxy or ES2023+ features.';
      case 'PHP':
        return 'Focus on Typed Properties, Enums (PHP 8.1+), Attributes or Anonymous Classes.';
      case 'Rust':
        return 'Focus on Ownership, Borrowing, Traits, Pattern Matching or Result handling.';
      case 'Java':
        return 'Focus on Streams API, Optionals, Records (Java 14+) or Reflection.';
      case 'Kotlin':
        return 'Focus on Coroutines, Data classes, Sealed interfaces or Extension functions.';
      case 'Swift':
        return 'Focus on Protocol-oriented programming, Closures, Result type or Enums.';
      case 'C++':
        return 'Focus on Smart Pointers (unique_ptr), Templates, Lambda captures or STL.';
      case 'Go':
        return 'Focus on Interfaces, Goroutines, Channels, Defer or Struct tags.';
      case 'Linux':
        return 'Focus on advanced shell commands, Pipes, Redirection, Chmod/Chown or Systemd.';
      case 'HTML':
        return 'Focus on Semantic HTML5, Data-attributes, ARIA roles or Template tags.';
      case 'CSS':
        return 'Focus on Flexbox, CSS Grid, Advanced Selectors, Pseudo-elements or CSS Variables.';
      default:
        return 'Focus on advanced syntax and best practices specific to $tech.';
    }
  }

  bool _isValidChallenge(Map<String, dynamic> data, String tech, String level) {
    final title = data['title']?.toString().trim() ?? '';
    final question = data['question']?.toString().trim() ?? '';
    final code = data['code_snippet']?.toString().trim() ?? '';
    final answer = data['correct_answer']?.toString().trim() ?? '';

    if ([title, question, code, answer].any((e) => e.isEmpty)) return false;
    if ('___'.allMatches(code).length != 1) return false;

    if (title.split(' ').length > 6) return false;
    if (question.length > 150) return false;
    if (answer.length > 25) return false;
    if (code.length > 500) return false;

    if (tech == 'HTML' &&
        (code.contains('fa-') || code.contains('bootstrap'))) {
      return false;
    }

    final cleanCode = code.toLowerCase();
    if (cleanCode.contains('int ___ = 5') ||
        cleanCode.contains('var ___ =') ||
        cleanCode.contains('x = ___'))
      return false;

    if (!_isValidByTech(code, answer, tech)) return false;

    if (!_isSpanish(question)) return false;

    if ((level == 'ADVANCED' || level == 'INTERMEDIATE') && code.length < 25) {
      return false;
    }

    return true;
  }

  bool _isValidByTech(String code, String answer, String tech) {
    final lowerCode = code.toLowerCase();
    final lowerAnswer = answer.toLowerCase();

    if (tech != 'HTML' && tech != 'PHP') {
      if (lowerCode.contains('<div') ||
          lowerCode.contains('<style') ||
          lowerCode.contains('</'))
        return false;
    }

    switch (tech) {
      case 'SQL':
        if (lowerAnswer == '--' || lowerAnswer == '/*') return false;
        if (!lowerCode.contains('select') &&
            !lowerCode.contains('update') &&
            !lowerCode.contains('with') &&
            !lowerCode.contains('insert') &&
            !lowerCode.contains('delete')) {
          return false;
        }
        break;
      case 'PHP':
        if (!code.contains('<?php') && !code.contains('?>')) return false;
        if (lowerCode.contains('select ') || lowerCode.contains('table')) {
          return false;
        }
        break;
      case 'CSS':
        if (!code.contains('{') || !code.contains(':')) return false;
        if (lowerCode.contains('select ') || lowerCode.contains('from ')) {
          return false;
        }
        break;
      case 'HTML':
        if (!code.contains('<') || !code.contains('>')) return false;
        if (lowerCode.contains('select ') || lowerCode.contains('from ')) {
          return false;
        }
        break;
      case 'Linux':
        if (code.contains('//') || code.contains('/*')) return false;
        if (lowerCode.contains('select ') || lowerCode.contains('{')) {
          return false;
        }
        break;
      case 'JavaScript':
      case 'Dart':
      case 'Java':
      case 'Kotlin':
      case 'Swift':
      case 'C++':
      case 'Go':
      case 'Rust':
        if (!code.contains('(') && !code.contains('{') && !code.contains(';')) {
          return false;
        }
        break;
    }
    return true;
  }

  bool _isSpanish(String text) {
    final englishWords = [
      'the',
      'is',
      'a',
      'in',
      'on',
      'for',
      'with',
      'using',
      'find',
      'value',
      'list',
      'given',
      'following',
      'return',
      'result',
      'what',
      'how',
      'create',
      'when',
      'where',
      'why',
      'explain',
      'code',
      'snippet',
      'write',
      'below',
      'each',
      'all',
      'any',
    ];
    final lower = text.toLowerCase();
    for (final word in englishWords) {
      if (lower.contains(' $word ') ||
          lower.startsWith('$word ') ||
          lower.endsWith(' $word')) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> _sanitize(
    Map<String, dynamic> data,
    String tech,
    String level,
  ) {
    String cleanField(dynamic val) {
      String s = val?.toString().trim() ?? '';
      final noise = [
        tech,
        level,
        tech.toUpperCase(),
        level.toUpperCase(),
        tech.toLowerCase(),
        level.toLowerCase(),
      ];
      for (final n in noise) {
        if (s.endsWith(n)) {
          s = s.substring(0, s.length - n.length).trim();
        }
      }
      return s;
    }

    return {
      'title': cleanField(data['title']),
      'question': cleanField(data['question']),
      'code_snippet': cleanField(data['code_snippet']),
      'correct_answer': cleanField(data['correct_answer']),
    };
  }

  Map<String, dynamic>? _safeParse(String content) {
    try {
      return jsonDecode(content);
    } catch (_) {
      try {
        final match = RegExp(r'\{[\s\S]*\}').firstMatch(content);
        if (match != null) {
          return jsonDecode(match.group(0)!);
        }
      } catch (__) {}
      return null;
    }
  }

  Future<Map<String, dynamic>?> _callApi(
    String url,
    String apiKey,
    String model,
    String prompt,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              "model": model,
              "temperature": 0.4,
              "messages": [
                {
                  "role": "system",
                  "content":
                      "You are a strict technical generator. Return ONLY JSON.",
                },
                {"role": "user", "content": prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final content = body['choices'][0]['message']['content'];

      return _safeParse(content);
    } catch (_) {
      return null;
    }
  }
}

@riverpod
AiChallengeService aiChallengeService(Ref ref) {
  return AiChallengeService();
}
