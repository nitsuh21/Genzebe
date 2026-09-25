# R8 rules for the Genzeb release build.
# The Flutter Gradle plugin already adds flutter_proguard_rules.pro; most
# plugins ship consumer rules. These are belt-and-braces keeps for classes
# reached via reflection, JNI or platform-channel registration.

# --- Flutter embedding & generated plugin registrant ---
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**
# Play Core (deferred components) is referenced by the embedding but unused.
-dontwarn com.google.android.play.core.**

# --- android_sms_reader (SMS read + incoming-SMS BroadcastReceiver) ---
-keep class com.stackobea.android_sms_reader.** { *; }

# --- sqflite ---
-keep class com.tekartik.sqflite.** { *; }

# --- google_sign_in (Play services auth / Credential Manager) ---
-keep class io.flutter.plugins.googlesignin.** { *; }
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.**

# --- permission_handler ---
-keep class com.baseflow.permissionhandler.** { *; }

# --- share_plus ---
-keep class dev.fluttercommunity.plus.share.** { *; }

# --- app_links (supabase_flutter OAuth deep links) ---
-keep class com.llfbandit.app_links.** { *; }

# --- path_provider_android / jni (jnigen bindings, looked up via JNI) ---
-keep class com.github.dart_lang.jni.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }

# --- shared_preferences / url_launcher ---
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }

# Keep annotations / signatures used by reflection-based code.
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
