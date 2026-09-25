import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';

enum InstitutionKind { bank, wallet }

/// Everything the app knows about one Ethiopian bank or mobile-money wallet:
/// how to recognise its SMS sender IDs, how to name it, and its brand colour
/// for the monogram badge shown next to its transactions.
class InstitutionInfo {
  const InstitutionInfo({
    required this.id,
    required this.name,
    required this.shortName,
    required this.kind,
    required this.brandColor,
    this.senderKeywords = const [],
    this.exactSenders = const [],
    this.signatures = const [],
  });

  final EthiopianInstitution id;

  /// "Commercial Bank of Ethiopia"
  final String name;

  /// "CBE" — used on chips, filters and the monogram badge.
  final String shortName;
  final InstitutionKind kind;

  /// ARGB brand colour for the monogram badge.
  final int brandColor;

  /// Normalised (lower-case, letters+digits only) sender-ID keywords. A
  /// keyword matches when the normalised sender starts with it, or — for
  /// keywords of 6+ characters — contains it ("BankofAbyssinia" ⊃
  /// "abyssinia"). Short keywords are prefix-only so "PROMO" never matches
  /// "omo".
  final List<String> senderKeywords;

  /// Normalised sender IDs that must match exactly: numeric shortcodes
  /// ("127") and short acronyms that are too ambiguous as prefixes ("lib").
  final List<String> exactSenders;

  /// Lower-case sign-off phrases the institution puts in its own receipts.
  final List<String> signatures;

  String get code => id.name;

  String get monogram {
    final letters = shortName.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.length <= 3) return letters.toUpperCase();
    return letters.substring(0, 2).toUpperCase();
  }
}

