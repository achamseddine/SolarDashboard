import 'dart:math' as math;

import '../db/app_database.dart';
import '../models/school.dart';
import '../models/station.dart';

/// Matches DeyeCloud plants to MEHE schools (CERD numbers).
///
/// Evidence, strongest first:
///  1. a CERD number written in the plant name (`CERD 123`, `#123`, `(123)`);
///  2. name similarity (weighted token overlap of the plant name against the
///     MEHE English name, the solar tracker's name and the Arabic name),
///     combined with the distance between plant and school coordinates;
///  3. coordinates alone when a single school lies within 150 m.
///
/// Manual links are never overwritten.
class StationSchoolLinker {
  StationSchoolLinker(List<School> schools) : _schools = schools {
    _index();
  }

  final List<School> _schools;
  final Map<int, _Indexed> _byCerd = {};
  final Map<String, List<int>> _byToken = {};
  final Map<String, double> _weights = {};

  static const acceptName = 0.62;
  static const acceptCombined = 0.55;
  static const nearMetres = 150.0;
  static const farMetres = 5000.0;

  void _index() {
    final df = <String, int>{};
    for (final s in _schools) {
      final variants = <Set<String>>[
        tokenize(s.name),
        if (s.solar?.listedName != null) tokenize(s.solar!.listedName!),
        if (s.nameAr != null) tokenize(s.nameAr!),
      ].where((v) => v.isNotEmpty).toList();
      final tokens = {for (final v in variants) ...v};
      _byCerd[s.cerd] = _Indexed(s, variants);
      for (final t in tokens) {
        df[t] = (df[t] ?? 0) + 1;
        _byToken.putIfAbsent(t, () => []).add(s.cerd);
      }
    }
    final n = math.max(1, _schools.length);
    df.forEach((t, c) => _weights[t] = math.log(n / c) + 0.1);
  }

  double _w(String t) => _weights[t] ?? (math.log(math.max(1, _schools.length)) + 0.1);

  /// Best weighted Jaccard similarity of [a] against any name variant.
  double _bestSimilarity(Set<String> a, _Indexed ix) {
    var best = 0.0;
    for (final v in ix.variants) {
      final s = similarity(a, v);
      if (s > best) best = s;
    }
    return best;
  }

  /// Weighted Jaccard similarity of two token sets.
  double similarity(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    var inter = 0.0, union = 0.0;
    for (final t in a) {
      final w = _w(t);
      union += w;
      if (b.contains(t)) inter += w;
    }
    for (final t in b) {
      if (!a.contains(t)) union += _w(t);
    }
    return union == 0 ? 0 : inter / union;
  }

