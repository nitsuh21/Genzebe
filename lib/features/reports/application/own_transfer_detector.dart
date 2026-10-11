import 'dart:math' as math;

import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart'
    show extractMerchant, normalizeMerchant;
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';

/// Why a transaction counts as money moving between the user's own accounts.
enum OwnTransferReason {
  /// Matched with the opposite leg on another of the user's accounts.
  paired,

  /// The user marked it themselves.
  markedByUser,

  /// The other side is an account number the user's own receipts call
  /// "your account".
  ownAccount,

  /// The other side is the account holder's own name.
  ownName,

  /// Same recipient/sender as a transaction the user marked as their own.
  learned,

  /// Categorized as savings — money the user keeps.
  savings,
}

/// Result of classifying transactions into real flows vs internal movements.
class FlowAnalysis {
  const FlowAnalysis({
    required this.internalIds,
    required this.pairFeeByOutflowId,
    this.reasonById = const {},
    this.partnerById = const {},
    this.suggestedIds = const <String>{},
  });

  static const empty = FlowAnalysis(
    internalIds: <String>{},
    pairFeeByOutflowId: {},
  );

  /// Transaction ids that are own-account movements: both legs of a
  /// matched pair, plus one-sided transfers proven by name/account, the
  /// user's own answers, and savings.
  final Set<String> internalIds;

  /// For matched pairs: outflow-leg id -> fee delta (outflow - inflow).
  final Map<String, int> pairFeeByOutflowId;

  final Map<String, OwnTransferReason> reasonById;

  /// For matched pairs, each leg's id -> the other leg's id.
  final Map<String, String> partnerById;

  /// Transfers to/from a bank or wallet the user also uses with no
  /// matching leg found — maybe their own, maybe someone else's. They stay
  /// in income/spending until the user answers.
  final Set<String> suggestedIds;
}

