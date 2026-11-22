import 'package:flutter/foundation.dart';

import 'data/google_account.dart';

/// Simulator-only sign-in probe, enabled with
/// `--dart-define=AURORA_DEMO_SIGNIN=1`.
///
/// It exists because the sign-in flow cannot be tapped from a headless test:
/// this triggers it at launch so the consent sheet can be observed (or the
/// failure read out) without a human.
const demoSignIn = String.fromEnvironment('AURORA_DEMO_SIGNIN') == '1';

Future<void> runSignInProbe(GoogleAccount account) async {
  if (!demoSignIn) return;
  await Future<void>.delayed(const Duration(seconds: 2));

  debugPrint('signin-probe: configured=${account.isConfigured}');
  try {
    final user = await account.signIn();
    debugPrint('signin-probe: user=${user?.email ?? 'cancelled'}');
  } catch (error) {
    debugPrint('signin-probe: FAILED $error');
  }
}
