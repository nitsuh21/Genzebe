import 'dart:async';

import 'package:flutter/services.dart';

/// Native bridge for system notifications: which transaction a tapped
/// notification points at, and the Android 13+ notification permission.
class NotificationBridge {
  NotificationBridge() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openTransaction' && call.arguments is String) {
        _taps.add(call.arguments as String);
      }
    });
  }

  static const _channel = MethodChannel('genzeb/notifications');
  final _taps = StreamController<String>.broadcast();

  /// Transaction ids from notifications tapped while the app is running.
  Stream<String> get taps => _taps.stream;

  /// The transaction a notification launched the app with (consumed once).
  Future<String?> takeLaunchTransaction() async {
    try {
      return await _channel.invokeMethod<String>('takeLaunchTransaction');
    } on MissingPluginException {
      return null; // tests / non-Android
    }
  }
}
