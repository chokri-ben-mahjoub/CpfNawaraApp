import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _keyPref = 'ai_api_key';
const aiModel = 'claude-sonnet-5-5';
const _endpoint = 'https://api.anthropic.com/v1/messages';

/// Clé d'API de l'assistant, stockée sur l'appareil uniquement (jamais
/// synchronisée ni exportée). `null` : assistant non configuré.
class AiKeyController extends StateNotifier<String?> {
  AiKeyController() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_keyPref);
  }

  Future<void> save(String? key) async {
    final prefs = await SharedPreferences.getInstance();
    final value = key?.trim();
    if (value == null || value.isEmpty) {
      await prefs.remove(_keyPref);
      state = null;
    } else {
      await prefs.setString(_keyPref, value);
      state = value;
    }
  }
}

final aiKeyProvider = StateNotifierProvider<AiKeyController, String?>((ref) => AiKeyController());

class AiException implements Exception {
  /// Clé de traduction du message à afficher.
  final String messageKey;
  const AiException(this.messageKey);
}

class AiMessage {
  final bool fromUser;
  final String text;
  const AiMessage(this.fromUser, this.text);
}

/// Appelle l'API Messages d'Anthropic avec le contexte du laboratoire.
/// Seules les données de [context] (valeurs récentes, seuils, stock) et la
/// conversation quittent l'appareil.
Future<String> askAssistant({
  required String apiKey,
  required String system,
  required List<AiMessage> messages,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .post(
          Uri.parse(_endpoint),
          headers: {
            'content-type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            // Requis pour l'appel direct depuis le navigateur (version web).
            'anthropic-dangerous-direct-browser-access': 'true',
          },
          body: jsonEncode({
            'model': aiModel,
            'max_tokens': 1200,
            'system': system,
            'messages': [
              for (final m in messages) {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text},
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode == 401 || response.statusCode == 403) throw const AiException('aiErrorKey');
    if (response.statusCode == 429) throw const AiException('aiErrorRate');
    if (response.statusCode != 200) throw const AiException('aiErrorGeneric');
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final parts = (body['content'] as List?) ?? const [];
    final text = parts.whereType<Map>().where((p) => p['type'] == 'text').map((p) => p['text']).join('\n').trim();
    if (text.isEmpty) throw const AiException('aiErrorGeneric');
    return text;
  } on AiException {
    rethrow;
  } catch (_) {
    throw const AiException('aiErrorNetwork');
  } finally {
    if (client == null) httpClient.close();
  }
}
