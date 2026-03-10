import 'package:agora_demo/core/config/agora_config.dart';
import 'package:agora_demo/core/model/agora_config.dart';

class AgoraConfigService {
  // Use your existing constant for the base URL

  Future<AgoraConfig> fetchConfig() async {
    return AgoraConfig(
      appId: AgoraConstants.appId,
      token:AgoraConstants.token,
      channelId: AgoraConstants.channelId
    );
  }
}
