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

Copy `env.example.json` to `env.json` (gitignored), paste your values, then:

```bash
flutter run --dart-define-from-file=env.json
flutter build apk --dart-define-from-file=env.json
```

(Individual `--dart-define=KEY=value` flags also still work.)

### Values for this machine

Debug signing SHA-1 for the Android OAuth client (package
`com.nitsuh.genzeb`):

```
34:E3:B1:0F:28:FB:5F:80:CD:12:92:3E:4E:1C:6C:9F:F8:88:B0:09
```

Release builds are signed with a different key — add the release SHA-1 as a
second fingerprint on the same Android OAuth client before shipping.

Without these defines the app silently runs in local mode: onboarding still
works via "Explore without an account" and all on-device features function.
