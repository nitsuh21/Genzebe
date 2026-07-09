import 'package:genzeb/core/config/app_config.dart';

/// Centralised AI configuration. The app-provided Gemini key comes from
/// dart-defines or the bundled env.json (see [AppConfig]); users may still
/// store a personal key from Profile. Free keys:
/// https://aistudio.google.com/app/apikey
class AiConfig {
  AiConfig._();

  /// The effective app-provided Gemini key: dart-define or the bundled
  /// env.json, both resolved by [AppConfig.load] at startup.
  static String get bundledGeminiKey => AppConfig.geminiApiKey.trim();

  /// Whether the app ships with a usable AI key.
  static bool get hasBundledKey => bundledGeminiKey.isNotEmpty;

  /// Gemini model used across the app.
  /// Keep this to a model name supported by v1beta endpoints.
  static const String geminiModel = 'gemini-2.5-flash';
}
