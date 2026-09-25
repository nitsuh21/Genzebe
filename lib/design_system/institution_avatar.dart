import 'package:flutter/material.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';

/// Institutions with a bundled logo in `assets/logos/<code>.png` (sources in
/// assets/logos/SOURCES.md). Everyone else gets a brand-coloured monogram.
const Set<String> kInstitutionsWithLogo = {
  'abay',
  'ahadu',
  'amhara',
  'awash',
  'berhan',
  'boa',
  'bunna',
  'cbe',
  'coop',
  'dashen',
  'ebirr',
  'enat',
  'gadaa',
  'global',
  'hibret',
  'hijra',
  'kacha',
  'lion',
  'mpesa',
  'nib',
  'omo',
  'oromia',
  'shabelle',
  'siinqee',
  'telebirr',
  'wegagen',
  'zamzam',
  'zemen',
};

/// The bank's or wallet's logo, or a brand-coloured monogram ("CBE", "AW")
/// when no logo is bundled. The logos are the institutions' trademarks,
/// shown only to identify which account a transaction belongs to.
class InstitutionAvatar extends StatelessWidget {
  const InstitutionAvatar({
    super.key,
    required this.info,
    this.size = 40,
  });

  InstitutionAvatar.forCode(String? code, {Key? key, double size = 40})
      : this(key: key, info: institutionInfoForCode(code), size: size);

  final InstitutionInfo info;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (kInstitutionsWithLogo.contains(info.code)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: Container(
          width: size,
          height: size,
          color: Colors.white,
          child: Image.asset(
            'assets/logos/${info.code}.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            // A missing/corrupt asset must never break a list row.
            errorBuilder: (_, __, ___) => _monogram(),
          ),
        ),
      );
    }
    return _monogram();
  }

  Widget _monogram() {
    final color = Color(info.brandColor);
    final isUnknown = info.id == kUnknownInstitution.id;
    final monogram = info.monogram;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.12)!,
            Color.lerp(color, Colors.black, 0.12)!,
          ],
        ),
      ),
      child: isUnknown
          ? Icon(Icons.account_balance_rounded,
              color: Colors.white, size: size * 0.5)
          : Text(
              monogram,
              maxLines: 1,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                fontSize: size * (monogram.length >= 3 ? 0.3 : 0.36),
              ),
            ),
    );
  }
}
