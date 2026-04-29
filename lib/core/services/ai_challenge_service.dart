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
    final prompt = '''
You are a senior software engineer creating fill-in-the-blank programming quizzes for a mobile app.
Your ONLY output must be a single valid JSON object with exactly these 4 keys: title, question, code_snippet, correct_answer.

TECHNOLOGY: $technology
DIFFICULTY: $level

STRICT RULES — violating any rule makes the output invalid:
1. "title": 2-5 words describing ONLY the programming concept (e.g. "Arrow Functions", "List Comprehension"). NEVER include "challenge", "reto", "structure", "beginner", "intermediate", "advanced", or the technology name.
2. "question": A clear question in SPANISH. MUST NOT mention the technology name, difficulty, "reto", or "estructura".
3. "code_snippet": A SHORT real code example (3-8 lines). Use "___" as placeholder for what the user must type. NEVER paste comments indicating the language, metadata, or the question text inside the code.
4. "correct_answer": The EXACT missing token that replaces "___". It must be a real $technology keyword or expression. MUST NEVER be "global", "local", "null", "none", "answer", "keyword", empty, or any generic word. For fill-in-the-blank it is always the EXACT text to replace "___".

EXAMPLES:
Kotlin BEGINNER → {"title":"Variables inmutables","question":"¿Qué palabra clave define una variable inmutable?","code_snippet":"___ nombre = \\"Dev Retos\\"\\nprintln(nombre)","correct_answer":"val"}
Kotlin INTERMEDIATE → {"title":"Clases de datos","question":"¿Qué palabra clave se usa para crear una clase de datos?","code_snippet":"___ class Usuario(val nombre: String, val edad: Int)","correct_answer":"data"}
Python INTERMEDIATE → {"title":"List Comprehension","question":"¿Cuál es la forma correcta de elevar al cuadrado con comprensión de listas?","code_snippet":"cuadrados = [x___ for x in range(1, 6)]","correct_answer":"**2"}
JavaScript BEGINNER → {"title":"Constantes","question":"¿Qué palabra se usa para declarar una constante?","code_snippet":"___ PI = 3.14;","correct_answer":"const"}

NOW generate ONE unique JSON object for $technology at $level difficulty. Output ONLY the JSON, no explanation, no markdown:
''';

    // 1. Intentar con Cerebras (Muy Rápido)
    final cerebrasKey = dotenv.env['CEREBRAS_API_KEY'];
    if (cerebrasKey != null && cerebrasKey.isNotEmpty) {
      print('IA: Intentando con Cerebras...');
      final result = await _callApi(
        'https://api.cerebras.ai/v1/chat/completions',
        cerebrasKey,
        'llama3.1-8b',
        prompt,
        technology,
        level,
      );
      if (result != null) return result;
    }

    // 2. Fallback a Groq
    final groqKey = dotenv.env['GROQ_API_KEY'];
    if (groqKey != null && groqKey.isNotEmpty) {
      print('IA: Usando Fallback de Groq...');
      final result = await _callApi(
        'https://api.groq.com/openai/v1/chat/completions',
        groqKey,
        'llama3-8b-8192',
        prompt,
        technology,
        level,
      );
      if (result != null) return result;
    }

    // 3. Fallback a OpenRouter
    final openrouterKey = dotenv.env['OPENROUTER_API_KEY'];
    if (openrouterKey != null && openrouterKey.isNotEmpty) {
      print('IA: Usando Fallback de OpenRouter...');
      final result = await _callApi(
        'https://openrouter.ai/api/v1/chat/completions',
        openrouterKey,
        'meta-llama/llama-3.1-8b-instruct:free',
        prompt,
        technology,
        level,
      );
      if (result != null) return result;
    }

    print('IA: Todos los proveedores fallaron o están al límite.');
    return null;
  }

  /// Valida que el JSON no tenga campos vacíos ni metadatos contaminantes
  bool _isValidChallenge(
    Map<String, dynamic> data,
    String technology,
    String level,
  ) {
    final title = data['title']?.toString().trim() ?? '';
    final question = data['question']?.toString().trim() ?? '';
    final code = data['code_snippet']?.toString().trim() ?? '';
    final answer = data['correct_answer']?.toString().trim() ?? '';

    // Campos vacíos = inválido
    if (title.isEmpty || question.isEmpty || code.isEmpty || answer.isEmpty) {
      print('IA VALIDATION: Campo vacío. title="$title" answer="$answer"');
      return false;
    }

    // El title no debe contener palabras de metadatos
    final badWords = [
      'reto', 'challenge', 'estructura', 'structure',
      'beginner', 'intermediate', 'advanced',
      level.toLowerCase(), 'programaci',
    ];
    for (final word in badWords) {
      if (title.toLowerCase().contains(word)) {
        print('IA VALIDATION: Title contaminado: "$title"');
        return false;
      }
    }

    // El code_snippet no debe contener el nivel entre comillas
    final levelPatterns = ['"$level"', "'$level'", '| Nivel'];
    for (final pattern in levelPatterns) {
      if (code.contains(pattern)) {
        print('IA VALIDATION: code_snippet contaminado: "$code"');
        return false;
      }
    }

    // La respuesta no debe ser una palabra genérica alucinada
    final genericAnswers = [
      'global', 'local', 'null', 'none', 'answer', 'keyword',
      'variable', 'token', 'value', 'placeholder', 'missing',
      'unknown', 'palabra', 'clave',
    ];
    final answerLower = answer.toLowerCase();
    for (final bad in genericAnswers) {
      if (answerLower == bad) {
        print('IA VALIDATION: correct_answer genérico/alucinado: "$answer"');
        return false;
      }
    }

    // La respuesta no debe ser demasiado larga (más de 80 chars = descripción, no token)
    if (answer.length > 80) {
      print('IA VALIDATION: correct_answer demasiado largo (${answer.length} chars)');
      return false;
    }

    return true;
  }

  Future<Map<String, dynamic>?> _callApi(
    String url,
    String apiKey,
    String model,
    String prompt,
    String technology,
    String level,
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
              "messages": [
                {
                  "role": "system",
                  "content":
                      "You are a helpful API that outputs valid JSON only. No markdown, no explanation, just the JSON object.",
                },
                {"role": "user", "content": prompt},
              ],
              "response_format": {"type": "json_object"},
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final content = body['choices'][0]['message']['content'];
        final data = jsonDecode(content) as Map<String, dynamic>;

        // Validar antes de retornar
        if (_isValidChallenge(data, technology, level)) {
          data['title'] = data['title']?.toString().trim();
          data['question'] = data['question']?.toString().trim();
          data['code_snippet'] = data['code_snippet']?.toString().trim();
          data['correct_answer'] = data['correct_answer']?.toString().trim();
          return data;
        } else {
          print('IA: Respuesta inválida de ${Uri.parse(url).host}, descartada.');
          return null;
        }
      } else {
        print(
          'Error desde ${Uri.parse(url).host} [${response.statusCode}]: ${response.body}',
        );
        return null;
      }
    } catch (e) {
      print('Excepción conectando a ${Uri.parse(url).host}: $e');
      return null;
    }
  }
}

@riverpod
AiChallengeService aiChallengeService(Ref ref) {
  return AiChallengeService();
}
