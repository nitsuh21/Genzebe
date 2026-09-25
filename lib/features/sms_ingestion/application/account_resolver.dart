import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/domain/repositories/ledger_repository.dart';

/// Files every SMS transaction under one account per institution, created
/// the first time that bank or wallet shows up in the inbox. There is no
/// manual sender→account mapping: the institution registry recognises the
/// sender, and each recognised institution gets its own account.
class AccountResolver {
  AccountResolver(this._ledgerRepository);

  final LedgerRepository _ledgerRepository;

  static const defaultAccountId = 'main-wallet';

  static String accountIdFor(EthiopianInstitution institution) =>
      institution == EthiopianInstitution.unknown
          ? defaultAccountId
          : '${institution.name}-main';

  Future<String> resolveAccountId({
    required SmsMessage sms,
    required ParsedSmsTransaction parsed,
  }) async {
    final info = institutionInfo(parsed.institution);
    final accountId = accountIdFor(parsed.institution);
    await _ledgerRepository.upsertAccount(
      Account(
        id: accountId,
        name: parsed.institution == EthiopianInstitution.unknown
            ? 'Main Wallet'
            : info.name,
        kind: info.kind == InstitutionKind.wallet ? 'wallet' : 'bank-account',
        createdAt: sms.receivedAt,
        institutionCode: parsed.institution.name,
        maskedAccount: parsed.accountNumberHint,
      ),
    );
    return accountId;
  }
}
