import 'package:agora_demo/core/config/session_role_enum.dart';
import 'package:agora_demo/core/screens/classroom/classroom_device_setup_screen.dart';
import 'package:agora_demo/core/screens/role_selection_screen.dart';
import 'package:agora_demo/core/state/router/classroom_initializer.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:agora_demo/main.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// This provider is to avoid showing the confirmation message to
// leave the session when user click Exit as it will call
// onExit() from goRouter.

final isExitApprovedProvider = StateProvider<bool>((ref) => false);

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const RoleSelectionScreen(),
      ),
      GoRoute(
          path: '/dashboard',
          builder: (context, state) =>
              const MainDashboardPage(),
          routes: [
            GoRoute(
              path: 'classroom',
              // Change 'builder' to 'pageBuilder'
              pageBuilder: (context, state) {
                // NoTransitionPage disables the swipe gesture on iOS because there is no transition.
                return const NoTransitionPage(
                  child: ClassroomWebInitializer(),
                );
              },
              // --- ADD THIS HANDLER ---
              onExit: (BuildContext context, GoRouterState state) async {
                GSLogger.info("Router: onExit triggered for Classroom.");

                // Check if exit was already approved (e.g., from Logout button)
                final isApproved = ref.read(isExitApprovedProvider);
                if (isApproved) {
                  // Reset the flag and allow exit without dialog
                  ref.read(isExitApprovedProvider.notifier).state = false;
                  return true;
                }

                // 3. Show Confirmation Dialog
                // Use the context provided by onExit to show the dialog.
                final bool? confirmLeave = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false, // Force a choice
                  builder: (dialogContext) => AlertDialog(
                    title: const Text("Leave Classroom?"),
                    content: const Text(
                        "Your session will end and you will be disconnected."),
                    actions: [
                      TextButton(
                        // Return FALSE to stay
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text("Stay"),
                      ),
                      TextButton(
                        // Return TRUE to leave
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style:
                            TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text("Leave"),
                      ),
                    ],
                  ),
                );

                // 4. Check Result
                // If null (dismissed) or false, cancel the navigation.
                if (confirmLeave != true) {
                  return false; // Tells GoRouter: "Do not pop this route."
                }
                // 5. Perform Cleanup
                try {
                  await endSession();
                  GSLogger.log("Router: Cleanup successful.");
                } catch (e) {
                  GSLogger.log("Router: Cleanup failed: $e");
                }
                // 6. Return true to allow the navigation to proceed (pop the page).
                return true;
              },
              redirect: (BuildContext context, GoRouterState state) async {
                // We can't easily check Providers here async easily without a
                // complex setup.But we can check SharedPreferences
                // synchronously-ish or trust the Initializer.
                // BETTER APPROACH: Let the Initializer handle the redirect.
                return null;
              },
            ),
            GoRoute(
                path: 'mediasetup',
                builder: (context, state) {
                  // Parse role from query parameter, default to tutor
                  final roleParam = state.uri.queryParameters['role'];
                  final role = roleParam == 'student' 
                      ? SessionRole.student 
                      : SessionRole.tutor;
                  return ClassroomDeviceSetupScreen(role: role);
                },
                onExit: (BuildContext context, GoRouterState state) async {
                  GSLogger.info("GoRouter.onExit setup");
                  return true;
                }),
            
          ]),
    ],
  );
});

Future<void> endSession() async {
  GSLogger.log("endSession called ");
  GSLogger.info("Router: Cleanup successful.");
}
