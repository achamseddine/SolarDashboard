import 'package:flutter/material.dart';

import 'models/alert.dart';
import 'models/device.dart';
import 'models/station.dart';

/// Colour system.
///
/// Chart series use the validated categorical palette of the data-viz method
/// (adjacent-pair CVD ΔE ≥ 8 in both modes); status colours are the fixed
/// status scale and are always paired with an icon or label. UNICEF cyan is
/// the brand accent for chrome only — never for data.
class AppColors {
  AppColors._();

  static const unicefCyan = Color(0xFF1CABE2);
  static const unicefDark = Color(0xFF00477D);

  // Status scale (mode-invariant, always with icon/label).
  static const good = Color(0xFF0CA30C);
  static const warning = Color(0xFFFAB219);
  static const serious = Color(0xFFEC835A);
  static const critical = Color(0xFFD03B3B);
  static const muted = Color(0xFF898781);

  static const online = good;
  static const offline = serious;
  static const alarm = critical;
  static const stale = warning;
  static const unknown = muted;

  static const levelHigh = critical;
  static const levelMedium = serious;
  static const levelLow = warning;

  // Light-mode series colours (see [ChartPalette] for mode-aware access).
  static const load = Color(0xFF2A78D6);
  static const pv = Color(0xFFEDA100);
  static const battery = Color(0xFF1BAF7A);
  static const gridImport = Color(0xFFEB6834);
  static const gridExport = Color(0xFF4A3AA7);
  static const grid = gridImport;

  static Color stationStatus(StationStatus s) {
    switch (s) {
      case StationStatus.online:
        return online;
      case StationStatus.offline:
        return offline;
      case StationStatus.alarm:
        return alarm;
      case StationStatus.stale:
        return stale;
      case StationStatus.unknown:
        return unknown;
    }
  }

  static IconData stationStatusIcon(StationStatus s) {
    switch (s) {
      case StationStatus.online:
        return Icons.check_circle;
      case StationStatus.offline:
        return Icons.cloud_off;
      case StationStatus.alarm:
        return Icons.warning_amber_rounded;
      case StationStatus.stale:
        return Icons.schedule;
      case StationStatus.unknown:
        return Icons.help_outline;
    }
  }

  static Color deviceStatus(DeviceStatus s) {
    switch (s) {
      case DeviceStatus.online:
        return online;
      case DeviceStatus.offline:
        return offline;
      case DeviceStatus.alarm:
        return alarm;
      case DeviceStatus.unknown:
        return unknown;
    }
  }

  static Color alertLevel(AlertLevel l) {
    switch (l) {
      case AlertLevel.high:
        return levelHigh;
      case AlertLevel.medium:
        return levelMedium;
      case AlertLevel.low:
        return levelLow;
    }
  }

  /// Ordinal blue ramp (validated), light → dark, for SOC buckets 0-20 … 80-100.
  static const socRampLight = [Color(0xFF86B6EF), Color(0xFF5598E7), Color(0xFF2A78D6), Color(0xFF1C5CAB), Color(0xFF104281)];
  static const socRampDark = [Color(0xFF184F95), Color(0xFF256ABF), Color(0xFF3987E5), Color(0xFF6DA7EC), Color(0xFF9EC5F4)];

  /// Sequential blue steps 100 → 700 for magnitude (heat cells, meters).
  static const sequential = [
    Color(0xFFCDE2FB), Color(0xFFB7D3F6), Color(0xFF9EC5F4), Color(0xFF86B6EF), Color(0xFF6DA7EC), Color(0xFF5598E7),
    Color(0xFF3987E5), Color(0xFF2A78D6), Color(0xFF256ABF), Color(0xFF1C5CAB), Color(0xFF184F95), Color(0xFF104281), Color(0xFF0D366B),
  ];
}

/// Mode-aware chart palette (series, chrome, ink). Obtain with
/// `ChartPalette.of(context)`.
class ChartPalette {
  const ChartPalette._({
    required this.isDark,
    required this.load,
    required this.pv,
    required this.battery,
    required this.gridImport,
    required this.gridExport,
    required this.accent,
    required this.deEmphasis,
    required this.surface,
    required this.grid,
    required this.axis,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkMuted,
    required this.socRamp,
    required this.categorical,
  });

  static const light = ChartPalette._(
    isDark: false,
    load: Color(0xFF2A78D6),
    pv: Color(0xFFEDA100),
    battery: Color(0xFF1BAF7A),
    gridImport: Color(0xFFEB6834),
    gridExport: Color(0xFF4A3AA7),
    accent: Color(0xFF2A78D6),
    deEmphasis: Color(0xFFC3C2B7),
    surface: Color(0xFFFCFCFB),
    grid: Color(0xFFE1E0D9),
    axis: Color(0xFFC3C2B7),
    inkPrimary: Color(0xFF0B0B0B),
    inkSecondary: Color(0xFF52514E),
    inkMuted: Color(0xFF898781),
    socRamp: AppColors.socRampLight,
    categorical: [Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A), Color(0xFFEDA100), Color(0xFFE87BA4), Color(0xFF008300), Color(0xFF4A3AA7), Color(0xFFE34948)],
  );

  static const dark = ChartPalette._(
    isDark: true,
    load: Color(0xFF3987E5),
    pv: Color(0xFFC98500),
    battery: Color(0xFF199E70),
    gridImport: Color(0xFFD95926),
    gridExport: Color(0xFF9085E9),
    accent: Color(0xFF3987E5),
    deEmphasis: Color(0xFF52514E),
    surface: Color(0xFF1A1A19),
    grid: Color(0xFF2C2C2A),
    axis: Color(0xFF383835),
    inkPrimary: Color(0xFFFFFFFF),
    inkSecondary: Color(0xFFC3C2B7),
    inkMuted: Color(0xFF898781),
    socRamp: AppColors.socRampDark,
    categorical: [Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70), Color(0xFFC98500), Color(0xFFD55181), Color(0xFF008300), Color(0xFF9085E9), Color(0xFFE66767)],
  );

  static ChartPalette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;

  final bool isDark;
  final Color load;
  final Color pv;
  final Color battery;
  final Color gridImport;
  final Color gridExport;
  final Color accent;
  final Color deEmphasis;
  final Color surface;
  final Color grid;
  final Color axis;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkMuted;
  final List<Color> socRamp;

  /// Fixed-order categorical slots (never cycle past 8 — fold to "Other").
  final List<Color> categorical;

  Color socColor(double soc) => socRamp[(soc >= 100 ? 4 : (soc / 20).floor()).clamp(0, 4)];
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.unicefCyan, brightness: brightness, primary: dark ? AppColors.unicefCyan : AppColors.unicefDark);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  return base.copyWith(
    scaffoldBackgroundColor: dark ? const Color(0xFF0D0D0D) : const Color(0xFFF9F9F7),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xFF1A1A19) : const Color(0xFFFCFCFB),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: dark ? const Color(0x1AFFFFFF) : const Color(0x1A0B0B0B))),
    ),
    appBarTheme: AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, foregroundColor: scheme.onSurface),
    dividerTheme: DividerThemeData(color: dark ? const Color(0xFF2C2C2A) : const Color(0xFFE1E0D9), space: 1),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    dataTableTheme: DataTableThemeData(headingTextStyle: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600), dataRowMinHeight: 44, dataRowMaxHeight: 56),
    visualDensity: VisualDensity.comfortable,
  );
}
