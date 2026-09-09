import 'dart:convert';
import 'dart:math' as math;

import '../api/json_utils.dart';

/// The nine governorates (muhafazat) of Lebanon (Law 522/2017 created
/// Keserwan-Jbeil out of Mount Lebanon).
class LebanonRegions {
  LebanonRegions._();

  static const beirut = 'Beirut';
  static const mountLebanon = 'Mount Lebanon';
  static const keserwanJbeil = 'Keserwan-Jbeil';
  static const north = 'North';
  static const akkar = 'Akkar';
  static const baalbekHermel = 'Baalbek-Hermel';
  static const bekaa = 'Bekaa';
  static const south = 'South';
  static const nabatieh = 'Nabatieh';
  static const unassigned = 'Unassigned';

  static const List<String> all = [beirut, mountLebanon, keserwanJbeil, north, akkar, baalbekHermel, bekaa, south, nabatieh];

  /// geoBoundaries ADM1 `shapeName` → canonical English name.
  static const Map<String, String> boundaryNames = {
    'Beyrouth': beirut,
    'Mont-Liban': mountLebanon,
    'Keserwan-Jbeil': keserwanJbeil,
    'Liban-Nord': north,
    'Aakkâr': akkar,
    'Baalbek-Hermel': baalbekHermel,
    'Béqaa': bekaa,
    'Liban-Sud': south,
    'Nabatîyé': nabatieh,
  };

  /// geoBoundaries ADM2 district → governorate.
  static const Map<String, String> districtToRegion = {
    'Beirut': beirut,
    'Baabda': mountLebanon,
    'Aley': mountLebanon,
    'Chouf': mountLebanon,
    'El Metn': mountLebanon,
    'Kesrouan': keserwanJbeil,
    'Jbail': keserwanJbeil,
    'Tripoli': north,
    'Koura': north,
    'Zgharta': north,
    'Bcharre': north,
    'Batroun': north,
    'Minieh-Dinnieh': north,
    'Akkar': akkar,
    'Baalbek': baalbekHermel,
    'Hermel': baalbekHermel,
    'Zahle': bekaa,
    'West Bekaa': bekaa,
    'Rachaya': bekaa,
    'Saida': south,
    'Sour': south,
    'Jezzine': south,
    'Nabatiye': nabatieh,
    'Hasbaya': nabatieh,
    'Marjaayoun': nabatieh,
    'Bent Jbail': nabatieh,
  };

