import 'package:genzeb/features/account/domain/models/account_models.dart';

abstract class AccountRepository {
  /// Returns the profile for an existing session, or null when signed out.
  Future<UserProfile?> restoreSession();

  /// Runs the Google SSO flow. Returns null if the user cancelled.
  Future<UserProfile?> signInWithGoogle();

  Future<void> signOut();

  /// Permanently deletes the signed-in account on the backend, then signs
  /// out. Throws when the backend refuses.
  Future<void> deleteAccount();

  /// The user's active plan code; falls back to freemium (which the backend
  /// auto-provisions on signup).
  Future<String> fetchPlanCode(String userId);
}
