class AgoraConfig {
  final String appId;
  final String? token;
  final String channelId;

  AgoraConfig({required this.appId, this.token, required this.channelId});

  factory AgoraConfig.fromJson(Map<String, dynamic> json) {
    return AgoraConfig(
      appId: json['appId'] as String,
      token: json['token'] as String?,
      channelId: json['channelId'] as String? ?? 'gswhiteboard',
    );
  }
}