/// Finds money moving between the user's own accounts so it never
/// masquerades as income or spending.
///
/// Every rule is evidence-based — a false match silently deletes real
/// income AND real spending, which is worse than missing a transfer:
///  1. The user's answer ([TransactionRecord.ownTransfer]) always wins.
///  2. Pairs: an outflow and an inflow that look like a transfer, with
///     amounts equal up to a plausible fee. How far apart the legs may be
///     depends on corroboration: 3 h with none, 24 h when one receipt names
///     the other leg's bank/wallet, 72 h when both do or the receipt names
///     the user / the user's own account number. A receipt that names a
///     different bank, a different account, or a third person can never be
///     paired. Two accounts at the same bank pair only when the account
///     numbers prove it. Salary and ATM cash withdrawals never pair.
///  3. One-sided transfers (the other bank sent no SMS) count only on hard
///     proof: the receipt names the account holder (learned from the
///     "Dear ..." greeting), one of their own account numbers, or a recipient the user
///     already marked as their own.
///  4. Outflows categorized as savings are money the user keeps.
FlowAnalysis analyzeOwnTransfers(List<TransactionRecord> records) {
  final profile = OwnerProfile.learn(records);
  final legs = [
    for (final tx in records)
      if (tx.reviewStatus != TransactionReviewStatus.pendingReview)
        _Leg(tx, profile),
  ];

  // What the user taught by answering: recipients/senders that are (or are
  // not) them.
  final ownNames = <String>{};
  final notOwnNames = <String>{};
  final ownAccounts = <MaskedAccount>[];
  final notOwnAccounts = <MaskedAccount>[];
  for (final leg in legs) {
    final answer = leg.tx.ownTransfer;
    if (answer == OwnTransferOverride.none) continue;
    final names = answer == OwnTransferOverride.own ? ownNames : notOwnNames;
    final accounts =
        answer == OwnTransferOverride.own ? ownAccounts : notOwnAccounts;
    if (leg.personKey != null) names.add(leg.personKey!);
    if (leg.counterpartyAccount != null) {
      accounts.add(leg.counterpartyAccount!);
    }
  }

  /// Hard proof that the other side is the user, or null.
  OwnTransferReason? proofOf(_Leg leg) {
    final account = leg.counterpartyAccount;
    if (account != null &&
        !notOwnAccounts.any(account.sameAs) &&
        !leg.ownAccounts.any(account.sameAs)) {
      if (profile.ownsAccount(account)) return OwnTransferReason.ownAccount;
      if (ownAccounts.any(account.sameAs)) return OwnTransferReason.learned;
    }
    final key = leg.personKey;
    if (key == null || notOwnNames.contains(key)) return null;
    if (profile.isOwnerName(leg.counterpartyName!)) {
      return OwnTransferReason.ownName;
    }
    if (ownNames.contains(key)) return OwnTransferReason.learned;
    return null;
  }

  final eligibleOut = <_Leg>[];
  final eligibleIn = <_Leg>[];
  final proven = <String, OwnTransferReason>{};
  for (final leg in legs) {
    if (leg.tx.ownTransfer == OwnTransferOverride.notOwn) continue;
    final proof = proofOf(leg);
    if (proof != null) proven[leg.tx.id] = proof;
    final own = proof != null;
    final marked = leg.tx.ownTransfer == OwnTransferOverride.own;
    if (leg.isOut) {
      if (leg.isCashWithdrawal && !marked) continue;
      if (own ||
          marked ||
          leg.isPlainDebit ||
          (leg.transferish && !leg.isThirdParty)) {
        eligibleOut.add(leg);
      }
    } else {
      if (leg.tx.categoryId == 'salary' && !marked) continue;
      if (own || marked || !leg.isThirdParty) eligibleIn.add(leg);
    }
  }

  // Every plausible pair, then strongest evidence first, closest in time
  // next — so a corroborated match is never stolen by a coincidental one.
  eligibleIn.sort((a, b) => a.tx.occurredAt.compareTo(b.tx.occurredAt));
  final candidates = <_Candidate>[];
  for (final out in eligibleOut) {
    final earliest = out.tx.occurredAt.subtract(_leads.last);
    final latest = out.tx.occurredAt.add(_windows.last);
    var i = _lowerBound(eligibleIn, earliest);
    for (; i < eligibleIn.length; i++) {
      final inn = eligibleIn[i];
      if (inn.tx.occurredAt.isAfter(latest)) break;
      final candidate = _pairCandidate(out, inn, proven);
      if (candidate != null) candidates.add(candidate);
    }
  }
  candidates.sort((a, b) {
    final byEvidence = b.evidence.compareTo(a.evidence);
    if (byEvidence != 0) return byEvidence;
    final byGap = a.gap.compareTo(b.gap);
    if (byGap != 0) return byGap;
    return a.fee.compareTo(b.fee);
  });

  final internalIds = <String>{};
  final reasons = <String, OwnTransferReason>{};
  final partners = <String, String>{};
  final pairFees = <String, int>{};
  for (final c in candidates) {
    final outId = c.out.tx.id;
    final inId = c.inn.tx.id;
    if (partners.containsKey(outId) || partners.containsKey(inId)) continue;
    partners[outId] = inId;
    partners[inId] = outId;
    pairFees[outId] = c.fee;
    internalIds
      ..add(outId)
      ..add(inId);
    reasons[outId] = OwnTransferReason.paired;
    reasons[inId] = OwnTransferReason.paired;
  }

  final userInstitutions = {
    for (final leg in legs) leg.institution,
  }..remove(EthiopianInstitution.unknown);
  // Where money is seen arriving / leaving. A bank that does report
  // credits but shows none for a transfer to it never received it.
  final reportsIn = {
    for (final leg in legs)
      if (!leg.isOut) leg.institution,
  };
  final reportsOut = {
    for (final leg in legs)
      if (leg.isOut) leg.institution,
  };
  final suggested = <String>{};

  for (final leg in legs) {
    final id = leg.tx.id;
    if (internalIds.contains(id)) continue;
    final answer = leg.tx.ownTransfer;
    if (answer == OwnTransferOverride.notOwn) continue;
    OwnTransferReason? reason = proven[id];
    if (answer == OwnTransferOverride.own) {
      reason = OwnTransferReason.markedByUser;
    } else if (reason == null && leg.isOut && leg.tx.categoryId == 'savings') {
      reason = OwnTransferReason.savings;
    }
    if (reason != null) {
      internalIds.add(id);
      reasons[id] = reason;
      continue;
    }
    if (_worthAsking(
      leg,
      userInstitutions,
      leg.isOut ? reportsIn : reportsOut,
    )) {
      suggested.add(id);
    }
  }

  return FlowAnalysis(
    internalIds: internalIds,
    pairFeeByOutflowId: pairFees,
    reasonById: reasons,
    partnerById: partners,
    suggestedIds: suggested,
  );
}

