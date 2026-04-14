import 'package:flutter/material.dart';
import '../../config/theme.dart';

class SecretScreen extends StatelessWidget {
  const SecretScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('???'),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
      ),
      body: const Center(
        child: Text(
          'Coming Soon',
          style: TextStyle(
            fontSize: 18,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
