import 'package:agora_demo/core/config/agora_config.dart';

class AgoraConfig {
  final String appId;
  final String? token;
  final String channelId;

  AgoraConfig({required this.appId, this.token, required this.channelId});

  factory AgoraConfig.fromJson(Map<String, dynamic> json) {
    return AgoraConfig(
      appId: AgoraConstants.appId, // Use constant for appId
      token: AgoraConstants.token,
      channelId: AgoraConstants.channelId,
    );
  }
}