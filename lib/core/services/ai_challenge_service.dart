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
      final key = p['key'];
      if (key == null || key.isEmpty) continue;

      String prompt = basePrompt;

      for (int i = 0; i < 3; i++) {
        final result = await _callApi(p['url']!, key, p['model']!, prompt);

        if (result != null && _isValidChallenge(result, technology)) {
          return _sanitize(result);
        }

        prompt += '''
        
Previous response was INVALID.
Fix the errors:
- Ensure Spanish only
- Ensure exactly one ___
- Ensure answer is real keyword
- Ensure code is valid
        
Generate AGAIN:
''';
      }
    }

    return null;
  }

  String _buildPrompt(String tech, String level) {
    return '''
You are a senior software engineer.

Generate ONE programming challenge.

OUTPUT FORMAT:
{
"title": "...",
"question": "...",
"code_snippet": "...",
"correct_answer": "..."
}

STRICT RULES:
- Question MUST be 100% Spanish
- No English words allowed
- code_snippet must contain EXACTLY ONE ___
- correct_answer must replace ___ exactly
- code must be REAL and VALID syntax for $tech
- NO fake code
- NO explanations
- NO markdown

GOOD EXAMPLE:
{"title":"Constantes","question":"¿Qué palabra se usa para declarar una constante?","code_snippet":"___ PI = 3.14;","correct_answer":"const"}

TECH: $tech
LEVEL: $level

Generate JSON NOW:
''';
  }

  bool _isValidChallenge(Map<String, dynamic> data, String tech) {
    final title = data['title']?.toString().trim() ?? '';
    final question = data['question']?.toString().trim() ?? '';
    final code = data['code_snippet']?.toString().trim() ?? '';
    final answer = data['correct_answer']?.toString().trim() ?? '';

    if ([title, question, code, answer].any((e) => e.isEmpty)) return false;

    if ('___'.allMatches(code).length != 1) return false;

    final test = code.replaceAll('___', answer);
    if (!test.contains(answer)) return false;

    if (answer.length > 40) return false;

    final bad = [
      'null',
      'none',
      'value',
      'variable',
      'code',
      'answer',
      'placeholder',
    ];
    if (bad.contains(answer.toLowerCase())) return false;

    if (code.trim().startsWith('___')) return false;

    if (!_isSpanish(question)) return false;

    if (_isBrokenCode(code, tech)) return false;

    return true;
  }

  bool _isSpanish(String text) {
    final english = [
      'what',
      'how',
      'when',
      'where',
      'why',
      'create',
      'function',
      'return',
      'table',
      'loop',
      'array',
    ];

    final lower = text.toLowerCase();

    for (final w in english) {
      if (lower.contains(w)) return false;
    }

    return true;
  }

  bool _isBrokenCode(String code, String tech) {
    if (tech == 'SQL') {
      if (code.contains('___ CREATE')) return true;
    }
    if (tech == 'JavaScript') {
      if (code.contains('function ___(')) return true;
    }

    return false;
  }

  Map<String, dynamic> _sanitize(Map<String, dynamic> data) {
    return {
      'title': data['title'].toString().trim(),
      'question': data['question'].toString().trim(),
      'code_snippet': data['code_snippet'].toString().trim(),
      'correct_answer': data['correct_answer'].toString().trim(),
    };
  }

  Map<String, dynamic>? _safeParse(String content) {
    try {
      return jsonDecode(content);
    } catch (_) {
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
              "temperature": 0.1,
              "messages": [
                {"role": "system", "content": "Return ONLY valid JSON."},
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
