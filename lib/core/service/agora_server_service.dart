import 'package:agora_demo/core/model/agora_config.dart';

class AgoraConfigService {
  // Use your existing constant for the base URL

  Future<AgoraConfig> fetchConfig() async {
    return AgoraConfig(
      appId: "AppId",
      token:
          "token",
      channelId: "gswhiteboard",
    );
  }
}
