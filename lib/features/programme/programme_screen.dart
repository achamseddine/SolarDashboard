import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/school_insights.dart';
import '../../core/providers.dart';
import '../common/widgets.dart';

/// Programme dashboard: solarisation coverage, connectivity, investment,
/// audited loads vs generation, education indicators (stub — filled in by
/// the programme UI task).
class ProgrammeScreen extends ConsumerWidget {
  const ProgrammeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(schoolInsightsProvider);
    return AsyncView<SchoolInsights>(
      value: insights,
      builder: (d) => ListView(
        padding: kPagePadding,
        children: [
          PageHeader(title: 'Programme', subtitle: '${d.solarized} of ${d.publicSchools} public schools solarised'),
        ],
      ),
    );
  }
}
