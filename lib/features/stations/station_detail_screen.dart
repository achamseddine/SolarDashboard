import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Placeholder – implemented in the feature work.
class StationDetailScreen extends ConsumerWidget {
  const StationDetailScreen({super.key, required this.stationId});
  final int stationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => const Center(child: Text('StationDetailScreen'));
}