  /// Best candidate for [station], or null when nothing is convincing.
  LinkCandidate? match(Station station) {
    final name = station.name;
    // 1. explicit CERD number in the plant name.
    for (final m in RegExp(r'(?:cerd|#|\bid)\s*[:.\-]?\s*(\d{1,5})\b|\((\d{1,5})\)', caseSensitive: false).allMatches(name)) {
      final c = int.tryParse(m.group(1) ?? m.group(2) ?? '');
      if (c != null && _byCerd.containsKey(c)) {
        return LinkCandidate(school: _byCerd[c]!.school, method: LinkMethod.cerd, confidence: 0.97, nameScore: 1, distanceM: _distance(station, _byCerd[c]!.school));
      }
    }

    final tokens = tokenize(name);
    final candidates = <int>{};
    for (final t in tokens) {
      final ids = _byToken[t];
      if (ids != null && ids.length <= 400) candidates.addAll(ids);
    }
    final hasLoc = station.lat != null && station.lng != null;
    if (hasLoc) {
      for (final s in _schools) {
        if (s.hasLocation && (s.lat! - station.lat!).abs() < 0.05 && (s.lng! - station.lng!).abs() < 0.06) candidates.add(s.cerd);
      }
    }
    if (candidates.isEmpty) return null;

    final scored = <LinkCandidate>[];
    for (final c in candidates) {
      final ix = _byCerd[c]!;
      final nameScore = _bestSimilarity(tokens, ix);
      final d = _distance(station, ix.school);
      final locScore = d == null ? null : _locationScore(d);
      double conf;
      LinkMethod method;
      if (locScore != null) {
        if (d! > farMetres && nameScore < 0.9) continue; // different place
        conf = 0.65 * nameScore + 0.35 * locScore;
        method = nameScore >= acceptName ? LinkMethod.nameLocation : LinkMethod.location;
      } else {
        conf = nameScore;
        method = LinkMethod.name;
      }
      if (ix.school.isSolarized) conf += 0.03; // programme schools are the likely fleet
      scored.add(LinkCandidate(school: ix.school, method: method, confidence: conf.clamp(0, 1).toDouble(), nameScore: nameScore, distanceM: d));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.confidence.compareTo(a.confidence));
    final best = scored.first;
    final runnerUp = scored.length > 1 ? scored[1] : null;

    // Ambiguity guard: a close runner-up means we cannot tell the schools
    // apart (e.g. two schools sharing one compound) unless the coordinates do.
    bool ambiguous() {
      if (runnerUp == null) return false;
      if (best.confidence - runnerUp.confidence >= 0.08) return false;
      final d1 = best.distanceM, d2 = runnerUp.distanceM;
      return d1 == null || d2 == null || (d2 - d1).abs() < 80;
    }

    if (best.method == LinkMethod.nameLocation && best.confidence >= acceptCombined && !ambiguous()) return best;
    if (best.method == LinkMethod.name && best.nameScore >= acceptName + 0.1 && !ambiguous()) return best;

    // Location fallback: exactly one school within [nearMetres].
    final near = scored.where((c) => c.distanceM != null && c.distanceM! <= nearMetres).toList()..sort((a, b) => a.distanceM!.compareTo(b.distanceM!));
    if (near.isNotEmpty) {
      final second = scored.where((c) => c.distanceM != null && c.school.cerd != near.first.school.cerd).map((c) => c.distanceM!).fold<double?>(null, (m, d) => m == null || d < m ? d : m);
      if (second == null || second > 2 * nearMetres) {
        final c = near.first;
        return LinkCandidate(school: c.school, method: LinkMethod.location, confidence: (0.5 + 0.3 * (1 - c.distanceM! / nearMetres) + 0.2 * c.nameScore).clamp(0, 0.9).toDouble(), nameScore: c.nameScore, distanceM: c.distanceM);
      }
    }
    return null;
  }

  /// Links every non-archived plant that has no manual link. Returns the
  /// number of links written.
  Future<int> linkAll(AppDatabase db, {int? now}) async {
    final stations = await db.stations.getStations();
    final existing = await db.schools.getLinks();
    final ts = now ?? nowEpoch();
    final links = <StationSchoolLink>[];
    final unlink = <int>[];
    for (final st in stations) {
      final cur = existing[st.id];
      if (cur != null && cur.isManual) continue;
      final best = match(st);
      if (best == null) {
        if (cur != null) unlink.add(st.id);
        continue;
      }
      if (cur != null && cur.cerd == best.school.cerd && (cur.confidence - best.confidence).abs() < 0.001) continue;
      links.add(StationSchoolLink(stationId: st.id, cerd: best.school.cerd, method: best.method, confidence: best.confidence, updatedAt: ts));
    }
    for (final id in unlink) {
      await db.schools.deleteLink(id);
    }
    await db.schools.upsertLinks(links);
    if (links.isNotEmpty || unlink.isNotEmpty) db.notifyChanged(DataKind.schools);
    return links.length;
  }

  /// Top [limit] suggestions for the manual link picker.
  List<LinkCandidate> suggestions(Station station, {int limit = 8}) {
    final tokens = tokenize(station.name);
    final out = <LinkCandidate>[];
    for (final ix in _byCerd.values) {
      final nameScore = _bestSimilarity(tokens, ix);
      final d = _distance(station, ix.school);
      final loc = d == null ? 0.0 : _locationScore(d);
      final conf = d == null ? nameScore : 0.65 * nameScore + 0.35 * loc;
      if (conf > 0.15) out.add(LinkCandidate(school: ix.school, method: LinkMethod.manual, confidence: conf, nameScore: nameScore, distanceM: d));
    }
    out.sort((a, b) => b.confidence.compareTo(a.confidence));
    return out.take(limit).toList();
  }

  static double _locationScore(double d) {
    if (d <= nearMetres) return 1;
    if (d <= 500) return 0.8;
    if (d <= 1500) return 0.5;
    if (d <= farMetres) return 0.2;
    return 0;
  }

  static double? _distance(Station st, School s) {
    if (st.lat == null || st.lng == null || !s.hasLocation) return null;
    return haversineMetres(st.lat!, st.lng!, s.lat!, s.lng!);
  }

