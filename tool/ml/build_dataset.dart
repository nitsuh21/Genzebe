// Step 0 of the categorization model: runs the shipping parser over raw
// bank/wallet SMS and writes the dataset the labeller and baseline read.
// Driven by export_sms.py; see tool/ml/README.md.
//
//   dart run tool/ml/build_dataset.dart where
//       Prints the SQL selection that keeps only financial senders, so the
//       phone never hands over personal chats.
//   dart run tool/ml/build_dataset.dart build <raw.json> <data-dir>
//       raw.json is a list of {sender, date (epoch ms), body}. Writes
//       <data-dir>/dataset.jsonl and <data-dir>/meta.json.
import 'dart:convert';
import 'dart:io';

import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';

void main(List<String> args) {
  if (args.length == 1 && args[0] == 'where') {
    stdout.write(_financialSenderWhere());
    return;
  }
  if (args.length == 3 && args[0] == 'build') {
    _build(File(args[1]), Directory(args[2]));
    return;
  }
  stderr.writeln('usage: build_dataset.dart where | build <raw.json> <data-dir>');
  exitCode = 64;
}

/// A superset of [isFinancialSender] expressed in SQL; the exact rule is
/// re-applied in Dart. Separators are stripped the same way the app
/// normalises sender IDs ("Coop Bank-Oromia" -> "coopbankoromia").
String _financialSenderWhere() {
  const address = "lower(replace(replace(replace(replace(address,' ',''),'-',''),'_',''),'.',''))";
  final clauses = <String>{};
  for (final info in kInstitutions) {
    for (final keyword in info.senderKeywords) {
      clauses.add("$address LIKE '%$keyword%'");
    }
    for (final exact in info.exactSenders) {
      clauses.add("$address = '$exact'");
    }
  }
  return clauses.join(' OR ');
}

void _build(File rawFile, Directory dataDir) {
  final raw = (jsonDecode(rawFile.readAsStringSync()) as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final engine = buildDefaultSmsParserEngine();

  var nonFinancial = 0;
  var ignored = 0;
  final seen = <String>{};
  final rows = <Map<String, dynamic>>[];
  for (final message in raw) {
    final sender = message['sender'] as String;
    final body = message['body'] as String;
    final receivedAt =
        DateTime.fromMillisecondsSinceEpoch(message['date'] as int);
    if (!isFinancialSender(sender)) {
      nonFinancial++;
      continue;
    }
    final id = '${receivedAt.millisecondsSinceEpoch}-'
        '${sender.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '')}';
    if (!seen.add(id)) continue;

    // OTPs, balance inquiries, promos and failed transactions parse to null
    // (pinned by the fixture corpus) and never reach the dataset.
    final parsed = engine.parse(
      SmsMessage(id: id, sender: sender, body: body, receivedAt: receivedAt),
    );
    if (parsed == null) {
      ignored++;
      continue;
    }
    final isExpense = parsed.detectedAmountMinor < 0;
    rows.add({
      'id': id,
      'date': receivedAt.toIso8601String(),
      'sender': sender,
      'institution': parsed.institution.name,
      'direction': isExpense ? 'out' : 'in',
      'amountMinor': parsed.detectedAmountMinor.abs(),
      'merchant': extractMerchant(body, isExpense: isExpense),
      'body': _maskNumbers(body),
      'predicted': parsed.categoryHint,
      'confidence': parsed.confidence,
    });
  }
  rows.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

  dataDir.createSync(recursive: true);
  File('${dataDir.path}/dataset.jsonl')
      .writeAsStringSync(rows.map(jsonEncode).map((l) => '$l\n').join());

  final predicted = <String, int>{};
  for (final row in rows) {
    predicted.update(row['predicted'] as String, (n) => n + 1,
        ifAbsent: () => 1);
  }
  final meta = {
    'builtAt': DateTime.now().toIso8601String(),
    'parserVersion': kParserVersion,
    'rawMessages': raw.length,
    'nonFinancial': nonFinancial,
    'ignoredByParser': ignored,
    'transactions': rows.length,
    'predicted': Map.fromEntries(
      predicted.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    ),
  };
  File('${dataDir.path}/meta.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(meta));
  stdout.writeln(jsonEncode(meta));
}

/// Account numbers, phone numbers and references are long digit runs; none
/// of them help categorize and all of them identify someone. Amounts are
/// kept (they are short or comma-grouped).
String _maskNumbers(String body) =>
    body.replaceAll(RegExp(r'\d{7,}'), '<num>');