  /// Keyword → governorate, matched case-insensitively against the plant
  /// name and address (districts, major towns, transliteration variants).
  static const Map<String, List<String>> _keywords = {
    beirut: ['beirut', 'beyrouth', 'bayrut', 'achrafieh', 'ashrafieh', 'hamra', 'ras beirut', 'mazraa', 'msaytbeh', 'bachoura', 'rmeil', 'medawar', 'zokak el blat', 'minet el hosn', 'saifi', 'verdun', 'tarik jdideh', 'tariq el jdideh'],
    mountLebanon: [
      'mount lebanon', 'mont liban', 'jabal lubnan', 'baabda', 'aley', 'aleih', 'chouf', 'shouf', 'metn', 'matn',
      'bourj hammoud', 'burj hammoud', 'dekwaneh', 'sin el fil', 'hazmieh', 'hadath', 'chiyah', 'ghobeiri', 'bourj el barajneh', 'burj al barajneh',
      'haret hreik', 'dahieh', 'choueifat', 'shweifat', 'beit mery', 'broummana', 'bikfaya', 'antelias', 'dbayeh', 'jal el dib', 'damour',
      'deir el qamar', 'beiteddine', 'barouk', 'jiyeh', 'naameh', 'bhamdoun', 'sofar', 'khalde', 'baakline', 'baaqline', 'mansourieh', 'fanar', 'jdeideh',
      'bourj abi haidar', 'kahale', 'aramoun', 'bchamoun', 'chbanieh', 'ras el metn', 'dhour choueir', 'zalka', 'furn el chebbak', 'ain el remmaneh',
    ],
    keserwanJbeil: ['keserwan', 'kesrouan', 'kesrwan', 'kesserwan', 'jbeil', 'jbail', 'byblos', 'jounieh', 'jounie', 'zouk', 'ajaltoun', 'faraya', 'amchit', 'halat', 'okaibe', 'ghazir', 'sarba', 'kaslik', 'harissa', 'daraoun', 'kfardebian', 'jeita', 'ballouneh', 'adma', 'safra', 'tabarja', 'aqoura', 'laklouk', 'qartaba', 'annaya', 'mastita', 'blat jbeil'],
    north: ['tripoli', 'trablous', 'tarabulus', 'north lebanon', 'liban nord', 'koura', 'zgharta', 'bcharre', 'bsharri', 'batroun', 'minieh', 'miniyeh', 'danniyeh', 'dinniyeh', 'el mina', 'qalamoun', 'chekka', 'amioun', 'ehden', 'kfarhazir', 'beddawi', 'bakhoun', 'sir el danniyeh', 'kousba', 'douma', 'tannourine', 'hadath el jebbeh', 'bqaa safrin', 'abou samra', 'qobbe'],
    akkar: ['akkar', 'aakkar', 'halba', 'qoubaiyat', 'kobayat', 'bebnine', 'bibnine', 'minyara', 'rahbe', 'fnaydek', 'michmich', 'wadi khaled', 'tikrit', 'jdeidet el qaitaa', 'berqayel', 'kfartoun', 'khraibeh', 'mounjez', 'tal abbas', 'akroum', 'mashta hassan', 'aandqet', 'andaket', 'sahel akkar', 'cheikh taba', 'bire akkar', 'qobayat'],
    baalbekHermel: ['baalbek', 'baalbeck', 'baalback', 'hermel', 'el hermel', 'deir el ahmar', 'arsal', 'aarsal', 'ras baalbek', 'labweh', 'laboue', 'nabi chit', 'brital', 'douris', 'chmestar', 'chmistar', 'talia', 'el qaa', 'fakiha', 'ainata', 'bednayel', 'temnine', 'hadath baalbek', 'iaat', 'younine', 'jdeideh el fakiha', 'boudai'],
    bekaa: ['bekaa', 'beqaa', 'bqaa', 'zahle', 'zahleh', 'rachaya', 'rashaya', 'west bekaa', 'bekaa gharbi', 'joub jannine', 'jib jannine', 'saadnayel', 'bar elias', 'barelias', 'chtaura', 'chtoura', 'anjar', 'qab elias', 'kab elias', 'majdal anjar', 'mreijat', 'kfar zabad', 'machghara', 'mashghara', 'sohmor', 'kherbet qanafar', 'qaraoun', 'karaoun', 'jdita', 'taalabaya', 'taanayel', 'ferzol', 'ablah', 'riyak', 'rayak', 'niha bekaa', 'kfar mechki', 'aitanit', 'ghazze', 'mansoura', 'lala', 'khiara', 'ali el nahri', 'haouch el harimeh'],
    south: ['saida', 'sidon', 'south lebanon', 'liban sud', 'tyre', 'sour', 'tyr', 'jezzine', 'jizzine', 'ghazieh', 'ghaziyeh', 'sarafand', 'abbassieh', 'abbasiyeh', 'qana', 'maarakeh', 'majdal zoun', 'naqoura', 'adloun', 'zrariyeh', 'haret saida', 'bourj el chemali', 'burj shemali', 'deir qanoun', 'chehabiyeh', 'qlaileh', 'kfar hatta', 'bissariyeh', 'ain el hilweh', 'majdelyoun', 'salhieh', 'maghdouche', 'tebnine', 'tibnin', 'bint jbeil', 'bint jubayl', 'aitaroun', 'rmeich', 'ain ebel'],
    nabatieh: ['nabatieh', 'nabatiyeh', 'nabatiye', 'marjayoun', 'marjeyoun', 'marjaayoun', 'hasbaya', 'hasbayya', 'kfar tebnit', 'khiam', 'kfarremmen', 'zawtar', 'harouf', 'doueir', 'jbaa', 'arnoun', 'yohmor', 'kfour', 'mayfadoun', 'ebba', 'zefta', 'deir ez zahrani', 'jarjouh', 'kaoukaba', 'chebaa', 'shebaa', 'rachaya el foukhar', 'kfar chouba', 'meiss el jabal', 'houla', 'markaba', 'blida', 'kfar kila', 'kfarkila', 'ansar', 'habbouch', 'kfar roummane', 'kfarsir', 'jibchit', 'toul', 'zebdine', 'arabsalim', 'jezzine road'],
  };

