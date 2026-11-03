import 'package:flutter/foundation.dart';

class NetworkActivity {
  static final waiting = ValueNotifier<Set<String>>(const {});
  static void setWaiting(String id, bool value) {
    final next = Set<String>.of(waiting.value);
    if (value ? next.add(id) : next.remove(id)) {
      waiting.value = Set.unmodifiable(next);
    }
  }
}
