import 'package:agora_demo/core/config/session_role_enum.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Growing Stars Whiteboard"),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Select Your Role",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            Wrap(
              spacing: 40,
              runSpacing: 30,
              children: [
                _buildRoleButton(
                  context,
                  title: "Tutor",
                  icon: Icons.school,
                  role: SessionRole.tutor,
                ),
                _buildRoleButton(
                  context,
                  title: "Student",
                  icon: Icons.person,
                  role: SessionRole.student,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required SessionRole role,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        ),
        onPressed: () {
          final roleParam = role == SessionRole.student ? 'student' : 'tutor';
          context.go('/dashboard/mediasetup?role=$roleParam');
        },
        icon: Icon(
          icon,
          size: 32,
        ),
        label: Text(
          title,
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
