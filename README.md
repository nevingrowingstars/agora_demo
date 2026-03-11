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


Once the application is started, you will see an option to join classroom as Tutor or as a Student. Login as a Tutor from one machine and as Student from another machine. 

Select the audio input, audio output and video device from the list. 

Grant the microphone and camera permission. If it still shows warning, click on “Retry Media Check” button to update. 

Once the user is joined as Tutor or as Student, you can use the Settings to change the device using the “Settings” button provided on the top,

