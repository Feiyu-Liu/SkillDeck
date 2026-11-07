import '../../application/ports/workspace_lifecycle_ports.dart';
import '../database/workspace_database.dart';

/// Owns the single live Drift Control Plane connection for one repository.
final class DriftControlPlaneLifecycle
    implements WorkspaceControlPlaneLifecyclePort {
  DriftControlPlaneLifecycle(this._database);

  final WorkspaceDatabase _database;
  bool _opened = false;
  bool _closed = false;

  bool get isOpen => _opened && !_closed;

  @override
  Future<void> open() async {
    if (_closed) throw StateError('The Control Plane has been closed.');
    if (_opened) return;
    try {
      // Forces schema creation/migration and verifies the singleton metadata
      // row on the Drift-owned background executor.
      await _database.liveIdentity();
      _opened = true;
    } on Object {
      // Opening the delayed executor may already have spawned its worker. The
      // lifecycle owns that partial acquisition and must not leave cleanup to
      // a coordinator that never observed a successful open.
      await close();
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _opened = false;
    await _database.close();
  }
}
