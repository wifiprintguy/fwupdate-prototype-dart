import 'package:ipp/ipp.dart';

/// The simulated identity roles the Client app's Identity screen can send,
/// and the Printer app's auth-enforcement toggle can check against.
///
/// FWUPDATE §5.1/§5.2 both require: "The Authenticated User performing this
/// operation MUST be either an Operator or Administrator for the Printer.
/// Otherwise, the Printer MUST reject the operation and return the
/// 'client-error-forbidden', 'client-error-not-authenticated', or
/// 'client-error-not-authorized' status code, as appropriate." There's no
/// real credential store in this prototype (see README §"Identity / role
/// simulation"), so the Client just declares which role it's pretending to
/// have.
enum SimulatedRole { administrator, operator, endUser, unauthenticated }

extension SimulatedRoleAuthorization on SimulatedRole {
  bool get isAuthorizedForFirmwareOperations =>
      this == SimulatedRole.administrator || this == SimulatedRole.operator;

  /// The status code FWUPDATE §5.1/§5.2 says the Printer must return when
  /// rejecting a role that isn't Operator/Administrator.
  int get rejectionStatusCode => switch (this) {
    SimulatedRole.unauthenticated => IppStatusCode.clientErrorNotAuthenticated,
    SimulatedRole.endUser => IppStatusCode.clientErrorNotAuthorized,
    SimulatedRole.administrator ||
    SimulatedRole.operator => IppStatusCode.successfulOk,
  };
}
