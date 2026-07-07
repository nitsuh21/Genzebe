import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/core/config/app_config.dart';
import 'package:genzeb/core/logging/app_logger.dart';
import 'package:genzeb/features/account/domain/models/account_models.dart';
import 'package:genzeb/features/account/domain/repositories/account_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountController extends StateNotifier<AccountState> {
  AccountController({AccountRepository? repository})
      : _repository = repository,
        super(
          AccountState(
            status: AuthStatus.initializing,
            backendConfigured: AppConfig.isBackendConfigured,
          ),
        ) {
    _restore();
  }

  static const _localModePref = 'account_local_mode';
  static const _demoSignedInPref = 'account_demo_signed_in';

  /// Null when the backend isn't configured — the app then runs local-only.
  final AccountRepository? _repository;

  Future<void> _restore() async {
    final repository = _repository;
    if (repository == null) {
      // No backend: still run the full onboarding/sign-in journey, restoring
      // whichever choice (demo sign-in or offline) was made before.
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_demoSignedInPref) ?? false) {
        state = state.copyWith(
          status: AuthStatus.signedIn,
          profile: _demoProfile,
        );
      } else if (prefs.getBool(_localModePref) ?? false) {
        state = state.copyWith(status: AuthStatus.localOnly);
      } else {
        state = state.copyWith(status: AuthStatus.signedOut);
      }
      return;
    }
    try {
      final profile = await repository.restoreSession();
      if (profile != null) {
        final planCode = await repository.fetchPlanCode(profile.id);
        state = state.copyWith(
          status: AuthStatus.signedIn,
          profile: profile,
          planCode: planCode,
        );
        return;
      }
    } catch (error) {
      AppLogger.info('auth', 'Session restore failed: $error');
    }
    final prefs = await SharedPreferences.getInstance();
    final choseLocal = prefs.getBool(_localModePref) ?? false;
    state = state.copyWith(
      status: choseLocal ? AuthStatus.localOnly : AuthStatus.signedOut,
    );
  }

  /// Demo identity used when the build has no backend configured, so the
  /// full signed-in experience can still be exercised end to end.
  static const _demoProfile = UserProfile(
    id: 'demo-user',
    email: 'abebe.kebede@gmail.com',
    displayName: 'Abebe Kebede',
  );

  Future<bool> signInWithGoogle() async {
    final repository = _repository;
    if (repository == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_localModePref, false);
      await prefs.setBool(_demoSignedInPref, true);
      state = state.copyWith(
        status: AuthStatus.signedIn,
        profile: _demoProfile,
        planCode: PlanCatalog.freemiumCode,
        busy: false,
        clearError: true,
      );
      return true;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      final profile = await repository.signInWithGoogle();
      if (profile == null) {
        state = state.copyWith(busy: false); // cancelled, not an error
        return false;
      }
      final planCode = await repository.fetchPlanCode(profile.id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_localModePref, false);
      state = state.copyWith(
        status: AuthStatus.signedIn,
        profile: profile,
        planCode: planCode,
        busy: false,
      );
      return true;
    } catch (error) {
      AppLogger.info('auth', 'Google sign-in failed: $error');
      state = state.copyWith(
        busy: false,
        error: 'Sign-in failed. Check your connection and try again.',
      );
      return false;
    }
  }

  /// "Explore offline": everything on-device works; account features wait.
  Future<void> continueWithoutAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_localModePref, true);
    state = state.copyWith(status: AuthStatus.localOnly, clearError: true);
  }

  Future<void> signOut() async {
    try {
      await _repository?.signOut();
    } catch (error) {
      AppLogger.info('auth', 'Sign-out error (ignored): $error');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_localModePref, false);
    await prefs.setBool(_demoSignedInPref, false);
    state = state.copyWith(
      status: AuthStatus.signedOut,
      clearProfile: true,
      planCode: PlanCatalog.freemiumCode,
      clearError: true,
    );
  }

  void dismissError() {
    state = state.copyWith(clearError: true);
  }
}
