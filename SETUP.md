# Genzeb backend setup

The app runs fully offline with no configuration. To enable Google sign-in
and accounts, wire up Supabase once:

## 1. Create the Supabase project

1. Create a project at [supabase.com](https://supabase.com) (free tier is fine).
2. Open **SQL Editor** and run the contents of
   [`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql).
   This creates `profiles`, `plans`, `subscriptions` (with row-level
   security), and a trigger that gives every new user the freemium plan.
3. Note your **Project URL** and **anon public key** from
   Project Settings → API.

## 2. Create the Google OAuth client

1. In [Google Cloud console](https://console.cloud.google.com), create a
   project and open **APIs & Services → Credentials**.
2. Create an **OAuth client ID → Web application**. Copy its client ID —
   this is your `GOOGLE_SERVER_CLIENT_ID` (yes, the *web* one; the native
   Android flow uses it to mint an ID token Supabase can verify).
3. Create a second **OAuth client ID → Android** with package name
   `com.nitsuh.genzeb` and your signing SHA-1
   (`cd android && ./gradlew signingReport`).
4. In Supabase: **Authentication → Providers → Google**, enable it and paste
   the web client ID (and secret).

## 3. Run with configuration

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOURPROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=GEMINI_API_KEY=... \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=1234-abc.apps.googleusercontent.com
```

For release builds pass the same `--dart-define` flags to `flutter build apk`.

Without these defines the app silently runs in local mode: onboarding still
works via "Explore without an account" and all on-device features function.
