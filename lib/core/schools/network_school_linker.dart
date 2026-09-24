import '../db/app_database.dart';
import '../models/gwn.dart';
import '../models/school.dart';
import 'station_school_linker.dart';

/// Matches a GWN network to a MEHE school by name.
///
/// A network carries no coordinates, so unlike the plant linker this has only
/// the name to go on and therefore demands a clearly higher score before it
/// commits: a wrong link would attribute one school's connectivity to
/// another. Anything short of that is left unlinked and shown as such.
class NetworkSchoolLinker {
  NetworkSchoolLinker(List<School> schools)
      : _schools = schools,
        _byCerd = {for (final s in schools) s.cerd: s},
        _linker = StationSchoolLinker(schools);

  final List<School> _schools;
  final Map<int, School> _byCerd;
  final StationSchoolLinker _linker;

  /// GWN names its networks `<CERD>- <school name>` in this deployment, so
  /// the leading number is an exact key rather than something to guess at.
  /// Tried first; the name comparison below is only the fallback.
  /// The leading number, however it is punctuated. The account writes
  /// `1000- name`, `388A-name`, `1080 Bname`, `1242 B1-name` and
  /// `441 name`, so requiring a separator after the digits missed most of
  /// them. Any number that is not a CERD in the dataset is ignored and the
  /// name comparison takes over, so reading too eagerly costs nothing.
  static final RegExp cerdPrefix = RegExp(r'^\s*(\d{1,6})(?!\d)');

  /// The CERD a network name carries, if it carries one.
  static int? cerdFromName(String name) {
    final m = cerdPrefix.firstMatch(name);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Name-only matching has no second signal to confirm it, so the bar sits
  /// above the plant linker's [StationSchoolLinker.acceptName].
  static const acceptName = 0.72;

  /// …and a runner-up this close means the two schools cannot be told apart.
  static const ambiguousMargin = 0.06;

  /// Best school for [network], or null when nothing is convincing enough.
  ({School school, double confidence})? match(GwnNetwork network) {
    // An exact CERD beats any amount of name similarity.
    final cerd = cerdFromName(network.name);
    if (cerd != null) {
      final s = _byCerd[cerd];
      if (s != null) return (school: s, confidence: 1.0);
    }

    // Otherwise compare names, with any numeric prefix removed so it cannot
    // drown out the words that actually identify the school.
    final bare = network.name.replaceFirst(RegExp(r'^\s*\d{1,6}\s*[A-Za-z]?\d*\s*[-–—_:.]?'), ' ');
    final tokens = StationSchoolLinker.tokenize(bare);
    if (tokens.isEmpty) return null;

    final scored = <({School school, double score})>[];
    for (final s in _schools) {
      final variants = <Set<String>>[
        StationSchoolLinker.tokenize(s.name),
        if (s.nameAr != null) StationSchoolLinker.tokenize(s.nameAr!),
      ].where((v) => v.isNotEmpty);
      var best = 0.0;
      for (final v in variants) {
        final x = _linker.similarity(tokens, v);
        if (x > best) best = x;
      }
      if (best > 0) scored.add((school: s, score: best));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.score.compareTo(a.score));

    final best = scored.first;
    if (best.score < acceptName) return null;
    if (scored.length > 1 && best.score - scored[1].score < ambiguousMargin) return null;
    return (school: best.school, confidence: best.score);
  }

  /// Links every network that has no link yet. Returns how many were linked.
  Future<int> linkAll(AppDatabase db) async {
    final networks = await db.networks.getNetworks();
    var linked = 0;
    for (final n in networks) {
      if (n.cerd != null) continue;
      final m = match(n);
      if (m == null) continue;
      await db.networks.setLink(n.id, m.school.cerd, m.confidence);
      linked++;
    }
    return linked;
  }
}
