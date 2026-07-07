import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzebet/features/profile/domain/models/auth_models.dart';

class AuthController extends StateNotifier<AuthSession> {
  AuthController() : super(const AuthSession(status: AuthStatus.guest));

  void signInWithPhone(String phoneNumber) {
    state = AuthSession(
      status: AuthStatus.authenticated,
      userId: 'user-${phoneNumber.hashCode}',
      phoneNumber: phoneNumber,
    );
  }

  void signOut() {
    state = const AuthSession(status: AuthStatus.guest);
  }
}
