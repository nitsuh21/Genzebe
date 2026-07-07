/// Centralised AI configuration.
///
/// The Gemini key is provided by the app (not the user). There are two ways to
/// supply it, checked in this order:
///
/// 1. Build-time (recommended, keeps the key out of source control):
///      flutter run --dart-define=GEMINI_API_KEY=your_key_here
///      flutter build apk --dart-define=GEMINI_API_KEY=your_key_here
///
/// 2. In-code fallback: paste the key into [_fallbackGeminiKey] below.
///    Quick for local testing, but it WILL be committed if you push it.
///
/// Get a free key at: https://aistudio.google.com/app/apikey
class AiConfig {
  AiConfig._();

  static const String _dartDefineGeminiKey =
      String.fromEnvironment('GEMINI_API_KEY');

  /// Optional in-code fallback. Paste your Gemini key between the quotes if you
  /// don't want to pass --dart-define every build.
  static const String _fallbackGeminiKey =
      '';

  /// The effective app-provided Gemini key (build-time wins over fallback).
  static String get bundledGeminiKey {
    final fromDefine = _dartDefineGeminiKey.trim();
    if (fromDefine.isNotEmpty) return fromDefine;
    return _fallbackGeminiKey.trim();
  }

  /// Whether the app ships with a usable AI key.
  static bool get hasBundledKey => bundledGeminiKey.isNotEmpty;

  /// Gemini model used across the app.
  /// Keep this to a model name supported by v1beta endpoints.
  static const String geminiModel = 'gemini-2.5-flash';
}
