import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF102744), Color(0xFF1A3D70), Color(0xFF2864E8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: -90,
              right: -70,
              child:
                  _Orb(size: 270, color: Colors.white.withValues(alpha: .045)),
            ),
            Positioned(
              bottom: -130,
              left: -90,
              child:
                  _Orb(size: 340, color: Colors.white.withValues(alpha: .04)),
            ),
            Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final scale = 1 + (_controller.value * .045);
                  return Transform.scale(scale: scale, child: child);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 94,
                      height: 94,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(29),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .2),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .12),
                            blurRadius: 30,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_shipping_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'HaulMate',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'FREIGHT, IN MOTION',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .68),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 40,
              right: 40,
              bottom: 54,
              child: Column(
                children: [
                  SizedBox(
                    width: 150,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: Colors.white.withValues(alpha: .16),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  Text(
                    'YOUR JOURNEY STARTS HERE',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .55),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  final double size;
  final Color color;

  const _Orb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
