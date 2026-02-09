import 'package:flutter/material.dart';

class CustomFloatingActionButton extends StatefulWidget {
  final VoidCallback onLoginTap;
  final VoidCallback onSignUpTap;

  const CustomFloatingActionButton({
    super.key,
    required this.onLoginTap,
    required this.onSignUpTap,
  });

  @override
  State<CustomFloatingActionButton> createState() =>
      _CustomFloatingActionButtonState();
}

class _CustomFloatingActionButtonState
    extends State<CustomFloatingActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: 0.125).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Sign Up Button
        ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: FloatingActionButton.extended(
              onPressed: () {
                _toggleMenu();
                widget.onSignUpTap();
              },
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF00897B),
              icon: const Icon(Icons.person_add),
              label: const Text(
                'Sign Up',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              heroTag: 'signup',
            ),
          ),
        ),

        // Login Button
        ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: FloatingActionButton.extended(
              onPressed: () {
                _toggleMenu();
                widget.onLoginTap();
              },
              backgroundColor: const Color(0xFF00897B),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.login),
              label: const Text(
                'Login',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              heroTag: 'login',
            ),
          ),
        ),

        // Main Toggle Button
        RotationTransition(
          turns: _rotationAnimation,
          child: FloatingActionButton(
            onPressed: _toggleMenu,
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
            child: AnimatedIcon(
              icon: AnimatedIcons.menu_close,
              progress: _controller,
              size: 28,
            ),
          ),
        ),
      ],
    );
  }
}