/// Pair windows by evidence strength: none, one-sided, mutual/proven.
const _windows = [Duration(hours: 3), Duration(hours: 24), Duration(hours: 72)];

/// How long before the debit a credit SMS may land, by evidence strength —
/// delivery order isn't guaranteed, and a bank's own receipt can arrive
/// hours after the wallet's.
const _leads = [Duration(hours: 3), Duration(hours: 3), Duration(hours: 12)];

/// A debit that never says where the money went ("your Account has been
/// debited with ETB 5,005.75") pairs only this close to a credit whose
/// receipt names its bank — bank-to-wallet hops land within a minute.
const _plainDebitWindow = Duration(hours: 1);

class _Candidate {
  const _Candidate(this.out, this.inn, this.evidence, this.gap, this.fee);

  final _Leg out;
  final _Leg inn;
  final int evidence;
  final Duration gap;
  final int fee;
}

_Candidate? _pairCandidate(
  _Leg out,
  _Leg inn,
  Map<String, OwnTransferReason> proven,
) {
  final outMinor = out.tx.amount.minorUnits;
  final inMinor = inn.tx.amount.minorUnits;
  final fee = outMinor - inMinor;
  if (fee < 0) return null;
  final tolerance = math.max((outMinor * 0.02).round(), 2500);
  if (fee > tolerance) return null;

  // Account numbers decide when both receipts show comparable ones.
  final target = out.counterpartyAccount;
  var accountsMatch = false;
  if (target != null) {
    final comparable = inn.ownAccounts.where(target.comparableWith);
    if (comparable.isNotEmpty) {
      if (!comparable.any(target.sameAs)) return null;
      accountsMatch = true;
    }
  }
  // Two accounts at one bank are filed under one app account; only the
  // account numbers can tell them apart.
  if (out.tx.accountId == inn.tx.accountId && !accountsMatch) return null;

  // A receipt that names where the money went (or came from) rules out
  // every other bank or wallet.
  final outNamesIn = out.names(inn);
  final inNamesOut = inn.names(out);
  if (out.namesSomewhere && !outNamesIn) return null;
  if (inn.namesSomewhere && !inNamesOut) return null;

  final int evidence;
  if (accountsMatch ||
      proven.containsKey(out.tx.id) ||
      proven.containsKey(inn.tx.id) ||
      (outNamesIn && inNamesOut)) {
    evidence = 2;
  } else if (outNamesIn || inNamesOut) {
    evidence = 1;
  } else {
    evidence = 0;
  }

  final gap = inn.tx.occurredAt.difference(out.tx.occurredAt);
  if (gap < -_leads[evidence] || gap > _windows[evidence]) return null;
  final vouchedFor = proven.containsKey(out.tx.id) ||
      out.tx.ownTransfer == OwnTransferOverride.own;
  if (out.isPlainDebit &&
      !vouchedFor &&
      (!inNamesOut || gap.abs() > _plainDebitWindow)) {
    return null;
  }
  return _Candidate(out, inn, evidence, gap.abs(), fee);
}

/// Worth a yes/no only when the other side could be one of the user's
/// accounts AND its silence proves nothing: that bank or wallet never
/// reports money moving in that direction. Otherwise the missing leg means
/// the money went to (or came from) someone else.
bool _worthAsking(
  _Leg leg,
  Set<EthiopianInstitution> userInstitutions,
  Set<EthiopianInstitution> otherSideReports,
) {
  if (leg.tx.ownTransfer != OwnTransferOverride.none) return false;
  if (leg.isThirdParty || leg.isCashWithdrawal) return false;
  if (leg.tx.categoryId == 'salary') return false;
  if (leg.isOut && !leg.transferish) return false;
  final others = {...userInstitutions}..remove(leg.institution);
  final candidates = {
    ...leg.mentions.where(others.contains),
    if (leg.mentionsElsewhere) ...others,
    if (leg.mentionsOtherBank)
      ...others.where((i) => institutionInfo(i).kind == InstitutionKind.bank),
  };
  return candidates.any((i) => !otherSideReports.contains(i));
}

