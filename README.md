# agora_demo

A new Flutter project.

## Getting Started

#### Flutter version 

% flutter --version

Flutter 3.27.3 • channel stable • https://github.com/flutter/flutter.git

Framework • revision c519ee916e (1 year, 2 months ago) • 2025-01-21 10:32:23 -0800

Engine • revision e672b006cb

Tools • Dart 3.6.1 • DevTools 2.40.2


#### Building the App

Modify the agora_config.dart (lib/core/config) to modify the ApiId and token
  
    flutter clean

    flutter pub get
   
    flutter build web

#### Run the App

    flutter run -d chrome


Once the application starts, you will see an option to join the classroom either as a Tutor or as a Student. Log in as a Tutor on one machine and as a Student on another machine.

Select the audio input, audio output, and video device from the available list.

Grant permission for the microphone and camera when prompted. If a warning message still appears, click the “Retry Media Check” button to refresh the device status.

After joining the classroom as a Tutor or Student, you can change the selected devices using the “Settings” button located at the top of the screen.


