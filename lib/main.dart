import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/app.dart';
import 'package:genzeb/core/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.isBackendConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      // The dashboard's "anon public" key; supabase_flutter is renaming the
      // param to publishableKey but the value is the same.
      // ignore: deprecated_member_use
      anonKey: AppConfig.supabaseAnonKey,
    );
  }
  runApp(const ProviderScope(child: GenzebApp()));
}