int _lowerBound(List<_Leg> sorted, DateTime at) {
  var lo = 0;
  var hi = sorted.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (sorted[mid].tx.occurredAt.isBefore(at)) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// One confirmed transaction plus what its receipt says about the other
/// side.
class _Leg {
  _Leg(this.tx, OwnerProfile profile)
      : isOut = tx.type == TransactionType.expense ||
            tx.type == TransactionType.transferOut,
        institution = _institutionOf(tx) {
    final body = tx.smsSnippet ?? '';
    final lower = body.toLowerCase();
    ownAccounts = ownAccountsIn(body, isOutflow: isOut);
    counterpartyAccount = _counterpartyAccountIn(body, isOutflow: isOut);
    final found = _institutionsMentionedIn(lower, exclude: institution);
    mentions = found.institutions;
    mentionsOtherBank = found.otherBank;
    mentionsElsewhere = found.elsewhere;
    isCashWithdrawal =
        isOut && RegExp(r'\b(withdraw\w*|atm)\b').hasMatch(lower);

    final name = body.isEmpty ? null : extractMerchant(body, isExpense: isOut);
    final isInstitution =
        name != null && _institutionsMentionedIn(name.toLowerCase()).any;
    counterpartyName = isInstitution ? null : name;
    final tokens = counterpartyName == null
        ? const <String>[]
        : personNameTokens(counterpartyName!);
    personKey = tokens.isEmpty ? null : normalizeMerchant(tokens.join(' '));
    final target = counterpartyAccount;
    // An account number at a bank where the user's own number is known,
    // and it isn't that number: someone else's account.
    final toSomeoneElse = target != null &&
        profile.isSomeoneElses(
            target, mentions.isEmpty ? {institution} : mentions);
    isThirdParty =
        (tokens.isNotEmpty && profile.isStranger(tokens)) || toSomeoneElse;

    transferish = const {'transfer_out', 'transfer_in', 'savings'}
            .contains(tx.categoryId) ||
        tx.type == TransactionType.transferOut ||
        tx.type == TransactionType.transferIn ||
        mentions.isNotEmpty ||
        mentionsOtherBank ||
        mentionsElsewhere ||
        counterpartyAccount != null ||
        _transferWords.hasMatch(lower);
  }

  final TransactionRecord tx;
  final bool isOut;
  final EthiopianInstitution institution;
  late final List<MaskedAccount> ownAccounts;
  late final MaskedAccount? counterpartyAccount;
  late final Set<EthiopianInstitution> mentions;
  late final bool mentionsOtherBank;

  /// Came from (or went to) some other bank or wallet, unnamed.
  late final bool mentionsElsewhere;
  late final bool isCashWithdrawal;
  late final String? counterpartyName;
  late final String? personKey;
  late final bool isThirdParty;
  late final bool transferish;

  bool get namesSomewhere =>
      mentions.isNotEmpty || mentionsOtherBank || mentionsElsewhere;

  /// A debit that says nothing about where the money went.
  bool get isPlainDebit =>
      isOut && !transferish && !isCashWithdrawal && counterpartyName == null;

  /// Whether this receipt names [other]'s bank or wallet as the other side.
  bool names(_Leg other) {
    if (mentions.contains(other.institution)) return true;
    if (mentionsElsewhere &&
        other.institution != institution &&
        other.institution != EthiopianInstitution.unknown) {
      return true;
    }
    return mentionsOtherBank &&
        other.institution != institution &&
        institutionInfo(other.institution).kind == InstitutionKind.bank;
  }
}

final _transferWords = RegExp(
  r'\b(transfer|transferred|transfered|sent|instant payment|ips|b2c)\b',
);

EthiopianInstitution _institutionOf(TransactionRecord tx) {
  final fromSender = institutionForSender(tx.smsSender ?? '');
  if (fromSender != EthiopianInstitution.unknown) return fromSender;
  final id = tx.accountId;
  if (!id.endsWith('-main')) return EthiopianInstitution.unknown;
  return EthiopianInstitution.values
          .asNameMap()[id.substring(0, id.length - '-main'.length)] ??
      EthiopianInstitution.unknown;
}

// ---------------------------------------------------------------------------
// Account numbers
// ---------------------------------------------------------------------------

/// An account number as banks print it in SMS — usually masked
/// ("1*****2468", "474041*******013"). Only the visible digits are kept.
class MaskedAccount {
  const MaskedAccount._(this.lead, this.tail);

  static MaskedAccount? parse(String raw) {
    final value = raw.trim();
    final firstMask = value.indexOf(_maskChar);
    if (firstMask < 0) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      return digits.length < 4 ? null : MaskedAccount._(digits, digits);
    }
    final lastMask = value.lastIndexOf(_maskChar);
    final lead = value.substring(0, firstMask).replaceAll(RegExp(r'\D'), '');
    final tail = value.substring(lastMask + 1).replaceAll(RegExp(r'\D'), '');
    if (tail.isEmpty) return null;
    return MaskedAccount._(lead, tail);
  }

  final String lead;
  final String tail;

  /// Enough trailing digits on both sides to tell accounts apart.
  bool comparableWith(MaskedAccount other) =>
      math.min(tail.length, other.tail.length) >= 3;

  /// True when every digit both sides show agrees, and enough of them do
  /// to rule out coincidence.
  bool sameAs(MaskedAccount other) {
    if (!comparableWith(other)) return false;
    final n = math.min(tail.length, other.tail.length);
    if (!tail.endsWith(other.tail.substring(other.tail.length - n))) {
      return false;
    }
    final m = math.min(lead.length, other.lead.length);
    if (!lead.startsWith(other.lead.substring(0, m))) return false;
    return n + m >= 4;
  }

  /// True when some digit both sides show disagrees — provably another
  /// account, even when too few digits show to call it the same one.
  bool differentFrom(MaskedAccount other) {
    final n = math.min(tail.length, other.tail.length);
    if (n >= 2 &&
        tail.substring(tail.length - n) !=
            other.tail.substring(other.tail.length - n)) {
      return true;
    }
    final m = math.min(lead.length, other.lead.length);
    return m >= 1 && lead.substring(0, m) != other.lead.substring(0, m);
  }

  @override
  String toString() => '$lead••$tail';
}

