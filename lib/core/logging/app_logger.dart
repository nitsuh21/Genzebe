import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class AppLogEntry {
  const AppLogEntry({
    required this.at,
    required this.tag,
    required this.message,
  });

  final DateTime at;
  final String tag;
  final String message;
}

/// Simple app-level logger that writes to:
/// 1) Dart/Android logs (developer.log)
/// 2) flutter run console (debugPrint)
/// 3) in-app rolling diagnostics buffer
class AppLogger {
  AppLogger._();

  static final Queue<AppLogEntry> _entries = ListQueue<AppLogEntry>();
  static const _maxEntries = 250;
  static final ValueNotifier<List<AppLogEntry>> logs =
      ValueNotifier<List<AppLogEntry>>(const []);

  static void info(String tag, String message) {
    final entry = AppLogEntry(
      at: DateTime.now(),
      tag: tag,
      message: message,
    );
    developer.log(message, name: tag);
    debugPrint('[$tag] $message');
    _entries.addLast(entry);
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
    logs.value =
        List<AppLogEntry>.unmodifiable(_entries.toList(growable: false));
  }

  static void clear() {
    _entries.clear();
    logs.value = const [];
  }
}
