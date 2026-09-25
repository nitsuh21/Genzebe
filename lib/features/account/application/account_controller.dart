import 'dart:async';

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
      } else {
        state = state.copyWith(status: AuthStatus.localOnly);
      }
      return;
    }
    // A configured build must never resurrect the preview-only demo session.
    final hygiene = await SharedPreferences.getInstance();
    if (hygiene.getBool(_demoSignedInPref) ?? false) {
      await hygiene.setBool(_demoSignedInPref, false);
    }
    try {
      final profile = await repository.restoreSession();
      if (profile != null) {
        // Never hold the splash screen on the network: an expired token
        // offline makes the client retry for a long time. Show the app now
        // on the free plan and upgrade the plan when the backend answers.
        state = state.copyWith(status: AuthStatus.signedIn, profile: profile);
        unawaited(_refreshPlan(repository, profile.id));
        return;
      }
    } catch (error) {
      AppLogger.info('auth', 'Session restore failed: $error');
    }
    // No account is required: without a session the app simply runs on
    // this device. Sign-in is offered in Profile for plans and backup.
    state = state.copyWith(status: AuthStatus.localOnly);
  }

  static const _planTimeout = Duration(seconds: 8);

  Future<void> _refreshPlan(AccountRepository repository, String userId) async {
    try {
      final planCode =
          await repository.fetchPlanCode(userId).timeout(_planTimeout);
      if (!mounted || state.profile?.id != userId) return;
      state = state.copyWith(planCode: planCode);
    } catch (error) {
      AppLogger.info('auth', 'Plan refresh skipped: $error');
    }
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
      state = state.copyWith(
        status: AuthStatus.signedIn,
        profile: profile,
        busy: false,
      );
      unawaited(_refreshPlan(repository, profile.id));
      return true;
    } catch (error) {
      AppLogger.info('auth', 'Google sign-in failed: $error');
      // Surface the real cause — OAuth misconfiguration (wrong SHA-1 /
      // client id) is indistinguishable from a network blip otherwise.
      final detail = error.toString().replaceAll(RegExp(r'\s+'), ' ');
      state = state.copyWith(
        busy: false,
        error: 'Sign-in failed: '
            '${detail.length > 160 ? '${detail.substring(0, 160)}…' : detail}',
      );
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _repository?.signOut();
    } catch (error) {
      AppLogger.info('auth', 'Sign-out error (ignored): $error');
    }
    await _toLocalOnly();
  }

  /// Deletes the account on the backend (Play's account-deletion
  /// requirement). On-device data is untouched — it never left the phone —
  /// and the app keeps working without an account. Returns false on failure
  /// with the reason in [AccountState.error].
  Future<bool> deleteAccount() async {
    final repository = _repository;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await repository?.deleteAccount();
      await _toLocalOnly();
      return true;
    } catch (error) {
      AppLogger.info('auth', 'Account deletion failed: $error');
      state = state.copyWith(
        busy: false,
        error: 'Could not delete your account. Check your connection and '
            'try again.',
      );
      return false;
    }
  }

  Future<void> _toLocalOnly() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_demoSignedInPref, false);
    state = state.copyWith(
      status: AuthStatus.localOnly,
      clearProfile: true,
      planCode: PlanCatalog.freemiumCode,
      clearError: true,
      busy: false,
    );
  }

  void dismissError() {
    state = state.copyWith(clearError: true);
  }
}