  /// Approximate governorate centroids (lat, lng) used only when no boundary
  /// data is loaded.
  static const Map<String, (double, double)> _centroids = {
    beirut: (33.8938, 35.5018),
    mountLebanon: (33.78, 35.62),
    keserwanJbeil: (34.05, 35.75),
    north: (34.33, 35.95),
    akkar: (34.55, 36.15),
    baalbekHermel: (34.15, 36.30),
    bekaa: (33.70, 35.85),
    south: (33.35, 35.35),
    nabatieh: (33.30, 35.55),
  };

  /// Resolves the governorate (and district when boundaries are loaded).
  /// Order: point-in-polygon on coordinates → text keywords → nearest
  /// centroid. Returns `(region, caza)`; both null when nothing matches.
  static (String?, String?) resolve({String? name, String? address, double? lat, double? lng, LebanonBoundaries? boundaries}) {
    if (lat != null && lng != null && lat != 0 && lng != 0 && boundaries != null && boundaries.isLoaded) {
      final hit = boundaries.locate(lat, lng);
      if (hit.$1 != null) return hit;
    }
    final text = '${name ?? ''} | ${address ?? ''}'.toLowerCase();
    if (text.trim() != '|') {
      String? best;
      var bestLen = 0;
      _keywords.forEach((region, words) {
        for (final w in words) {
          if (w.length > bestLen && _containsWord(text, w)) {
            best = region;
            bestLen = w.length;
          }
        }
      });
      if (best != null) return (best, null);
    }
    if (lat != null && lng != null && lat != 0 && lng != 0) {
      return (fromCoordinates(lat, lng), null);
    }
    return (null, null);
  }

  /// Nearest governorate centroid (fallback without boundary data).
  static String? fromCoordinates(double lat, double lng) {
    if (lat < 33.0 || lat > 34.75 || lng < 35.0 || lng > 36.7) return null; // outside Lebanon
    if (lat >= 33.865 && lat <= 33.912 && lng >= 35.47 && lng <= 35.545) return beirut;
    String? best;
    var bestD = double.infinity;
    _centroids.forEach((region, c) {
      if (region == beirut) return;
      final d = math.sqrt(math.pow(lat - c.$1, 2) + math.pow((lng - c.$2) * math.cos(lat * math.pi / 180), 2));
      if (d < bestD) {
        bestD = d;
        best = region;
      }
    });
    return best;
  }

  static bool _containsWord(String text, String word) {
    var from = 0;
    while (true) {
      final i = text.indexOf(word, from);
      if (i < 0) return false;
      final before = i == 0 ? ' ' : text[i - 1];
      final afterIdx = i + word.length;
      final after = afterIdx >= text.length ? ' ' : text[afterIdx];
      if (!_isLetter(before) && !_isLetter(after)) return true;
      from = i + 1;
    }
  }

  static bool _isLetter(String c) => RegExp(r'[a-z]').hasMatch(c);
}

/// A closed ring of (lng, lat) points.
class GeoRing {
  GeoRing(this.points)
      : minLat = points.map((p) => p.$2).reduce(math.min),
        maxLat = points.map((p) => p.$2).reduce(math.max),
        minLng = points.map((p) => p.$1).reduce(math.min),
        maxLng = points.map((p) => p.$1).reduce(math.max);

  final List<(double, double)> points;
  final double minLat, maxLat, minLng, maxLng;

