import 'package:flutter/material.dart';

import '../../../core/models/device.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';

/// One card per device with grouped key readings and an expandable table.
class DeviceCards extends StatelessWidget {
  const DeviceCards({super.key, required this.devices, required this.latest});
  final List<Device> devices;
  final Map<String, DeviceLatest> latest;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return const SectionCard(title: 'Devices', child: EmptyState(message: 'No devices known for this plant yet', icon: Icons.devices_other_outlined));
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1200 ? 3 : (c.maxWidth >= 760 ? 2 : 1);
      final width = (c.maxWidth - (cols - 1) * kGap) / cols;
      return Wrap(
        spacing: kGap,
        runSpacing: kGap,
        children: [for (final d in devices) SizedBox(width: width, child: _DeviceCard(device: d, latest: latest[d.deviceSn]))],
      );
    });
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.latest});
  final Device device;
  final DeviceLatest? latest;

  static IconData _icon(Device d) {
    if (d.isInverter) return Icons.settings_input_component_outlined;
    if (d.isBattery) return Icons.battery_std_outlined;
    if (d.isLogger) return Icons.router_outlined;
    if ((d.deviceType ?? '').contains('METER')) return Icons.speed_outlined;
    return Icons.memory_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = latest;
    final status = l != null && l.status != DeviceStatus.unknown ? l.status : device.status;
    final ts = l?.collectionTs ?? device.collectionTs;
    final groups = <(String, List<(String, List<String>)>)>[
      ('PV', [('Total DC input', MeasureKeys.pvPower), ('PV1', MeasureKeys.pv1), ('PV2', MeasureKeys.pv2), ('PV3', MeasureKeys.pv3), ('PV4', MeasureKeys.pv4), ('PV1 voltage', MeasureKeys.pvVoltage1), ('PV2 voltage', MeasureKeys.pvVoltage2)]),
      ('Battery', [('SOC', MeasureKeys.soc), ('Power', MeasureKeys.batteryPower), ('Voltage', MeasureKeys.batteryVoltage), ('Current', MeasureKeys.batteryCurrent), ('Temperature', MeasureKeys.batteryTemp)]),
      ('Grid & load', [('Grid power', MeasureKeys.gridPower), ('Grid frequency', MeasureKeys.gridFrequency), ('Grid voltage', MeasureKeys.gridVoltage), ('Load', MeasureKeys.loadPower), ('Inverter temperature', MeasureKeys.inverterTemp)]),
      ('Today', [('Generation', MeasureKeys.dailyGeneration), ('Consumption', MeasureKeys.dailyConsumption), ('Import', MeasureKeys.dailyImport), ('Export', MeasureKeys.dailyExport), ('Charge', MeasureKeys.dailyCharge), ('Discharge', MeasureKeys.dailyDischarge), ('Lifetime generation', MeasureKeys.totalGeneration)]),
      ('State', [('Running status', MeasureKeys.runningStatus), ('Work mode', MeasureKeys.workMode), ('Alert message', MeasureKeys.alertMessage)]),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon(device), size: 22, color: AppColors.deviceStatus(status)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.productName ?? device.productId ?? (device.deviceType ?? 'Device'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${device.deviceType ?? '–'} · SN ${device.deviceSn}', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                DeviceStatusChip(status),
              ],
            ),
            const SizedBox(height: 4),
            Text('Data ${Fmt.dateTime(ts)} · ${Fmt.ago(ts)}${device.collectorSn == null ? '' : ' · logger ${device.collectorSn}'}', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            const Divider(height: 16),
            if (l == null || l.readings.isEmpty)
              Text(device.isLogger ? 'Loggers carry no measurements' : 'No readings received yet', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
            else ...[
              for (final g in groups)
                if (g.$2.any((e) => l.reading(e.$2) != null)) ...[
                  Text(g.$1, style: t.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                  for (final e in g.$2)
                    if (l.reading(e.$2) case final r?) InfoRow(e.$1, r.displayValue),
                  const SizedBox(height: 6),
                ],
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('All readings (${l.readings.length})', style: t.labelLarge),
                  children: [
                    ChartTable(
                      columns: const ['Key', 'Name', 'Value', 'Unit'],
                      rows: [for (final r in l.readings) [r.key, r.name ?? '', r.valueNum?.toString() ?? r.valueText ?? '', r.unit ?? '']],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
