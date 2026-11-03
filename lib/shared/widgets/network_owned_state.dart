import 'package:flutter/widgets.dart';

import '../../core/net/network_cancellation.dart';

mixin NetworkOwnedState<W extends StatefulWidget> on State<W> {
  final networkRequests = NetworkRequestOwner();
  @override
  void dispose() {
    networkRequests.dispose();
    super.dispose();
  }
}