  bool contains(double lat, double lng) {
    if (lat < minLat || lat > maxLat || lng < minLng || lng > maxLng) return false;
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final xi = points[i].$1, yi = points[i].$2;
      final xj = points[j].$1, yj = points[j].$2;
      final intersect = ((yi > lat) != (yj > lat)) && (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}

/// A named area made of one or more polygons (outer ring + holes).
class GeoArea {
  const GeoArea({required this.name, required this.polygons});

  final String name;

  /// Each polygon: first ring is the outer boundary, the rest are holes.
  final List<List<GeoRing>> polygons;

  bool contains(double lat, double lng) {
    for (final poly in polygons) {
      if (poly.isEmpty) continue;
      if (!poly.first.contains(lat, lng)) continue;
      var inHole = false;
      for (final hole in poly.skip(1)) {
        if (hole.contains(lat, lng)) {
          inHole = true;
          break;
        }
      }
      if (!inHole) return true;
    }
    return false;
  }

  /// Outer rings as (lat, lng) lists — for drawing on a map.
  List<List<(double, double)>> get outlines => [
        for (final poly in polygons)
          if (poly.isNotEmpty) [for (final p in poly.first.points) (p.$2, p.$1)],
      ];
}

/// Governorate and district polygons parsed from the bundled geoBoundaries
/// GeoJSON (CC BY 4.0, www.geoboundaries.org).
class LebanonBoundaries {
  LebanonBoundaries({List<GeoArea>? governorates, List<GeoArea>? districts})
      : governorates = governorates ?? const [],
        districts = districts ?? const [];

  final List<GeoArea> governorates;
  final List<GeoArea> districts;

  bool get isLoaded => governorates.isNotEmpty;

  /// Parses geoBoundaries GeoJSON strings. Names are canonicalised through
  /// [LebanonRegions.boundaryNames]; unknown names are kept as-is.
  factory LebanonBoundaries.fromGeoJson({String? governoratesJson, String? districtsJson}) {
    return LebanonBoundaries(
      governorates: governoratesJson == null ? null : _parse(governoratesJson, (n) => LebanonRegions.boundaryNames[n] ?? n),
      districts: districtsJson == null ? null : _parse(districtsJson, (n) => n),
    );
  }

  static List<GeoArea> _parse(String json, String Function(String) canon) {
    final root = asMap(jsonDecode(json));
    final out = <GeoArea>[];
    for (final f in firstList(root, ['features'])) {
      final props = asMap(f['properties']);
      final name = asString(pick(props, ['shapeName', 'name', 'NAME_1', 'NAME_2'])) ?? 'Unknown';
      final geom = asMap(f['geometry']);
      final type = asString(geom['type']);
      final coords = geom['coordinates'];
      final polygons = <List<GeoRing>>[];
      if (type == 'Polygon' && coords is List) {
        polygons.add(_rings(coords));
      } else if (type == 'MultiPolygon' && coords is List) {
        for (final p in coords) {
          if (p is List) polygons.add(_rings(p));
        }
      }
      if (polygons.isNotEmpty) out.add(GeoArea(name: canon(name), polygons: polygons));
    }
    return out;
  }

  static List<GeoRing> _rings(List<Object?> polygon) => [
        for (final ring in polygon)
          if (ring is List && ring.length >= 3)
            GeoRing([
              for (final pt in ring)
                if (pt is List && pt.length >= 2) ((pt[0] as num).toDouble(), (pt[1] as num).toDouble()),
            ]),
      ];

  /// Returns `(governorate, district)` for a point, or nulls.
  (String?, String?) locate(double lat, double lng) {
    String? region;
    String? caza;
    for (final d in districts) {
      if (d.contains(lat, lng)) {
        caza = d.name;
        region = LebanonRegions.districtToRegion[d.name];
        break;
      }
    }
    if (region == null) {
      for (final g in governorates) {
        if (g.contains(lat, lng)) {
          region = g.name;
          break;
        }
      }
    }
    return (region, caza);
  }
}
