import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Placeholder – implemented in the feature work.
class AlarmsScreen extends ConsumerWidget {
  const AlarmsScreen({super.key, this.initialStationId});
  final int? initialStationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => const Center(child: Text('AlarmsScreen'));
}
