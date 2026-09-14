import 'school.dart';
import 'school_insights.dart';

/// Internet-connectivity roll-out of one governorate or district.
class ConnectivityGroup {
  const ConnectivityGroup({
    required this.name,
    required this.schools,
    required this.connected,
    required this.students,
    required this.connectedStudents,
    this.solarized = 0,
    this.solarizedConnected = 0,
  });

  final String name;
  final int schools;
  final int connected;
  final int students;
  final int connectedStudents;
  final int solarized;
  final int solarizedConnected;

  int get notConnected => schools - connected;
  int get studentsWithout => students - connectedStudents;
  double get share => schools == 0 ? 0 : connected / schools;
  double get studentShare => students == 0 ? 0 : connectedStudents / students;

  /// Share of the governorate's solarised schools that also have internet.
  double? get solarizedShare => solarized == 0 ? null : solarizedConnected / solarized;
}

/// The four combinations of solar and internet, with the schools in each.
enum ConnectivityQuadrant {
  both('Solar + internet', 'Solarised and on the connectivity roll-out'),
  solarOnly('Solar only', 'Solarised but no internet connection'),
  internetOnly('Internet only', 'Connected but not solarised'),
  neither('Neither', 'No solar system and no internet connection');

  const ConnectivityQuadrant(this.label, this.description);
  final String label;
  final String description;
}

/// Everything the connectivity dashboard shows. Built from the bundled MEHE
/// master list and the internet-connectivity roll-out, joined with the solar
/// tracker and (where a plant is linked) the live fleet.
class ConnectivityInsights {
  const ConnectivityInsights({
    required this.generatedAt,
    required this.byRegion,
    required this.byCaza,
    required this.quadrants,
    required this.quadrantStudents,
    this.schools = 0,
    this.connected = 0,
    this.students = 0,
    this.connectedStudents = 0,
    this.solarized = 0,
    this.solarizedConnected = 0,
    this.monitored = 0,
    this.monitoredConnected = 0,
    this.connectedWithCoordinates = 0,
    this.downWithoutInternet = 0,
    this.connectivityOnlyRecords = 0,
    this.topGaps = const [],
    this.bestServed = const [],
  });

  final DateTime generatedAt;

  /// Roll-out per governorate, largest first.
  final List<ConnectivityGroup> byRegion;

  /// Roll-out per district (caza), largest gap first.
  final List<ConnectivityGroup> byCaza;

  /// School counts per solar × internet combination.
  final Map<ConnectivityQuadrant, int> quadrants;

  /// Student counts per solar × internet combination.
  final Map<ConnectivityQuadrant, int> quadrantStudents;

  final int schools;
  final int connected;
  final int students;
  final int connectedStudents;
  final int solarized;
  final int solarizedConnected;

  /// Schools whose plant is monitored in the DeyeCloud account.
  final int monitored;
  final int monitoredConnected;

  /// Connected schools that can be placed on the map.
  final int connectedWithCoordinates;

  /// Monitored plants that are offline at a school with no internet.
  final int downWithoutInternet;

  /// Schools that appear in the connectivity list but not in the MEHE master
  /// list (their record is thinner).
  final int connectivityOnlyRecords;

  /// Districts with the largest number of schools still without internet.
  final List<ConnectivityGroup> topGaps;

  /// Districts with the highest connectivity share (at least 5 schools).
  final List<ConnectivityGroup> bestServed;

  int get notConnected => schools - connected;
  int get studentsWithout => students - connectedStudents;
  double get share => schools == 0 ? 0 : connected / schools;
  double get studentShare => students == 0 ? 0 : connectedStudents / students;

  /// Share of solarised schools that also have internet.
  double? get solarizedShare => solarized == 0 ? null : solarizedConnected / solarized;

  /// Share of monitored plants whose school has internet. A monitored plant
  /// needs a data path, so a low share points at unreported outages.
  double? get monitoredShare => monitored == 0 ? null : monitoredConnected / monitored;

  int quadrant(ConnectivityQuadrant q) => quadrants[q] ?? 0;
  int quadrantStudentCount(ConnectivityQuadrant q) => quadrantStudents[q] ?? 0;

  /// Which quadrant a school falls into.
  static ConnectivityQuadrant quadrantOf(School s) {
    if (s.isSolarized) return s.connected ? ConnectivityQuadrant.both : ConnectivityQuadrant.solarOnly;
    return s.connected ? ConnectivityQuadrant.internetOnly : ConnectivityQuadrant.neither;
  }

  /// Which quadrant a school insight falls into.
  static ConnectivityQuadrant quadrantOfInsight(SchoolInsight s) => quadrantOf(s.school);
}