/// Every NBE-licensed commercial bank and the major mobile-money wallets.
///
/// ORDER MATTERS: the first entry whose keywords match wins, so more specific
/// senders come first ("cbebirr" before "cbe", "coopbankoromia" before
/// "oromia").
const List<InstitutionInfo> kInstitutions = [
  // --- Wallets --------------------------------------------------------------
  InstitutionInfo(
    id: EthiopianInstitution.telebirr,
    name: 'telebirr',
    shortName: 'telebirr',
    kind: InstitutionKind.wallet,
    brandColor: 0xFF0A78C2,
    // Ethio telecom delivers telebirr receipts under its own sender too.
    senderKeywords: ['telebirr', 'ethiotelecom', 'ethiotel'],
    exactSenders: ['127'],
    signatures: [
      'thank you for using telebirr',
      'e-money account',
      'telebirr wallet',
    ],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.cbebirr,
    name: 'CBE Birr',
    shortName: 'CBE Birr',
    kind: InstitutionKind.wallet,
    brandColor: 0xFF8A3FA0,
    senderKeywords: ['cbebirr'],
    signatures: ['cbe birr'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.mpesa,
    name: 'M-PESA Ethiopia',
    shortName: 'M-PESA',
    kind: InstitutionKind.wallet,
    brandColor: 0xFF43B02A,
    senderKeywords: ['mpesa', 'safaricom'],
    signatures: ['m-pesa'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.amole,
    name: 'Amole',
    shortName: 'Amole',
    kind: InstitutionKind.wallet,
    brandColor: 0xFFE2231A,
    senderKeywords: ['amole'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.hellocash,
    name: 'HelloCash',
    shortName: 'HelloCash',
    kind: InstitutionKind.wallet,
    brandColor: 0xFFF7941D,
    senderKeywords: ['hellocash'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.ebirr,
    name: 'eBirr',
    shortName: 'eBirr',
    kind: InstitutionKind.wallet,
    brandColor: 0xFF1565C0,
    senderKeywords: ['ebirr', 'kaafi'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.kacha,
    name: 'Kacha',
    shortName: 'Kacha',
    kind: InstitutionKind.wallet,
    brandColor: 0xFF00A99D,
    senderKeywords: ['kacha'],
  ),

  // --- Banks ----------------------------------------------------------------
  InstitutionInfo(
    id: EthiopianInstitution.cbe,
    name: 'Commercial Bank of Ethiopia',
    shortName: 'CBE',
    kind: InstitutionKind.bank,
    brandColor: 0xFF6B2C91,
    senderKeywords: ['cbe', 'commercialbank'],
    signatures: [
      'thank you for banking with cbe',
      'thanks for banking with cbe',
      'cbe.com.et',
    ],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.awash,
    name: 'Awash Bank',
    shortName: 'Awash',
    kind: InstitutionKind.bank,
    brandColor: 0xFF1D3F8C,
    senderKeywords: ['awash'],
    signatures: ['thank you for banking with awash', 'awash bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.dashen,
    name: 'Dashen Bank',
    shortName: 'Dashen',
    kind: InstitutionKind.bank,
    brandColor: 0xFF003A70,
    // "DB SuperApp" is Dashen's app and sends its own receipts.
    senderKeywords: ['dashen', 'dbsuperapp'],
    signatures: ['dashen bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.boa,
    name: 'Bank of Abyssinia',
    shortName: 'BoA',
    kind: InstitutionKind.bank,
    brandColor: 0xFFD9A300,
    senderKeywords: ['abyssinia', 'boa'],
    signatures: ['bank of abyssinia', 'abyssinia bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.hibret,
    name: 'Hibret Bank',
    shortName: 'Hibret',
    kind: InstitutionKind.bank,
    brandColor: 0xFF0054A6,
    senderKeywords: ['hibret', 'unitedbank'],
    signatures: ['hibret bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.wegagen,
    name: 'Wegagen Bank',
    shortName: 'Wegagen',
    kind: InstitutionKind.bank,
    brandColor: 0xFFE87722,
    senderKeywords: ['wegagen'],
    signatures: ['wegagen bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.nib,
    name: 'Nib International Bank',
    shortName: 'NIB',
    kind: InstitutionKind.bank,
    brandColor: 0xFF00843D,
    senderKeywords: ['nibbank', 'nibinternational', 'nib'],
    signatures: ['nib international bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.coop,
    name: 'Cooperative Bank of Oromia',
    shortName: 'Coopbank',
    kind: InstitutionKind.bank,
    brandColor: 0xFF00A0DF,
    senderKeywords: ['coopbank', 'coop', 'cooperativebank'],
    signatures: ['cooperative bank of oromia', 'coopbank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.oromia,
    name: 'Oromia Bank',
    shortName: 'Oromia',
    kind: InstitutionKind.bank,
    brandColor: 0xFFC8102E,
    senderKeywords: ['oromiabank', 'oromiainternational', 'oromia'],
    exactSenders: ['oib'],
    signatures: ['oromia bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.zemen,
    name: 'Zemen Bank',
    shortName: 'Zemen',
    kind: InstitutionKind.bank,
    brandColor: 0xFFB0122B,
    // Not a bare "zemen" prefix: "ZemenGEBEYA" is a marketplace.
    senderKeywords: ['zemenbank'],
    exactSenders: ['zemen'],
    signatures: ['zemen bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.lion,
    name: 'Lion International Bank',
    shortName: 'Lion',
    kind: InstitutionKind.bank,
    brandColor: 0xFFF2A900,
    senderKeywords: ['lionbank', 'lioninternational'],
    exactSenders: ['lib'],
    signatures: ['lion international bank', 'lion bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.bunna,
    name: 'Bunna Bank',
    shortName: 'Bunna',
    kind: InstitutionKind.bank,
    brandColor: 0xFF6F3F1D,
    senderKeywords: ['bunna'],
    signatures: ['bunna bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.berhan,
    name: 'Berhan Bank',
    shortName: 'Berhan',
    kind: InstitutionKind.bank,
    brandColor: 0xFFF37021,
    senderKeywords: ['berhan'],
    signatures: ['berhan bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.abay,
    name: 'Abay Bank',
    shortName: 'Abay',
    kind: InstitutionKind.bank,
    brandColor: 0xFF0B7A3E,
    senderKeywords: ['abay'],
    signatures: ['abay bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.addis,
    name: 'Addis International Bank',
    shortName: 'Addis',
    kind: InstitutionKind.bank,
    brandColor: 0xFF1F4E79,
    senderKeywords: ['addisbank', 'addisinternational'],
    exactSenders: ['adib', 'aib'],
    signatures: ['addis international bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.enat,
    name: 'Enat Bank',
    shortName: 'Enat',
    kind: InstitutionKind.bank,
    brandColor: 0xFF9B2A8C,
    senderKeywords: ['enat'],
    signatures: ['enat bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.global,
    name: 'Global Bank Ethiopia',
    shortName: 'Global',
    kind: InstitutionKind.bank,
    brandColor: 0xFF0E6BA8,
    senderKeywords: ['globalbank', 'debubglobal', 'debub'],
    signatures: ['global bank', 'debub global'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.zamzam,
    name: 'ZamZam Bank',
    shortName: 'ZamZam',
    kind: InstitutionKind.bank,
    brandColor: 0xFF1B8E3E,
    senderKeywords: ['zamzam'],
    signatures: ['zamzam bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.hijra,
    name: 'Hijra Bank',
    shortName: 'Hijra',
    kind: InstitutionKind.bank,
    brandColor: 0xFF13714A,
    senderKeywords: ['hijra'],
    signatures: ['hijra bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.siinqee,
    name: 'Siinqee Bank',
    shortName: 'Siinqee',
    kind: InstitutionKind.bank,
    brandColor: 0xFFB5121B,
    senderKeywords: ['siinqee', 'sinqee'],
    signatures: ['siinqee bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.ahadu,
    name: 'Ahadu Bank',
    shortName: 'Ahadu',
    kind: InstitutionKind.bank,
    brandColor: 0xFF5B2A86,
    senderKeywords: ['ahadu'],
    signatures: ['ahadu bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.goh,
    name: 'Goh Betoch Bank',
    shortName: 'Goh',
    kind: InstitutionKind.bank,
    brandColor: 0xFF0F5E9C,
    senderKeywords: ['gohbetoch', 'gohbank'],
    signatures: ['goh betoch'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.tsehay,
    name: 'Tsehay Bank',
    shortName: 'Tsehay',
    kind: InstitutionKind.bank,
    brandColor: 0xFFE8A317,
    senderKeywords: ['tsehay'],
    signatures: ['tsehay bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.amhara,
    name: 'Amhara Bank',
    shortName: 'Amhara',
    kind: InstitutionKind.bank,
    brandColor: 0xFF1A5F9E,
    senderKeywords: ['amharabank', 'amhara'],
    signatures: ['amhara bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.tsedey,
    name: 'Tsedey Bank',
    shortName: 'Tsedey',
    kind: InstitutionKind.bank,
    brandColor: 0xFF7A3E9D,
    senderKeywords: ['tsedey', 'tsedeybank'],
    signatures: ['tsedey bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.sidama,
    name: 'Sidama Bank',
    shortName: 'Sidama',
    kind: InstitutionKind.bank,
    brandColor: 0xFF2E7D32,
    senderKeywords: ['sidama'],
    signatures: ['sidama bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.gadaa,
    name: 'Gadaa Bank',
    shortName: 'Gadaa',
    kind: InstitutionKind.bank,
    brandColor: 0xFFC62828,
    senderKeywords: ['gadaa'],
    signatures: ['gadaa bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.rammis,
    name: 'Rammis Bank',
    shortName: 'Rammis',
    kind: InstitutionKind.bank,
    brandColor: 0xFF00695C,
    senderKeywords: ['rammis'],
    signatures: ['rammis bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.shabelle,
    name: 'Shabelle Bank',
    shortName: 'Shabelle',
    kind: InstitutionKind.bank,
    brandColor: 0xFF0277BD,
    senderKeywords: ['shabelle'],
    signatures: ['shabelle bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.omo,
    name: 'Omo Bank',
    shortName: 'Omo',
    kind: InstitutionKind.bank,
    brandColor: 0xFF558B2F,
    senderKeywords: ['omobank', 'omo'],
    signatures: ['omo bank'],
  ),
  InstitutionInfo(
    id: EthiopianInstitution.dbe,
    name: 'Development Bank of Ethiopia',
    shortName: 'DBE',
    kind: InstitutionKind.bank,
    brandColor: 0xFF00529B,
    senderKeywords: ['developmentbank'],
    exactSenders: ['dbe'],
    signatures: ['development bank of ethiopia'],
  ),
];

const InstitutionInfo kUnknownInstitution = InstitutionInfo(
  id: EthiopianInstitution.unknown,
  name: 'Other',
  shortName: 'Other',
  kind: InstitutionKind.bank,
  brandColor: 0xFF7A8099,
);

final Map<EthiopianInstitution, InstitutionInfo> _byId = {
  for (final info in kInstitutions) info.id: info,
};

InstitutionInfo institutionInfo(EthiopianInstitution id) =>
    _byId[id] ?? kUnknownInstitution;

/// Looks up by the persisted code (`EthiopianInstitution.name`), tolerating
/// null/unknown codes from older rows.
InstitutionInfo institutionInfoForCode(String? code) {
  final normalized = code?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return kUnknownInstitution;
  for (final info in kInstitutions) {
    if (info.code.toLowerCase() == normalized) return info;
  }
  return kUnknownInstitution;
}

String _normalizeSender(String sender) =>
    sender.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Resolves the institution behind an SMS sender ID, or `unknown`.
///
/// Personal phone numbers never match: purely numeric senders only match an
/// exact shortcode, so "+251911270000" is not telebirr's "127".
EthiopianInstitution institutionForSender(String sender) {
  final normalized = _normalizeSender(sender);
  if (normalized.isEmpty) return EthiopianInstitution.unknown;
  final numeric = RegExp(r'^[0-9]+$').hasMatch(normalized);
  for (final info in kInstitutions) {
    if (info.exactSenders.contains(normalized)) return info.id;
    if (numeric) continue;
    for (final keyword in info.senderKeywords) {
      if (normalized.startsWith(keyword)) return info.id;
      if (keyword.length >= 6 && normalized.contains(keyword)) return info.id;
    }
  }
  return EthiopianInstitution.unknown;
}

/// True when [sender] is a recognised Ethiopian bank or wallet — the only
/// senders sync reads. Personal chats, OTP services and promos are skipped
/// before they are ever stored.
bool isFinancialSender(String sender) =>
    institutionForSender(sender) != EthiopianInstitution.unknown;

/// Best-effort institution for a message from an unrecognised sender, from
/// the sign-off phrase in its body. A mere mention of another bank ("from
/// CBE account") deliberately does not count.
EthiopianInstitution inferInstitutionFromSignature(String lowered) {
  for (final info in kInstitutions) {
    if (info.signatures.any(lowered.contains)) return info.id;
  }
  return EthiopianInstitution.unknown;
}
