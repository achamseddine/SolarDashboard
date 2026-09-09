import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Placeholder – implemented in the feature work.
class StationsScreen extends ConsumerWidget {
  const StationsScreen({super.key, this.initialQuery, this.initialRegion, this.initialStatus});
  final String? initialQuery;
  final String? initialRegion;
  final String? initialStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) => const Center(child: Text('StationsScreen'));
}
