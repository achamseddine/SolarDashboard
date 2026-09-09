import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Navigates with go_router when the screen is hosted by the app router;
/// a no-op in isolated widget tests.
void goTo(BuildContext context, String path) {
  GoRouter.maybeOf(context)?.go(path);
}

/// Back navigation: pop when possible, otherwise go to [fallback].
void goBack(BuildContext context, {String fallback = '/stations'}) {
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    final nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) nav.pop();
    return;
  }
  if (router.canPop()) {
    router.pop();
  } else {
    router.go(fallback);
  }
}
