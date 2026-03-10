class MediaAvailabilityStatus {
  final bool audioAvailable;
  final bool videoAvailable;
  final String? audioError;
  final String? videoError;
  final bool isChecking;

  const MediaAvailabilityStatus({
    required this.audioAvailable,
    required this.videoAvailable,
    this.audioError,
    this.videoError,
    this.isChecking = false,
  });

  /// Initial state - nothing checked yet
  factory MediaAvailabilityStatus.initial() => const MediaAvailabilityStatus(
    audioAvailable: false,
    videoAvailable: false,
    isChecking: false,
  );

  /// Checking state - media check in progress
  factory MediaAvailabilityStatus.checking() => const MediaAvailabilityStatus(
    audioAvailable: false,
    videoAvailable: false,
    isChecking: true,
  );

  /// At least one media type is available
  bool get anyMediaAvailable => audioAvailable || videoAvailable;

  /// Both audio and video are available
  bool get allMediaAvailable => audioAvailable && videoAvailable;

  /// Has issues (not checking and not all media available)
  bool get hasIssues => !isChecking && !allMediaAvailable;

  /// Can join with media (at least one available)
  bool get canJoinWithMedia => anyMediaAvailable;

  /// Can always join without media (fallback option)
  bool get canJoinWithoutMedia => true;

  /// Is audio permission denied?
  bool get isAudioPermissionDenied {
    final error = audioError?.toLowerCase();
    return error != null && error.contains('permission');
  }

  /// Is video permission denied?
  bool get isVideoPermissionDenied {
    final error = videoError?.toLowerCase();
    return error != null && error.contains('permission');
  }

  /// Is audio in use by another app?
  bool get isAudioInUse {
    final error = audioError?.toLowerCase();
    if (error == null) return false;
    return error.contains('in use') || error.contains('another application');
  }

  /// Is video in use by another app?
  bool get isVideoInUse {
    final error = videoError?.toLowerCase();
    if (error == null) return false;
    return error.contains('in use') || error.contains('another application');
  }

  /// Get user-friendly suggestion based on errors
  String? get suggestion {
    if (isChecking) return null;
    if (allMediaAvailable) return null;

    final suggestions = <String>[];

    if (isAudioPermissionDenied || isVideoPermissionDenied) {
      suggestions.add('Grant permission in browser settings');
    }

    if (isAudioInUse || isVideoInUse) {
      suggestions.add('Close other apps using camera/microphone (Teams, Zoom, etc.)');
    }

    if (!audioAvailable ) {
      suggestions.add('You can still join without audio/video and use any external tool for communication');
    }

    return suggestions.isNotEmpty ? suggestions.join('\n') : null;
  }

  

  /// CopyWith for immutable updates
  MediaAvailabilityStatus copyWith({
    bool? audioAvailable,
    bool? videoAvailable,
    String? audioError,
    String? videoError,
    bool? isChecking,
    bool clearAudioError = false,
    bool clearVideoError = false,
  }) {
    return MediaAvailabilityStatus(
      audioAvailable: audioAvailable ?? this.audioAvailable,
      videoAvailable: videoAvailable ?? this.videoAvailable,
      audioError: clearAudioError ? null : (audioError ?? this.audioError),
      videoError: clearVideoError ? null : (videoError ?? this.videoError),
      isChecking: isChecking ?? this.isChecking,
    );
  }

  @override
  String toString() {
    return 'MediaAvailabilityStatus('
        'audio: $audioAvailable, '
        'video: $videoAvailable, '
        'isChecking: $isChecking, '
        'audioError: $audioError, '
        'videoError: $videoError)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MediaAvailabilityStatus &&
        other.audioAvailable == audioAvailable &&
        other.videoAvailable == videoAvailable &&
        other.audioError == audioError &&
        other.videoError == videoError &&
        other.isChecking == isChecking;
  }

  @override
  int get hashCode {
    return Object.hash(
      audioAvailable,
      videoAvailable,
      audioError,
      videoError,
      isChecking,
    );
  }
}