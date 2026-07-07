import 'package:genzeb/core/logging/app_logger.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/application/account_mapping_service.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/device_sms_source.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/sms_message_repository.dart';

class ForceSyncResult {
  const ForceSyncResult({
    required this.processed,
    required this.newlyParsed,
    required this.pendingReview,
    required this.duplicates,
    required this.failed,
    required this.deviceFetched,
    required this.deviceMatchedMappings,
    required this.importedCount,
    required this.mappingRuleCount,
    required this.smsPermissionState,
  });

  final int processed;
  final int newlyParsed;
  final int pendingReview;
  final int duplicates;
  final int failed;
  final int deviceFetched;
  final int deviceMatchedMappings;
  final int importedCount;
  final int mappingRuleCount;
  final SmsPermissionState smsPermissionState;
}

class SyncService {
  SyncService({
    required SmsMessageRepository smsMessageRepository,
    required SmsIngestionService smsIngestionService,
    required DeviceSmsSource deviceSmsSource,
    required AccountMappingService accountMappingService,
  })  : _smsMessageRepository = smsMessageRepository,
        _smsIngestionService = smsIngestionService,
        _deviceSmsSource = deviceSmsSource,
        _accountMappingService = accountMappingService;

  final SmsMessageRepository _smsMessageRepository;
  final SmsIngestionService _smsIngestionService;
  final DeviceSmsSource _deviceSmsSource;
  final AccountMappingService _accountMappingService;

  Future<ForceSyncResult> forceSyncFromSms({
    String? importedRawPayload,
    bool syncAllMappings = true,
    Set<String>? selectedMappingSenderPatterns,
  }) async {
    final since = DateTime.now().subtract(const Duration(days: 365 * 2));
    final mappings = await _accountMappingService.getMappings();
    final normalizedSelection = selectedMappingSenderPatterns
            ?.map((pattern) => pattern.toLowerCase())
            .toSet() ??
        const <String>{};
    final activeMappings = mappings.where((mapping) {
      if (syncAllMappings) return true;
      return normalizedSelection.contains(mapping.senderPattern.toLowerCase());
    }).toList(growable: false);
    final permissionState = await _deviceSmsSource.ensurePermission();
    final fetchedDeviceMessages = permissionState == SmsPermissionState.granted
        ? await _deviceSmsSource.fetchRecentMessages(
            since: since,
          )
        : const <SmsMessage>[];
    final deviceMessages = fetchedDeviceMessages.where((message) {
      if (mappings.isEmpty) return true;
      if (activeMappings.isEmpty) return false;
      final sender = message.sender;
      return activeMappings.any(
        (rule) => _senderMatchesPattern(sender, rule.senderPattern),
      );
    }).toList(growable: false);
    final importedMessages = _parseImportedPayload(importedRawPayload);
    final allMessages = <SmsMessage>[
      ...deviceMessages,
      ...importedMessages,
    ];
    AppLogger.info(
      'sync.force',
      'forceSyncFromSms: fetchedDevice=${fetchedDeviceMessages.length}, '
          'mappedDevice=${deviceMessages.length}, imported=${importedMessages.length}, '
          'mappingRules=${mappings.length}, activeRules=${activeMappings.length}, '
          'syncAllMappings=$syncAllMappings, permission=$permissionState, since=$since',
    );
    var duplicates = 0;
    var failed = 0;
    for (final message in allMessages) {
      await _smsIngestionService.ingest(sms: message);
      final stored = await _smsMessageRepository.getById(message.id);
      if (stored == null) continue;
      if (stored.status == SmsIngestionStatus.duplicate) duplicates += 1;
      if (stored.status == SmsIngestionStatus.failed) failed += 1;
    }
    final allStored = await _smsMessageRepository.getAll();
    final newlyParsed = allStored
        .where((message) => message.status == SmsIngestionStatus.parsed)
        .length;
    final pendingReview = allStored
        .where((message) => message.status == SmsIngestionStatus.pendingReview)
        .length;
    return ForceSyncResult(
      processed: allMessages.length,
      newlyParsed: newlyParsed,
      pendingReview: pendingReview,
      duplicates: duplicates,
      failed: failed,
      deviceFetched: fetchedDeviceMessages.length,
      deviceMatchedMappings: deviceMessages.length,
      importedCount: importedMessages.length,
      mappingRuleCount: activeMappings.length,
      smsPermissionState: permissionState,
    );
  }

  List<SmsMessage> _parseImportedPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return const [];
    final lines = payload
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final now = DateTime.now();
    return lines.asMap().entries.map((entry) {
      final index = entry.key;
      final line = entry.value;
      final parts = line.split('|');
      final sender = parts.length > 1 ? parts.first.trim() : 'IMPORTED';
      final body = parts.length > 1 ? parts.sublist(1).join('|').trim() : line;
      return SmsMessage(
        id: 'imported-${now.microsecondsSinceEpoch}-$index',
        sender: sender,
        body: body,
        receivedAt: now.subtract(Duration(minutes: index)),
      );
    }).toList(growable: false);
  }

  bool _senderMatchesPattern(String sender, String pattern) {
    final lowerSender = sender.toLowerCase();
    final lowerPattern = pattern.toLowerCase();
    if (lowerSender.contains(lowerPattern)) return true;

    final normalizedSender = _normalizeSenderToken(lowerSender);
    final normalizedPattern = _normalizeSenderToken(lowerPattern);
    if (normalizedPattern.isEmpty) return false;
    return normalizedSender.contains(normalizedPattern);
  }

  String _normalizeSenderToken(String value) {
    return value.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