  static double haversineMetres(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  // ------------------------------------------------------------ tokenizer

  static const _stop = {
    'public', 'school', 'schools', 'official', 'mixed', 'for', 'the', 'of', 'and', 'in', 'a', 'de', 'des', 'du', 'la', 'le',
    'ecole', 'école', 'officielle', 'publique', 'lycee', 'lycée', 'previously', 'formerly', 'new', 'old', 'complex', 'compound',
    'رسمية', 'الرسمية', 'مدرسة', 'المختلطة', 'مختلطة', 'ثانوية', 'الثانوية', 'متوسطة', 'المتوسطة', 'ابتدائية', 'الابتدائية', 'للبنات', 'للبنين', 'للصبيان', 'التكميلية', 'تكميلية',
  };
  static const _ordinals = {
    'first': '1', '1st': '1', 'i': '1', 'second': '2', '2nd': '2', 'ii': '2', 'third': '3', '3rd': '3', 'iii': '3', 'fourth': '4', '4th': '4', 'fifth': '5', '5th': '5',
    'الاولى': '1', 'الأولى': '1', 'الثانية': '2', 'الثالثة': '3', 'الرابعة': '4', 'الخامسة': '5',
  };

  /// Lower-cases, strips punctuation, folds common Lebanese transliteration
  /// variants and drops generic words.
  static Set<String> tokenize(String s) {
    final out = <String>{};
    final cleaned = s.toLowerCase().replaceAll(RegExp(r"[’'`´]"), '').replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
    for (var t in cleaned.split(' ')) {
      t = t.trim();
      if (t.isEmpty) continue;
      t = _ordinals[t] ?? t;
      if (_stop.contains(t)) continue;
      if (RegExp(r'^[a-z]').hasMatch(t)) {
        if (t == 'al' || t == 'el' || t == 'as' || t == 'es') continue;
        t = t.replaceFirst(RegExp(r'^(al|el)(?=[a-z]{3,})'), '');
        t = fold(t);
      } else {
        t = foldArabic(t);
        if (t.isEmpty) continue;
      }
      if (t.length < 2) continue;
      out.add(t);
    }
    return out;
  }

  /// Latin transliteration folding to a consonant skeleton
  /// (Achrafieh/Ashrafiyeh → khrf, Msaytbeh/Mousseitbeh → mstb, Tariq/Tarik → trk).
  static String fold(String t) {
    var x = t;
    x = x.replaceAll('sh', 'ch').replaceAll('ph', 'f').replaceAll('th', 't').replaceAll('dh', 'd').replaceAll('gh', 'g');
    x = x.replaceAll('kh', 'x').replaceAll('ch', 'x').replaceAll('q', 'k').replaceAll('c', 'k');
    x = x.replaceAll('w', 'u').replaceAll('y', 'i').replaceAll('z', 's').replaceAll('v', 'f').replaceAll('j', 'g');
    x = x.replaceAll(RegExp(r'[aeiou]h$'), ''); // -eh / -ah endings
    final lead = RegExp(r'^[aeiou]').hasMatch(x) ? 'a' : '';
    x = lead + x.replaceAll(RegExp(r'[aeiou]'), '');
    x = x.replaceAllMapped(RegExp(r'([a-z])\1+'), (m) => m.group(1)!);
    return x.isEmpty ? t : x;
  }

  /// Arabic normalisation: alef variants, taa marbuta, diacritics, ال prefix.
  static String foldArabic(String t) {
    var x = t.replaceAll(RegExp(r'[ً-ْـ]'), '');
    x = x.replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ة', 'ه').replaceAll('ى', 'ي').replaceAll('ؤ', 'و').replaceAll('ئ', 'ي');
    x = x.replaceFirst(RegExp(r'^(ال|وال|بال|لل)'), '');
    return x;
  }
}

class _Indexed {
  _Indexed(this.school, this.variants);
  final School school;

  /// Token sets of the English, tracker and Arabic names.
  final List<Set<String>> variants;
}

/// A proposed plant ↔ school match.
class LinkCandidate {
  const LinkCandidate({required this.school, required this.method, required this.confidence, required this.nameScore, this.distanceM});
  final School school;
  final LinkMethod method;
  final double confidence;
  final double nameScore;
  final double? distanceM;
}
