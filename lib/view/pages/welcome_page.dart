import 'package:flutter/material.dart';
import 'package:photo_album/view/pages/sign_in_page.dart';
import 'package:photo_album/view/pages/sign_up_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/welcome_bg.jpg',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 110),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Transform.translate(
                                offset: const Offset(15, 20),
                                child: Container(
                                  width: 200,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.purple.withValues(
                                          alpha: 0.1,
                                        ),
                                        blurRadius: 30,
                                        offset: const Offset(-10, 10),
                                      ),
                                    ],
                                  ),
                                  child: Image.asset('assets/images/logo.png'),
                                ),
                              ),
                            ),
                            const SizedBox(height: 85),
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Color(0xFFFFA726), Color(0xFFEC407A)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ).createShader(Offset.zero & bounds.size),
                              child: const Text(
                                '智能影记',
                                style: TextStyle(
                                  fontSize: 45,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '做自己生活的导演',
                              style: TextStyle(
                                fontSize: 20,
                                color: Color(0xFFF48FB1),
                                letterSpacing: 2,
                              ),
                            ),
                            const Spacer(),
                            _buildStandardButton(
                              context,
                              label: '登录',
                              color: const Color(0xFFF48FB1),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) => const SignInPage(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                            _buildStandardButton(
                              context,
                              label: '注册',
                              color: const Color(0xFFB39DDB),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) => const SignUpPage(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 60),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandardButton(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(27),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }
}
