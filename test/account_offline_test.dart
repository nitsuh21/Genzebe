import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/features/account/application/account_controller.dart';
import 'package:genzeb/features/account/domain/models/account_models.dart';
import 'package:genzeb/features/account/domain/repositories/account_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A signed-in session whose backend never answers — an expired token with
/// no connectivity, which is common on Ethiopian mobile data.
class _OfflineRepository implements AccountRepository {
  _OfflineRepository({this.signedIn = true});

  final bool signedIn;

  @override
  Future<UserProfile?> restoreSession() async => signedIn
      ? const UserProfile(id: 'u1', email: 'someone@example.com')
      : null;

  @override
  Future<String> fetchPlanCode(String userId) => Completer<String>().future;

  @override
  Future<UserProfile?> signInWithGoogle() async => null;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

Future<AuthStatus> _settledStatus(AccountController controller) async {
  for (var i = 0; i < 50; i++) {
    if (controller.state.status != AuthStatus.initializing) break;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return controller.state.status;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('startup never waits on the backend', () async {
    final controller = AccountController(repository: _OfflineRepository());
    expect(await _settledStatus(controller), AuthStatus.signedIn);
    expect(controller.state.planCode, PlanCatalog.freemiumCode);
    controller.dispose();
  });

  test('no session means the app runs without an account', () async {
    final controller =
        AccountController(repository: _OfflineRepository(signedIn: false));
    expect(await _settledStatus(controller), AuthStatus.localOnly);
    controller.dispose();
  });
}
