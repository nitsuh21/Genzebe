import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/design_system/institution_avatar.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';

void main() {
  group('institutionForSender', () {
    const cases = <String, EthiopianInstitution>{
      'CBE': EthiopianInstitution.cbe,
      'CBEBirr': EthiopianInstitution.cbebirr,
      'CBE Birr': EthiopianInstitution.cbebirr,
      '127': EthiopianInstitution.telebirr,
      'telebirr': EthiopianInstitution.telebirr,
      'Ethio telecom': EthiopianInstitution.telebirr,
      'AwashBank': EthiopianInstitution.awash,
      'Dashen Bank': EthiopianInstitution.dashen,
      'BankofAbyssinia': EthiopianInstitution.boa,
      'BoA': EthiopianInstitution.boa,
      'HibretBank': EthiopianInstitution.hibret,
      'Wegagen': EthiopianInstitution.wegagen,
      'NIB': EthiopianInstitution.nib,
      'Coopbank': EthiopianInstitution.coop,
      'OromiaBank': EthiopianInstitution.oromia,
      'ZemenBank': EthiopianInstitution.zemen,
      'LIB': EthiopianInstitution.lion,
      'BunnaBank': EthiopianInstitution.bunna,
      'BerhanBank': EthiopianInstitution.berhan,
      'AbayBank': EthiopianInstitution.abay,
      'EnatBank': EthiopianInstitution.enat,
      'GlobalBank': EthiopianInstitution.global,
      'ZamZam Bank': EthiopianInstitution.zamzam,
      'HijraBank': EthiopianInstitution.hijra,
      'Siinqee': EthiopianInstitution.siinqee,
      'AhaduBank': EthiopianInstitution.ahadu,
      'TsehayBank': EthiopianInstitution.tsehay,
      'AmharaBank': EthiopianInstitution.amhara,
      'GadaaBank': EthiopianInstitution.gadaa,
      'M-PESA': EthiopianInstitution.mpesa,
      'Amole': EthiopianInstitution.amole,
      'HelloCash': EthiopianInstitution.hellocash,
      'eBirr': EthiopianInstitution.ebirr,
      // Sender IDs exactly as seen on a real phone (2026-09-25).
      'Awash Bank': EthiopianInstitution.awash,
      'Bunna Bank': EthiopianInstitution.bunna,
      'WegagenBank': EthiopianInstitution.wegagen,
      'AMHARA BANK': EthiopianInstitution.amhara,
      'Gadaa Bank': EthiopianInstitution.gadaa,
      'MPESA': EthiopianInstitution.mpesa,
      'Safaricom': EthiopianInstitution.unknown,
      'Sidama Reg': EthiopianInstitution.unknown,
      'SidamaBank': EthiopianInstitution.sidama,
      'DB SuperApp': EthiopianInstitution.dashen,
      'ethio tel': EthiopianInstitution.telebirr,
      'BOA': EthiopianInstitution.boa,
      // Never financial: people, OTP services, promos, look-alikes.
      '+251911270000': EthiopianInstitution.unknown,
      '0912345678': EthiopianInstitution.unknown,
      '8397': EthiopianInstitution.unknown,
      'PROMO': EthiopianInstitution.unknown,
      'SafariPromo': EthiopianInstitution.unknown,
      'Library': EthiopianInstitution.unknown,
      'GebeyaGo': EthiopianInstitution.unknown,
      'ZemenGEBEYA': EthiopianInstitution.unknown,
      'ELSLottery': EthiopianInstitution.unknown,
      'TWVerify': EthiopianInstitution.unknown,
      'RIDE_8294': EthiopianInstitution.unknown,
      'National ID': EthiopianInstitution.unknown,
      'Fraud-Alert': EthiopianInstitution.unknown,
      'SOMEBANK': EthiopianInstitution.unknown,
      '': EthiopianInstitution.unknown,
    };
    cases.forEach((sender, expected) {
      test('"$sender" -> ${expected.name}', () {
        expect(institutionForSender(sender), expected);
      });
    });
  });

  test('every institution except unknown is registered exactly once', () {
    final registered = kInstitutions.map((i) => i.id).toList();
    expect(registered.toSet().length, registered.length);
    for (final id in EthiopianInstitution.values) {
      if (id == EthiopianInstitution.unknown) continue;
      expect(registered, contains(id), reason: '${id.name} missing');
    }
  });

  test('every institution can be recognised by some sender', () {
    for (final info in kInstitutions) {
      expect(
        info.senderKeywords.isNotEmpty || info.exactSenders.isNotEmpty,
        isTrue,
        reason: info.name,
      );
    }
  });

  test('codes round-trip for persisted account rows', () {
    for (final info in kInstitutions) {
      expect(institutionInfoForCode(info.code).id, info.id);
    }
    expect(institutionInfoForCode(null), kUnknownInstitution);
    expect(institutionInfoForCode('retired-bank'), kUnknownInstitution);
  });

  test('every bundled logo belongs to an institution and exists', () {
    final codes = kInstitutions.map((i) => i.code).toSet();
    for (final code in kInstitutionsWithLogo) {
      expect(codes, contains(code), reason: 'unknown institution $code');
      expect(File('assets/logos/$code.png').existsSync(), isTrue,
          reason: 'missing assets/logos/$code.png');
    }
    // The banks and wallets seen on the owner's phone all have logos.
    for (final code in [
      'cbe',
      'telebirr',
      'hibret',
      'boa',
      'awash',
      'dashen',
      'gadaa',
      'mpesa',
      'wegagen',
      'amhara',
      'bunna',
      'abay',
      'ahadu',
    ]) {
      expect(kInstitutionsWithLogo, contains(code));
    }
  });
}
