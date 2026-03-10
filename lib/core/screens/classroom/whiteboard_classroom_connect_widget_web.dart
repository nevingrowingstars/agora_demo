import 'dart:io';

import 'package:agora_demo/core/state/media/media_session_notifier.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ClassroomConnectWidgetWeb extends ConsumerStatefulWidget {
  const ClassroomConnectWidgetWeb({super.key});

  @override
  ConsumerState<ClassroomConnectWidgetWeb> createState() =>
      _ClassroomConnectWidgetWebState();
}

class _ClassroomConnectWidgetWebState
    extends ConsumerState<ClassroomConnectWidgetWeb> {
  // GlobalKey for the timer button to position the popup

  // --- STEP 1: Implement initState to fetch the data ---
  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to ensure the widget is built before the call.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        GSLogger.log("ClassroomConnectWidgetWeb: Fetching peer details...");
        // is established (DataChannelOpenedEvent in MediaSessionNotifier)
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    
    // The widget now gets its connection status directly from the provider.
    // The `status` parameter is no longer needed.

    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 2,
      ),
      decoration: BoxDecoration(
        color: Colors.blueAccent,
      ),
      child: Row(
        // This pushes the logo to the left and the buttons to the right.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment:
            CrossAxisAlignment.center, // Keep them vertically centered
        children: [
          

          
          SizedBox(width: 0.3),


        ],
      ),
    );
  }

  

  Future<void> endSession(WidgetRef ref) async {
    GSLogger.info("ClassroomConnectWidgetWeb.endSession called ");

    // 3. If sharing, stop it and notify peer.
    final mediaState = ref.read(mediaSessionProvider).valueOrNull;
    if (mediaState?.isLocalUserSharingScreen == true) {
      await ref.read(mediaSessionProvider.notifier).stopScreenShare();
    }
  }
}
