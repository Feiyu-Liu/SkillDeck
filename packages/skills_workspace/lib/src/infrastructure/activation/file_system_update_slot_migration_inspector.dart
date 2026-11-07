import 'dart:io';

import 'package:path/path.dart' as path;

import '../../application/update/update_models.dart';
import '../../application/ports/update_ports.dart';
import '../../domain/cancellation.dart';
import '../../domain/public_models.dart';

/// Validates the filesystem side of a source-driven Slot migration.
///
/// A Slot is materialized as one Repository Copy and below each persisted
/// Activation location. The planner has already checked the SQLite Slot
/// uniqueness constraint; this adapter closes the separate filesystem race by
/// checking every destination before a candidate is prepared. It deliberately
/// does not inspect or mutate the old path: that path is owned by the later
/// operation plan and recovery bundle.
final class FileSystemUpdateSlotMigrationInspector
    implements UpdateSlotMigrationInspectionPort {
  const FileSystemUpdateSlotMigrationInspector({
    required String Function(String slotKey) repositoryCopyPathForSlot,
  }) : _repositoryCopyPathForSlot = repositoryCopyPathForSlot;

  final String Function(String slotKey) _repositoryCopyPathForSlot;

  @override
  Future<UpdateSlotMigrationInspectionResult> inspect({
    required RepositorySnapshot snapshot,
    required ManagedSkill skill,
    required String newSlotKey,
    required CancellationToken cancellationToken,
  }) async {
    if (snapshot.findSkill(skill.id) == null) {
      return const UpdateSlotMigrationInspectionFailure(
        'managedSkillNotInSnapshot',
      );
    }
    if (newSlotKey.trim().isEmpty ||
        newSlotKey == '.' ||
        newSlotKey == '..' ||
        newSlotKey.contains('/') ||
        newSlotKey.contains(r'\') ||
        newSlotKey.contains('\u0000')) {
      return const UpdateSlotMigrationInspectionFailure('invalidSlotKey');
    }

    final destinationPaths = <String>[
      _repositoryCopyPathForSlot(newSlotKey),
      for (final activation in skill.activations)
        path.join(path.absolute(activation.location), newSlotKey),
    ];
    final destinations = <String>{};
    for (final destinationPath in destinationPaths) {
      if (cancellationToken.isCancelled) {
        return const UpdateSlotMigrationInspectionFailure('operationCancelled');
      }
      final destination = path.normalize(path.absolute(destinationPath));
      if (!destinations.add(_identityKey(destination))) {
        return const UpdateSlotMigrationInspectionFailure(
          'duplicateMigrationDestination',
        );
      }
      final type = await FileSystemEntity.type(destination, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        return const UpdateSlotMigrationInspectionFailure(
          'destinationAlreadyExists',
        );
      }
    }
    return const UpdateSlotMigrationInspectionSuccess();
  }

  String _identityKey(String value) => Platform.isWindows
      ? path.windows.normalize(value).toUpperCase()
      : path.posix.normalize(value);
}
