import 'package:flutter/material.dart';

@immutable
class SessionInfo {
  final String roomId;
  // You could add other properties here in the future
  // final String sessionTitle;

  const SessionInfo({required this.roomId});
}