final _maskChar = RegExp(r'[*xX#•]');
const _acct = r'([0-9][0-9*xX#•]{3,})';

/// "your Account 1*****2468", "your telebirr account 2519******69",
/// "your account 474041*******013".
final _yourAccount = RegExp(
  '\\byour\\s+(?:[a-z-]+\\s+){0,2}?(?:acc(?:oun)?t|a/c)\\.?\\s*'
  '(?:no\\.?|number|#)?\\s*:?\\s*$_acct',
  caseSensitive: false,
);

/// "from account 1**2468" — the source account of an outflow.
final _fromAccount = RegExp(
  '\\bfrom\\s+(?:acc(?:oun)?t|a/c)\\.?\\s*(?:no\\.?)?\\s*:?\\s*$_acct',
  caseSensitive: false,
);

/// "to account 1**4607" — the destination of an outflow.
final _toAccount = RegExp(
  '\\bto\\s+(?:acc(?:oun)?t|a/c)\\.?\\s*(?:no\\.?)?\\s*:?\\s*$_acct',
  caseSensitive: false,
);

/// "to Commercial Bank of Ethiopia account number 1000213572468" — telebirr's
/// wording for a wallet-to-bank transfer.
final _toNamedAccount = RegExp(
  '\\bto\\s+[^.\\n]{0,60}?\\bacc(?:oun)?t\\s+(?:number|no\\.?)\\s*:?\\s*$_acct',
  caseSensitive: false,
);

/// The user's own account numbers that a receipt mentions.
List<MaskedAccount> ownAccountsIn(String body, {required bool isOutflow}) {
  final found = <MaskedAccount>[];
  for (final match in _yourAccount.allMatches(body)) {
    final account = MaskedAccount.parse(match.group(1)!);
    if (account != null) found.add(account);
  }
  if (isOutflow) {
    for (final match in _fromAccount.allMatches(body)) {
      final account = MaskedAccount.parse(match.group(1)!);
      if (account != null) found.add(account);
    }
  }
  return found;
}

