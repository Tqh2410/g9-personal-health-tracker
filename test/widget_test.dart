import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:personal_health_diary/main.dart';
import 'package:personal_health_diary/src/models/user.dart';
import 'package:personal_health_diary/src/providers/auth_provider.dart';
import 'package:personal_health_diary/src/services/auth_service.dart';

class _FakeAuthService implements AuthService {
  @override
  Stream<User?> get authStateChanges => const Stream<User?>.empty();

  @override
  User? get currentUser => null;

  @override
  String? get currentUserId => null;

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<User> loginWithEmail({
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> reloadUser() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<User> signInWithGoogle() {
    throw UnimplementedError();
  }

  @override
  Future<User> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('app boots to the auth flow', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(_FakeAuthService())],
        child: const MyApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Đăng nhập'), findsOneWidget);
  });
}
