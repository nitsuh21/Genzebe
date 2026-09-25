import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _askedPref = 'notification_permission_asked_v1';

/// Asks once (Android 13+) for permission to post money in / money out
/// notifications, and only once SMS access exists — without it there is
/// nothing to notify about. Declining is respected; Android settings can
/// change it later.
Future<void> askForNotificationPermissionOnce() async {
  try {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedPref) ?? false) return;
    if (!await Permission.sms.isGranted) return;
    await prefs.setBool(_askedPref, true);
    if (await Permission.notification.isGranted) return;
    await Permission.notification.request();
  } catch (_) {
    // Never let a permission prompt break startup.
  }
}
