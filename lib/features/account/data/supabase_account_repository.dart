import 'package:genzeb/core/config/app_config.dart';
import 'package:genzeb/core/logging/app_logger.dart';
import 'package:genzeb/features/account/domain/models/account_models.dart';
import 'package:genzeb/features/account/domain/repositories/account_repository.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Google SSO via Supabase Auth: the native Google flow yields an ID token,
/// which Supabase verifies and exchanges for its own session.
class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository();

  SupabaseClient get _client => Supabase.instance.client;

  final GoogleSignIn _google = GoogleSignIn(
    serverClientId: AppConfig.googleServerClientId,
    scopes: const ['email', 'profile'],
  );

  @override
  Future<UserProfile?> restoreSession() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return _profileFromUser(user);
  }

  @override
  Future<UserProfile?> signInWithGoogle() async {
    final googleUser = await _google.signIn();
    if (googleUser == null) return null; // user cancelled

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw const AuthException(
        'Google did not return an ID token. Check GOOGLE_SERVER_CLIENT_ID '
        'is the WEB client ID from the same Google Cloud project.',
      );
    }

    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );
    final user = response.user;
    if (user == null) {
      throw const AuthException('Supabase returned no user for the session.');
    }
    return _profileFromUser(user);
  }

  @override
  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (error) {
      AppLogger.info('auth', 'Google signOut failed (ignored): $error');
    }
    await _client.auth.signOut();
  }

  @override
  Future<void> deleteAccount() async {
    await _client.rpc<void>('delete_my_account');
    await signOut();
  }

  @override
  Future<String> fetchPlanCode(String userId) async {
    try {
      final row = await _client
          .from('subscriptions')
          .select('plan_code')
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();
      final code = row?['plan_code'] as String?;
      return code ?? PlanCatalog.freemiumCode;
    } catch (error) {
      // Offline or table missing: the app must keep working, so degrade to
      // the plan every account is provisioned with.
      AppLogger.info('auth', 'fetchPlanCode failed, using freemium: $error');
      return PlanCatalog.freemiumCode;
    }
  }

  UserProfile _profileFromUser(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return UserProfile(
      id: user.id,
      email: user.email ?? '',
      displayName: (metadata['full_name'] ?? metadata['name']) as String?,
      photoUrl: (metadata['avatar_url'] ?? metadata['picture']) as String?,
    );
  }
}
