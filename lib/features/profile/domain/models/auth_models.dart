enum AuthStatus { guest, authenticated }

class AuthSession {
  const AuthSession({
    required this.status,
    this.userId,
    this.phoneNumber,
  });

  final AuthStatus status;
  final String? userId;
  final String? phoneNumber;
}
