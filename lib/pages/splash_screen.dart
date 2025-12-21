import 'package:flutter/material.dart';
import 'dart:async';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // Color palette
  final Color darkGreen = const Color(0xFF456028);
  final Color mediumGreen = const Color(0xFF94A65E);
  final Color creamBackground = const Color(0xFFF8F9FA);

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _animationController.forward();

    _redirectToLogin();
  }

  Future<void> _redirectToLogin() async {
    // Tunggu 3 detik untuk animasi splash screen
    await Future.delayed(const Duration(milliseconds: 3000));

    if (mounted) {
      // Redirect ke login page dengan animasi fade
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamBackground,
      body: Stack(
        children: [
          // Decorative corner graphic - top right (optional, bisa dihapus jika tidak ada asset)
          Positioned(
            top: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: mediumGreen.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(100),
                  ),
                ),
              ),
            ),
          ),

          // Decorative corner graphic - bottom left (optional, bisa dihapus jika tidak ada asset)
          Positioned(
            bottom: 0,
            left: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: darkGreen.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(100),
                  ),
                ),
              ),
            ),
          ),

          // Main Content
          Center(
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo dengan container background
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.eco_rounded,
                            size: 100,
                            color: darkGreen,
                          ),
                        ),

                        const SizedBox(height: 30),

                        // App Title - HydroGrow
                        Text(
                          'HydroGrow',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: darkGreen,
                            letterSpacing: -0.5,
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Subtitle
                        Text(
                          'Admin System',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: mediumGreen,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),

                        const SizedBox(height: 50),

                        // Loading Indicator
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              mediumGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Version Text at Bottom
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                'Version 1.0.0',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}