MaskedAccount? _counterpartyAccountIn(String body, {required bool isOutflow}) {
  final match = isOutflow
      ? (_toAccount.firstMatch(body) ?? _toNamedAccount.firstMatch(body))
      : _fromAccount.firstMatch(body);
  final digits = match?.group(1);
  return digits == null ? null : MaskedAccount.parse(digits);
}

// ---------------------------------------------------------------------------
// The account holder
// ---------------------------------------------------------------------------

/// What the user's own receipts reveal about them: the account holder's
/// name (from the "Dear ..." greeting) and their own account numbers ("your account
/// 1*****2468"). Learned fresh from the ledger on every analysis.
class OwnerProfile {
  const OwnerProfile({
    this.nameTokens = const [],
    this.accounts = const [],
    this.accountsAt = const {},
  });

  factory OwnerProfile.learn(Iterable<TransactionRecord> records) {
    final names = <List<String>>[];
    final accounts = <String, MaskedAccount>{};
    final accountsAt = <EthiopianInstitution, Map<String, MaskedAccount>>{};
    for (final tx in records) {
      final body = tx.smsSnippet;
      if (body == null || body.isEmpty) continue;
      final name = holderNameFromSalutation(body);
      if (name != null) names.add(name);
      final isOut = tx.type == TransactionType.expense ||
          tx.type == TransactionType.transferOut;
      final institution = _institutionOf(tx);
      for (final account in ownAccountsIn(body, isOutflow: isOut)) {
        final key = '${account.lead}*${account.tail}';
        accounts[key] = account;
        accountsAt.putIfAbsent(institution, () => {})[key] = account;
      }
    }
    return OwnerProfile(
      nameTokens: _consensusName(names),
      accounts: accounts.values.toList(growable: false),
      accountsAt: {
        for (final entry in accountsAt.entries)
          entry.key: entry.value.values.toList(growable: false),
      },
    );
  }

  /// Lower-case name tokens, e.g. ['abebe', 'kebede', 'alemu'].
  final List<String> nameTokens;
  final List<MaskedAccount> accounts;

  /// The user's own account numbers per bank/wallet.
  final Map<EthiopianInstitution, List<MaskedAccount>> accountsAt;

  /// True when [account], at one of [institutions], provably isn't any
  /// number the user's own receipts there show.
  bool isSomeoneElses(
    MaskedAccount account,
    Iterable<EthiopianInstitution> institutions,
  ) {
    final known = [for (final i in institutions) ...?accountsAt[i]];
    return known.isNotEmpty && known.every(account.differentFrom);
  }

  /// Names are only compared once the full name is known — a first name
  /// alone is far too common.
  bool get knowsName => nameTokens.length >= 2;

  bool ownsAccount(MaskedAccount account) => accounts.any(account.sameAs);

  /// "Abebe K. A", "ABEBE KEBEDE" -> true for holder Abebe Kebede Alemu:
  /// the given name must match exactly and every further name must match
  /// in full or by initial.
  bool isOwnerName(String name) => _matchesOwner(personNameTokens(name));

  /// A named person who is provably not the holder.
  bool isStranger(List<String> tokens) {
    if (!knowsName || tokens.isEmpty) return false;
    // "Mr Abebe" — can't tell either way.
    if (tokens.length == 1) return tokens.first != nameTokens.first;
    return !_matchesOwner(tokens);
  }

  bool _matchesOwner(List<String> tokens) {
    if (!knowsName || tokens.length < 2) return false;
    if (tokens.first != nameTokens.first) return false;
    final n = math.min(tokens.length, nameTokens.length);
    for (var i = 1; i < n; i++) {
      final token = tokens[i];
      final own = nameTokens[i];
      if (token == own) continue;
      if (token.length == 1 && own.startsWith(token)) continue;
      return false;
    }
    return true;
  }
}

final _salutation =
    RegExp(r'^\s*(?:dear|ውድ)\s+([^\n,፣:;!]+)', caseSensitive: false);

const _notNames = {
  'customer',
  'customers',
  'valued',
  'esteemed',
  'client',
  'sir',
  'madam',
  'member',
  'user',
  'subscriber',
  'beneficiary',
  'all',
};

