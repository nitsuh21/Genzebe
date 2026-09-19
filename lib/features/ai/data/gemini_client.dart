import 'dart:convert';

import 'package:http/http.dart' as http;

class GeminiException implements Exception {
  GeminiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GeminiChatTurn {
  const GeminiChatTurn({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;
}

/// Thin REST client for Google's Gemini `generateContent` endpoint.
class GeminiClient {
  GeminiClient(
      {http.Client? httpClient, this.model = 'gemini-1.5-flash-latest'})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String model;

  static const _base =
      'https://generativelanguage.googleapis.com/v1beta/models';

  Future<String> generate({
    required String apiKey,
    required String systemInstruction,
    required List<GeminiChatTurn> history,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw GeminiException('Missing Gemini API key.');
    }
    final uri = Uri.parse('$_base/$model:generateContent?key=$apiKey');
    final body = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': systemInstruction},
        ],
      },
      'contents': [
        for (final turn in history)
          {
            'role': turn.fromUser ? 'user' : 'model',
            'parts': [
              {'text': turn.text},
            ],
          },
      ],
      'generationConfig': {
        'temperature': 0.4,
        'maxOutputTokens': 800,
      },
    };

    http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));
    } catch (error) {
      throw GeminiException('Network error reaching Gemini: $error');
    }

    if (response.statusCode == 400) {
      throw GeminiException(
        'Gemini rejected the request (check your API key is valid).',
      );
    }
    if (response.statusCode == 429) {
      throw GeminiException('Gemini rate limit reached. Try again shortly.');
    }
    if (response.statusCode >= 300) {
      throw GeminiException(
        'Gemini error ${response.statusCode}: ${_safeError(response.body)}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      final feedback = decoded['promptFeedback'];
      throw GeminiException(
        'Gemini returned no answer${feedback == null ? '.' : ' ($feedback).'}',
      );
    }
    final content = (candidates.first as Map<String, dynamic>)['content']
        as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    final text = parts
        ?.map((part) => (part as Map<String, dynamic>)['text'] as String? ?? '')
        .join('\n')
        .trim();
    if (text == null || text.isEmpty) {
      throw GeminiException('Gemini returned an empty answer.');
    }
    return text;
  }

  String _safeError(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      return error?['message'] as String? ?? body;
    } catch (_) {
      return body;
    }
  }
}
