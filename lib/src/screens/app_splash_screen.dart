import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppSplashScreen extends StatefulWidget {
  const AppSplashScreen({super.key});

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFF),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = Curves.easeInOut.transform(_controller.value);
            final scale = 0.92 + (0.08 * t);
            final opacity = 0.75 + (0.25 * t);
            final angle = math.sin(t * math.pi) * 0.03;

            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.rotate(
                    angle: angle,
                    child: Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          width: 142,
                          height: 142,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            boxShadow: [
                              BoxShadow(
                                color: scheme.primary.withValues(alpha: 0.22),
                                blurRadius: 28,
                                spreadRadius: 1,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset(
                            'assets/branding/splash_logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Personal Health Diary',
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Chăm sóc sức khỏe mỗi ngày',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
