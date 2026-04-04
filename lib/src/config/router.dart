import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/nutrition_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final path = state.matchedLocation;
      final isAuthRoute =
          path == '/login' || path == '/sign-up' || path == '/forgot-password';
      final isNutritionRoute = path == '/nutrition';

      return authState.when(
        data: (user) {
          if (user == null) {
            return isAuthRoute ? null : '/login';
          }
          return isNutritionRoute ? null : '/nutrition';
        },
        loading: () => null,
        error: (_, _) => '/login',
      );
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        name: 'sign-up',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/nutrition',
        name: 'nutrition',
        builder: (context, state) => const NutritionScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Khong tim thay trang: ${state.uri}')),
    ),
  );
});