import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

// Auth Service Provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

// Auth State Provider - Watches user auth state
final authStateProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

// Current User Provider
final currentUserProvider = Provider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.currentUser;
});

// Current User ID Provider
final currentUserIdProvider = Provider<String?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.currentUserId;
});

// Sign Up with Email
final signUpProvider = FutureProvider.family<User, SignUpParams>((
  ref,
  params,
) async {
  final authService = ref.watch(authServiceProvider);
  return authService.signUpWithEmail(
    email: params.email,
    password: params.password,
    firstName: params.firstName,
    lastName: params.lastName,
  );
});

// Login with Email
final loginProvider = FutureProvider.family<User, LoginParams>((
  ref,
  params,
) async {
  final authService = ref.watch(authServiceProvider);
  return authService.loginWithEmail(
    email: params.email,
    password: params.password,
  );
});

// Google Sign-In
final googleSignInProvider = FutureProvider<User>((ref) async {
  final authService = ref.watch(authServiceProvider);
  return authService.signInWithGoogle();
});

// Password Reset
final passwordResetProvider = FutureProvider.family<void, String>((
  ref,
  email,
) async {
  final authService = ref.watch(authServiceProvider);
  return authService.sendPasswordResetEmail(email);
});

// Sign Out
final signOutProvider = FutureProvider<void>((ref) async {
  final authService = ref.watch(authServiceProvider);
  return authService.signOut();
});

// Delete Account
final deleteAccountProvider = FutureProvider<void>((ref) async {
  final authService = ref.watch(authServiceProvider);
  return authService.deleteAccount();
});

// Email Verification
final emailVerificationProvider = FutureProvider<void>((ref) async {
  final authService = ref.watch(authServiceProvider);
  return authService.sendEmailVerification();
});

// Models for parameters
class SignUpParams {
  final String email;
  final String password;
  final String firstName;
  final String lastName;

  SignUpParams({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
  });
}

class LoginParams {
  final String email;
  final String password;

  LoginParams({required this.email, required this.password});
}
