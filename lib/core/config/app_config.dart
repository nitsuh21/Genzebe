/// Backend configuration, injected at build time so no secrets live in git:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ... \
///     --dart-define=GOOGLE_SERVER_CLIENT_ID=1234-abc.apps.googleusercontent.com
///
/// When these are absent the app runs in local mode: everything works
/// offline, and account/plan features show as unavailable. See SETUP.md.
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// The *web* OAuth client ID from Google Cloud console. Required for
  /// Google sign-in to return an ID token that Supabase can verify.
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static bool get isBackendConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  static bool get isGoogleSignInConfigured =>
      isBackendConfigured && googleServerClientId.trim().isNotEmpty;
}
