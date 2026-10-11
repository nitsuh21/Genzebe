import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Banks and wallets the user turned off. Every sync, history rebuild and
/// background receipt skips their messages until they're turned back on.
class ExcludedInstitutionsStore {
  const ExcludedInstitutionsStore();

  static const prefKey = 'excluded_institutions';

  Future<Set<EthiopianInstitution>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final codes = prefs.getStringList(prefKey) ?? const [];
    final byName = EthiopianInstitution.values.asNameMap();
    return {
      for (final code in codes)
        if (byName[code] case final id?) id,
    }..remove(EthiopianInstitution.unknown);
  }

  Future<void> save(Set<EthiopianInstitution> excluded) async {
    final prefs = await SharedPreferences.getInstance();
    final codes = [
      for (final id in excluded)
        if (id != EthiopianInstitution.unknown) id.name,
    ]..sort();
    await prefs.setStringList(prefKey, codes);
  }
}
