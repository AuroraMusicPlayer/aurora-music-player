import 'package:flutter/foundation.dart';

/// A tiny broadcast surface so parts of the UI can refresh when the library
/// changes behind their back (auto-cache finishing, play counts moving).
class AppEvents {
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void bump() => revision.value++;

  void dispose() => revision.dispose();
}