const _nameStops = {
  'you',
  'your',
  'the',
  'please',
  'thank',
  'thanks',
  'we',
  'this',
  'has',
  'have',
  'is',
  'our',
  'account',
  'kindly',
  'etb',
  'birr',
  'on',
  'for',
  'to',
  'from',
  'with',
};

/// The holder's name from a receipt's salutation ("Dear Abebe Kebede Alemu
/// You have ..." -> [abebe, kebede, alemu]), or null for "Dear customer".
List<String>? holderNameFromSalutation(String body) {
  final match = _salutation.firstMatch(body);
  if (match == null) return null;
  final tokens = <String>[];
  for (final raw in match.group(1)!.trim().split(RegExp(r'\s+'))) {
    final word = raw.toLowerCase().replaceAll(RegExp(r"[.']+$"), '');
    // One-letter words end the name: in "Dear Abebe A debit transaction"
    // the "A" starts the sentence.
    if (!RegExp(r'^[a-z]{2,}$').hasMatch(word)) break;
    if (_nameStops.contains(word)) break;
    tokens.add(word);
    if (tokens.length == 4) break;
  }
  if (tokens.isEmpty || _notNames.contains(tokens.first)) return null;
  return tokens;
}

/// The most-attested name, position by position: "Dear Abebe" and "Dear
/// Abebe Kebede Alemu" agree on [abebe, kebede, alemu].
List<String> _consensusName(List<List<String>> names) {
  final result = <String>[];
  var pool = names;
  for (var i = 0; i < 4; i++) {
    final counts = <String, int>{};
    for (final name in pool) {
      if (name.length > i) {
        counts.update(name[i], (v) => v + 1, ifAbsent: () => 1);
      }
    }
    if (counts.isEmpty) break;
    final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    result.add(top);
    pool = pool.where((n) => n.length > i && n[i] == top).toList();
  }
  return result;
}

const _titles = {'mr', 'mrs', 'ms', 'miss', 'dr', 'ato', 'wro', 'wt', 'wrt'};

/// "Hanna S. M." -> [hanna, s, m]; "W/ro Almaz" -> [almaz].
List<String> personNameTokens(String name) {
  final tokens = name
      .toLowerCase()
      .replaceAll('/', '')
      .split(RegExp(r'[^a-z]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  while (tokens.isNotEmpty && _titles.contains(tokens.first)) {
    tokens.removeAt(0);
  }
  return tokens;
}

// ---------------------------------------------------------------------------
// Banks and wallets named in a receipt
// ---------------------------------------------------------------------------

/// Names a receipt may use for the other side's bank or wallet. Bank names
/// that double as given names (Abay, Berhan, Tsehay, ...) only count with
/// "Bank" after them.
const Map<EthiopianInstitution, List<String>> _aliases = {
  EthiopianInstitution.telebirr: ['telebirr', 'tele-birr', 'tele birr'],
  EthiopianInstitution.cbebirr: ['cbe birr', 'cbebirr', 'cbe-birr'],
  EthiopianInstitution.mpesa: ['m-pesa', 'mpesa', 'm pesa', 'safaricom'],
  EthiopianInstitution.amole: ['amole'],
  EthiopianInstitution.hellocash: ['hellocash', 'hello cash'],
  EthiopianInstitution.ebirr: ['ebirr', 'e-birr', 'kaafi'],
  EthiopianInstitution.kacha: ['kacha'],
  EthiopianInstitution.cbe: ['cbe', 'commercial bank'],
  EthiopianInstitution.awash: ['awash'],
  EthiopianInstitution.dashen: ['dashen'],
  EthiopianInstitution.boa: ['abyssinia', 'boa'],
  EthiopianInstitution.hibret: ['hibret', 'united bank'],
  EthiopianInstitution.wegagen: ['wegagen'],
  EthiopianInstitution.nib: ['nib bank', 'nib international'],
  EthiopianInstitution.coop: ['coopbank', 'coop bank', 'cooperative bank'],
  EthiopianInstitution.oromia: ['oromia bank', 'oromia international'],
  EthiopianInstitution.zemen: ['zemen'],
  EthiopianInstitution.lion: ['lion bank', 'lion international'],
  EthiopianInstitution.bunna: ['bunna bank'],
  EthiopianInstitution.berhan: ['berhan bank'],
  EthiopianInstitution.abay: ['abay bank'],
  EthiopianInstitution.addis: ['addis bank', 'addis international'],
  EthiopianInstitution.enat: ['enat bank'],
  EthiopianInstitution.global: ['global bank'],
  EthiopianInstitution.zamzam: ['zamzam'],
  EthiopianInstitution.hijra: ['hijra'],
  EthiopianInstitution.siinqee: ['siinqee', 'sinqee'],
  EthiopianInstitution.ahadu: ['ahadu'],
  EthiopianInstitution.goh: ['goh betoch'],
  EthiopianInstitution.tsehay: ['tsehay bank'],
  EthiopianInstitution.amhara: ['amhara bank'],
  EthiopianInstitution.tsedey: ['tsedey bank'],
  EthiopianInstitution.sidama: ['sidama bank'],
  EthiopianInstitution.gadaa: ['gadaa bank'],
  EthiopianInstitution.rammis: ['rammis'],
  EthiopianInstitution.shabelle: ['shabelle bank'],
  EthiopianInstitution.omo: ['omo bank'],
  EthiopianInstitution.dbe: ['development bank'],
};

/// Longest alias first, so "cbe birr" is read before "cbe".
final List<(RegExp, EthiopianInstitution)> _aliasMatchers = () {
  final aliases = [
    for (final entry in _aliases.entries)
      for (final alias in entry.value) (alias, entry.key),
  ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));
  return [
    for (final (alias, institution) in aliases)
      (
        RegExp('(^|[^a-z0-9])${RegExp.escape(alias)}(?=[^a-z0-9]|\$)'),
        institution,
      ),
  ];
}();

