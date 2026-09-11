import 'dart:convert';

import '../api/json_utils.dart';
import '../db/app_database.dart';
import '../models/school.dart';

/// The bundled `assets/data/schools.json` (built by
/// `scripts/build_school_dataset.py` from the MEHE / UNICEF workbooks).
class SchoolDataset {
  const SchoolDataset({required this.version, required this.generatedAt, required this.sources, required this.schools, required this.equipment});

  final int version;
  final String generatedAt;
  final List<String> sources;
  final List<School> schools;
  final List<SchoolEquipment> equipment;

  static const assetPath = 'assets/data/schools.json';

  static SchoolDataset fromJson(String text) {
    final root = asMap(jsonDecode(text));
    final schools = <School>[];
    final equipment = <SchoolEquipment>[];
    for (final item in root['schools'] as List? ?? const []) {
      final j = asMap(item);
      final s = School.fromJson(j);
      if (s == null) continue;
      schools.add(s);
      for (final e in j['equipment'] as List? ?? const []) {
        final eq = SchoolEquipment.fromJson(s.cerd, e);
        if (eq != null) equipment.add(eq);
      }
    }
    return SchoolDataset(
      version: asInt(root['version']) ?? 1,
      generatedAt: asString(root['generatedAt']) ?? '',
      sources: [for (final s in root['sources'] as List? ?? const []) s.toString()],
      schools: schools,
      equipment: equipment,
    );
  }

  int get solarizedCount => schools.where((s) => s.isSolarized).length;
  int get connectedCount => schools.where((s) => s.connected).length;

  /// Solarised schools with coordinates — used to seed the demo fleet so the
  /// plant ↔ school linking can be exercised without a DeyeCloud account.
  List<DemoSeed> get demoSeeds => [
        for (final s in schools)
          if (s.isSolarized && s.hasLocation && (s.solar?.kwp ?? 0) > 0)
            DemoSeed(
              cerd: s.cerd,
              name: s.solar?.listedName ?? s.name,
              region: s.region ?? '',
              lat: s.lat!,
              lng: s.lng!,
              kwp: s.solar!.kwp!,
              batteryKwh: s.solar?.batteryKwh,
              address: [s.caza, s.region].whereType<String>().join(', '),
            ),
      ];
}

/// A real solarised school used as the identity of a synthetic demo plant.
class DemoSeed {
  const DemoSeed({required this.cerd, required this.name, required this.region, required this.lat, required this.lng, required this.kwp, this.batteryKwh, this.address = ''});
  final int cerd;
  final String name;
  final String region;
  final double lat;
  final double lng;
  final double kwp;
  final double? batteryKwh;
  final String address;
}

/// Summary of what is in the database (Settings → school dataset card).
class SchoolDatasetInfo {
  const SchoolDatasetInfo({required this.version, required this.generatedAt, required this.importedAt, required this.schools, required this.solarized, required this.connected, required this.links, required this.manualLinks});
  final int? version;
  final String? generatedAt;
  final int? importedAt;
  final int schools;
  final int solarized;
  final int connected;
  final int links;
  final int manualLinks;
  bool get isImported => version != null && schools > 0;
}

/// Imports the bundled dataset into SQLite once per dataset version.
class SchoolDatasetImporter {
  SchoolDatasetImporter(this.db, {this.log});
  final AppDatabase db;
  final void Function(String)? log;

  static const metaVersion = 'schools.datasetVersion';
  static const metaGeneratedAt = 'schools.generatedAt';
  static const metaImportedAt = 'schools.importedAt';

  /// Returns true when the dataset was (re-)imported.
  Future<bool> importIfNeeded(SchoolDataset dataset, {bool force = false}) async {
    final current = await db.sync.metaGet(metaVersion);
    final count = await db.schools.countSchools();
    if (!force && current == '${dataset.version}' && count > 0) return false;
    await db.schools.replaceDataset(schools: dataset.schools, equipment: dataset.equipment);
    await db.sync.metaSet(metaVersion, '${dataset.version}');
    await db.sync.metaSet(metaGeneratedAt, dataset.generatedAt);
    await db.sync.metaSet(metaImportedAt, '${nowEpoch()}');
    log?.call('School dataset v${dataset.version} imported: ${dataset.schools.length} schools, ${dataset.equipment.length} equipment lines');
    db.notifyChanged(DataKind.schools);
    return true;
  }

  Future<SchoolDatasetInfo> info() async {
    final links = await db.schools.getLinks();
    return SchoolDatasetInfo(
      version: int.tryParse(await db.sync.metaGet(metaVersion) ?? ''),
      generatedAt: await db.sync.metaGet(metaGeneratedAt),
      importedAt: int.tryParse(await db.sync.metaGet(metaImportedAt) ?? ''),
      schools: await db.schools.countSchools(),
      solarized: (await db.schools.getSchools(solarized: true)).length,
      connected: (await db.schools.getSchools(connected: true)).length,
      links: links.length,
      manualLinks: links.values.where((l) => l.isManual).length,
    );
  }
}
