import 'package:flutter/material.dart';

/// The privacy policy, shown inside the app as Google Play requires.
///
/// The release build has no INTERNET permission, so the text lives here
/// rather than behind a link. Keep it in step with the published copy in
/// `docs/privacy-policy.html` (served at [kPrivacyPolicyUrl]).
const kPrivacyPolicyUrl =
    'https://nitsuh21.github.io/Genzebe/privacy-policy.html';
const _contactEmail = 'nitsuhdemissew21@gmail.com';
const _effectiveDate = '2 October 2026';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: SelectionArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, 32 + MediaQuery.of(context).viewPadding.bottom),
          children: [
            Text('Effective $_effectiveDate',
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            const _Section('In short', [
              'Genzeb reads SMS on your phone only, to find transaction '
                  'messages from recognised Ethiopian banks and mobile-money '
                  'wallets.',
              'Your SMS text never leaves your device. Personal '
                  '(non-financial) SMS are ignored and not stored.',
              'If you prefer not to grant SMS access, you can still add '
                  'transactions manually.',
              'Your financial records are stored in a database on your '
                  'device. We do not have a copy.',
              'There are no accounts and no sign-in. The app has no internet '
                  'access, so nothing you do in Genzeb is sent anywhere.',
              'No ads. No analytics or tracking SDKs. We never sell your data.',
            ]),
            const _Section('SMS messages', [
              'Permissions used: READ_SMS and RECEIVE_SMS. Banks and wallets '
                  'in Ethiopia report transactions by SMS; Genzeb reads them '
                  'to build your transaction history, balances and budgets '
                  'automatically.',
              'Genzeb asks for SMS access only after explaining why, and only '
                  'if you agree.',
              'Messages are processed entirely on your device by a built-in '
                  'parser. SMS text is never uploaded or shared with us or '
                  'any third party, including any AI service.',
              'Only messages from recognised financial senders are processed; '
                  'everything else is ignored and not stored. For a '
                  'recognised message, Genzeb keeps the message and the '
                  'details it extracts (amount, date, type, fees, balance, '
                  'counterparty) on your device.',
              'RECEIVE_SMS lets Genzeb record a new transaction message as '
                  'soon as it arrives, even when the app is closed.',
              'Notifications: with your permission, Genzeb shows a "money in" '
                  'or "money out" notification when a transaction message '
                  'arrives. It is created on your phone, and on the lock '
                  'screen it hides the amount.',
              'You can revoke SMS access any time in Android Settings → Apps '
                  '→ Genzeb → Permissions.',
            ]),
            const _Section('Data stored on your device', [
              'Transactions, categories, budgets and settings are stored '
                  'locally. They are not uploaded to any server or cloud.',
              'Android backup is disabled for Genzeb, so this data is not '
                  'restored if you reinstall the app or change phones.',
              'Clearing the app\'s data or uninstalling Genzeb deletes it.',
              'If you use share or export, the file is created on your device '
                  'and sent only where you choose.',
            ]),
            const _Section('What we do not do', [
              'No advertising and no advertising ID.',
              'No analytics, crash-reporting or tracking SDKs.',
              'We do not sell, rent or trade your data, and we do not use it '
                  'for credit scoring, lending or marketing.',
              'We do not access your contacts, location, call log, camera, '
                  'microphone or photos.',
            ]),
            const _Section('Security and children', [
              'Your data stays in the app\'s private storage, which other '
                  'apps cannot read. Protect your phone with a screen lock.',
              'Genzeb is intended for adults (18+) and is not directed to '
                  'children.',
            ]),
            const _Section('Changes and contact', [
              'If we change how the app handles data, we will update this '
                  'policy and tell you in the app before significant changes '
                  'take effect.',
              'Questions: $_contactEmail',
              'Online copy: $kPrivacyPolicyUrl',
            ]),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.points);

  final String title;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final point in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(
                      child: Text(point, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
