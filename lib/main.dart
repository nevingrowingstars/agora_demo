import 'dart:async';
import 'dart:io';

import 'package:agora_demo/core/state/router/router_provider.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GSLogger.setLevel(GSLogLevel.info);
  GSLogger.log("GS Agora Demo Started()!!!");
  runApp(
    const ProviderScope(child: AgoraDemoWhiteboardApp()),
  );
}

void guardedMain() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details); // Show in debug console
    // Optionally log to file
    File('gswhiteboard_error_log.txt').writeAsStringSync(
      '${DateTime.now()}: ${details.exception}\n${details.stack}',
      mode: FileMode.append,
    );
  };
  runZonedGuarded(() {
    runApp(const AgoraDemoWhiteboardApp());
  }, (Object error, StackTrace stackTrace) {
    File('gswhiteboard_error_log.txt').writeAsStringSync(
      '${DateTime.now()}: $error\n$stackTrace',
      mode: FileMode.append,
    );
  });
}

class AgoraDemoWhiteboardApp extends ConsumerWidget {
  const AgoraDemoWhiteboardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final router = ref.watch(goRouterProvider);
    
    return MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // `child` here will be whatever GoRouter is currently displaying.
        // We wrap it in our ForceLandscapeWrapper.
        // `child!` is safe because the router always provides a widget.
        return ForceLandscapeWrapper(
          child: child!,
        );
      },
      supportedLocales: const [
        Locale('en', ''), // Add all locales your app supports
      ],
    );
  }
}

class ForceLandscapeWrapper extends StatefulWidget {
  final Widget child;
  const ForceLandscapeWrapper({Key? key, required this.child})
      : super(key: key);

  @override
  State<ForceLandscapeWrapper> createState() => _ForceLandscapeWrapperState();
}

class _ForceLandscapeWrapperState extends State<ForceLandscapeWrapper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _forceLandscape();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// This is called whenever the app's dimensions change, including rotation.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _forceLandscape();
  }

  void _forceLandscape() {
    // This is the core logic.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // This widget just passes its child through. Its real job is in the lifecycle methods.
    return widget.child;
  }
}

class MainDashboardPage extends HookConsumerWidget {
  const MainDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Growing Stars Whiteboard",
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Wrap(
          spacing: 40,
          runSpacing: 30,
          children: [
            _buildToolButton(
              context,
              title: "Classroom",
              icon: Icons.school,
              route: "/dashboard/mediasetup"
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String route,
    bool isLogout = false
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Consumer(
        builder: (context, ref, child) {
          return ElevatedButton.icon(
            onPressed: () async {
              context.go(route);
            },
            icon: Icon(
              icon,
              size: 32,
            ),
            label: Text(
              title,
            ),
          );
        },
      ),
    );
  }
}
