import 'package:flutter/material.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';

/// Brand-coloured monogram for a bank or wallet ("CBE", "AW", "M-").
///
/// Deliberately not the institutions' official logos: those are trademarks,
/// and Play's impersonation policy flags apps that show them without
/// permission. The brand colour plus short name is enough to recognise an
/// account at a glance.
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
