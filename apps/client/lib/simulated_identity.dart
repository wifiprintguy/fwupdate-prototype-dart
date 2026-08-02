import 'package:flutter/foundation.dart';
import 'package:fwupdate/fwupdate.dart';

/// The identity this Client app claims to have when talking to a Printer,
/// so the Printer's auth-enforcement toggle (see the Printer app's
/// Simulation Control screen) has something meaningful to check.
///
/// There's no real credential store in this prototype — see the project
/// README's "Identity / role simulation" section. [role] is carried in the
/// HTTP Basic Auth password as a fixed marker string the Printer app
/// recognizes; picking [SimulatedRole.unauthenticated] sends no
/// Authorization header at all, which is what "unauthenticated" actually
/// means at the HTTP layer.
class SimulatedIdentity extends ChangeNotifier {
  SimulatedIdentity({
    this.requestingUserName = 'rafael',
    this.role = SimulatedRole.operator,
  });

  String requestingUserName;
  SimulatedRole role;

  void update({String? requestingUserName, SimulatedRole? role}) {
    if (requestingUserName != null) this.requestingUserName = requestingUserName;
    if (role != null) this.role = role;
    notifyListeners();
  }

  String? get basicAuthUsername => role == SimulatedRole.unauthenticated ? null : requestingUserName;

  String? get basicAuthPassword => switch (role) {
    SimulatedRole.administrator => 'administrator',
    SimulatedRole.operator => 'operator',
    SimulatedRole.endUser => 'end-user',
    SimulatedRole.unauthenticated => null,
  };
}