/// Wording that says the money went to another bank without naming it —
/// Hibret's "To Other Bank - (Ips)" and "Fund Transfer To Ethswitch" (the
/// national interbank switch).
final _otherBank = RegExp(r'\b(other banks?|ips|interbank|ethswitch)\b');

/// Wording that says the money came from some other bank or wallet — BoA's
/// "by A/R - P2P incoming settlement account" (from CBE or telebirr alike).
final _elsewhere = RegExp(r'\bincoming settlement\b');
final _channel = RegExp(r'\b(?:via|through|using)\b');

/// "to Tele-Birr via Mobile", "from Hibret Bank", "by A/R - P2P incoming
/// settlement", "ከ 9000811 - Hibret Bank" — the to/from/by phrase of a
/// receipt, where the other side is named. Not
/// "to your account", and not sign-offs like "Thank you for Banking with
/// CBE".
///
/// A lookahead, so every trigger gets its own window: in "by transaction
/// number DJ1 on ... from Hibret Bank" the "by" window must not swallow the
/// "from" one.
final _counterpartyPhrase = RegExp(
  r'(?=(?:\bto\b|\bfrom\b|\bby\b|(?:^|\s)ከ)\s+(?!your\b)([^.\n።]{1,48}))',
);

class _Mentions {
  const _Mentions(this.institutions, this.otherBank, this.elsewhere);

  final Set<EthiopianInstitution> institutions;
  final bool otherBank;
  final bool elsewhere;

  bool get any => institutions.isNotEmpty || otherBank || elsewhere;
}

_Mentions _institutionsMentionedIn(
  String lower, {
  EthiopianInstitution? exclude,
}) {
  final found = <EthiopianInstitution>{};
  var otherBank = false;
  var elsewhere = false;
  final phrases = exclude == null
      // A bare counterparty name ("Hibret Bank") is all phrase.
      ? [lower]
      : [for (final m in _counterpartyPhrase.allMatches(lower)) m.group(1)!];
  for (final raw in phrases) {
    // "paid ETB 120 to Shoa Supermarket via telebirr": the channel after
    // "via" is not the other side.
    var phrase = raw.split(_channel).first;
    for (final (pattern, institution) in _aliasMatchers) {
      if (!pattern.hasMatch(phrase)) continue;
      phrase = phrase.replaceAll(pattern, ' ');
      if (institution != exclude) found.add(institution);
    }
    if (_otherBank.hasMatch(phrase)) otherBank = true;
    if (_elsewhere.hasMatch(phrase)) elsewhere = true;
  }
  return _Mentions(found, otherBank, elsewhere);
}
