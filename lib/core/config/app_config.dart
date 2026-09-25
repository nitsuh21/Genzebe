import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

/// Backend configuration.
///
/// Resolution order, so every workflow just works with no flags:
///  1. `--dart-define` / `--dart-define-from-file` values (release builds,
///     CI) — these always win when present.
///  2. The bundled `env.json` asset, loaded at runtime — this is what makes
///     a plain `flutter run` from the IDE fully configured.
///
/// When neither source provides values the app runs in local mode:
/// everything on-device works, account features show as unavailable.
class AppConfig {
  AppConfig._();

  static const String _defineUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _defineAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _defineGoogleClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const String _defineGeminiKey =
      String.fromEnvironment('GEMINI_API_KEY');

  static String _supabaseUrl = _defineUrl;
  static String _supabaseAnonKey = _defineAnonKey;
  static String _googleServerClientId = _defineGoogleClientId;
  static String _geminiApiKey = _defineGeminiKey;

  static String get supabaseUrl => _supabaseUrl;
  static String get supabaseAnonKey => _supabaseAnonKey;

  /// The *web* OAuth client ID from Google Cloud console. Required for
  /// Google sign-in to return an ID token that Supabase can verify.
  static String get googleServerClientId => _googleServerClientId;

  /// Development-only Gemini key, from `--dart-define=GEMINI_API_KEY=...`.
  /// Never read from the bundled env.json: assets ship inside the APK, and
  /// the AI assistant is a Plus perk that free builds must not expose.
  static String get geminiApiKey => _geminiApiKey;

  /// Master switch for sign-in and everything behind it (plans, Plus, AI,
  /// account deletion). Off for the first Play release: the app is fully
  /// local, never initialises Supabase and never touches the network. The
  /// code stays; build with `--dart-define=GENZEB_ACCOUNTS=true` to bring it
  /// back (and restore INTERNET in AndroidManifest.xml).
  static const bool accountsEnabled =
      bool.fromEnvironment('GENZEB_ACCOUNTS', defaultValue: false);

  static bool get isBackendConfigured =>
      accountsEnabled &&
      _supabaseUrl.trim().isNotEmpty &&
      _supabaseAnonKey.trim().isNotEmpty;

  static bool get isGoogleSignInConfigured =>
      isBackendConfigured && _googleServerClientId.trim().isNotEmpty;

  @visibleForTesting
  static void overrideForTesting({String? geminiApiKey}) {
    if (geminiApiKey != null) _geminiApiKey = geminiApiKey;
  }

  /// Fills any value missing from dart-defines with the bundled env.json.
  /// Safe to call when the asset is absent (tests, unconfigured clones).
  static Future<void> load() async {
    if (_supabaseUrl.isNotEmpty &&
        _supabaseAnonKey.isNotEmpty &&
        _googleServerClientId.isNotEmpty) {
      return; // fully provided at build time
    }
    try {
      final raw = await rootBundle.loadString('env.json');
      final env = jsonDecode(raw) as Map<String, dynamic>;
      String fromAsset(String key) {
        final value = (env[key] as String?)?.trim() ?? '';
        // Ignore untouched placeholder values from env.example.json.
        if (value.contains('YOURPROJECT') ||
            value.startsWith('optional') ||
            value.contains('paste')) {
          return '';
        }
        return value;
      }

      if (_supabaseUrl.isEmpty) _supabaseUrl = fromAsset('SUPABASE_URL');
      if (_supabaseAnonKey.isEmpty) {
        _supabaseAnonKey = fromAsset('SUPABASE_ANON_KEY');
      }
      if (_googleServerClientId.isEmpty) {
        _googleServerClientId = fromAsset('GOOGLE_SERVER_CLIENT_ID');
      }
    } catch (_) {
      // No bundled env.json — stay with whatever the defines provided.
    }
  }
}
