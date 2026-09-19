import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';

/// Table-driven parser spec: every case in test/fixtures/sms/*.json runs
/// through the production engine (same template order as providers.dart).
/// See test/fixtures/sms/README.md for the case format.
void main() {
  final engine = SmsParserEngine(
    const [
      CbeSmsParserTemplate(),
      AwashSmsParserTemplate(),
      TelebirrSmsParserTemplate(),
      BoaSmsParserTemplate(),
      HibretSmsParserTemplate(),
      DashenSmsParserTemplate(),
      GenericAmountParserTemplate(),
    ],
  );

  final dir = Directory('test/fixtures/sms');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final allIds = <String>[];
  test('corpus has fixtures with unique ids', () {
    expect(files, isNotEmpty, reason: 'no fixtures found in ${dir.path}');
    final duplicates =
        allIds.where((id) => allIds.where((x) => x == id).length > 1).toSet();
    expect(duplicates, isEmpty, reason: 'duplicate case ids');
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last.replaceAll('.json', '');
    final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final cases = (doc['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

    group(name, () {
      for (final c in cases) {
        final id = c['id'] as String;
        allIds.add(id);
        final expected = c['expect'] as Map<String, dynamic>;

        test(id, () {
          final parsed = engine.parse(
            SmsMessage(
              id: id,
              sender: c['sender'] as String,
              body: c['body'] as String,
              receivedAt: DateTime(2026, 7, 9, 12),
            ),
          );

          final shouldParse = expected['parsed'] as bool;
          if (!shouldParse) {
            expect(parsed, isNull,
                reason: 'expected the message to be ignored');
            return;
          }
          expect(parsed, isNotNull, reason: 'expected a parse');
          parsed!;

          if (expected.containsKey('institution')) {
            expect(
              parsed.institution.name,
              expected['institution'],
              reason: 'institution',
            );
          }
          if (expected.containsKey('direction')) {
            final direction = parsed.detectedAmountMinor < 0 ? 'out' : 'in';
            expect(direction, expected['direction'], reason: 'direction');
          }
          if (expected.containsKey('amountMinor')) {
            expect(
              parsed.detectedAmountMinor.abs(),
              expected['amountMinor'],
              reason: 'amount',
            );
          }
          if (expected.containsKey('category')) {
            expect(parsed.categoryHint, expected['category'],
                reason: 'category');
          }
          if (expected.containsKey('balanceMinor')) {
            expect(parsed.balanceMinor, expected['balanceMinor'],
                reason: 'balance');
          }
          if (expected.containsKey('referenceContains')) {
            final needle = expected['referenceContains'];
            if (needle == null) {
              expect(parsed.reference, isNull, reason: 'reference');
            } else {
              expect(parsed.reference, contains(needle), reason: 'reference');
            }
          }
          if (expected.containsKey('merchant')) {
            expect(
              extractMerchant(
                c['body'] as String,
                isExpense: parsed.detectedAmountMinor < 0,
              ),
              expected['merchant'],
              reason: 'merchant',
            );
          }
          if (expected.containsKey('explicitDirection')) {
            expect(
              parsed.evidence?.explicitDirection,
              expected['explicitDirection'],
              reason: 'explicitDirection',
            );
          }
          if (expected.containsKey('autoAccept')) {
            expect(
              parsed.confidence >= kAutoAcceptConfidence,
              expected['autoAccept'],
              reason: 'autoAccept (confidence ${parsed.confidence}, '
                  'reasons: ${parsed.evidence?.reviewReasons})',
            );
          }
        });
      }
    });
  }
}
