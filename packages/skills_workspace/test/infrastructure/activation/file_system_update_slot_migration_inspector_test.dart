import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/application/update/update_models.dart';
import 'package:skills_workspace/src/infrastructure/activation/file_system_update_slot_migration_inspector.dart';
import 'package:test/test.dart';

void main() {
  final id = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');

  test('accepts absent destinations for every activation', () async {
    final root = await Directory.systemTemp.createTemp('slot-migration-');
    addTearDown(() => root.delete(recursive: true));
    final skill = _skill(id, root.path);

    final result = await _inspector(root.path).inspect(
      snapshot: RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        managedSkills: [skill],
      ),
      skill: skill,
      newSlotKey: 'new-slot',
      cancellationToken: CancellationToken.none(),
    );

    expect(result, isA<UpdateSlotMigrationInspectionSuccess>());
  });

  test('rejects an occupied destination without following links', () async {
    final root = await Directory.systemTemp.createTemp('slot-migration-');
    addTearDown(() => root.delete(recursive: true));
    final destination = Directory(path.join(root.path, 'new-slot'));
    await destination.create();
    final skill = _skill(id, root.path);

    final result = await _inspector(root.path).inspect(
      snapshot: RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        managedSkills: [skill],
      ),
      skill: skill,
      newSlotKey: 'new-slot',
      cancellationToken: CancellationToken.none(),
    );

    expect(result, isA<UpdateSlotMigrationInspectionFailure>());
    expect(
      (result as UpdateSlotMigrationInspectionFailure).reason,
      'destinationAlreadyExists',
    );
  });

  test('rejects an occupied Repository Copy destination', () async {
    final root = await Directory.systemTemp.createTemp('slot-migration-');
    addTearDown(() => root.delete(recursive: true));
    final repositoryDestination = Directory(
      path.join(root.path, 'repository-copies', 'new-slot'),
    );
    await repositoryDestination.create(recursive: true);
    final skill = _skill(id, path.join(root.path, 'activation'));

    final result = await _inspector(root.path).inspect(
      snapshot: RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        managedSkills: [skill],
      ),
      skill: skill,
      newSlotKey: 'new-slot',
      cancellationToken: CancellationToken.none(),
    );

    expect(result, isA<UpdateSlotMigrationInspectionFailure>());
    expect(
      (result as UpdateSlotMigrationInspectionFailure).reason,
      'destinationAlreadyExists',
    );
  });

  test('rejects duplicate Repository Copy and Activation identity', () async {
    final root = await Directory.systemTemp.createTemp('slot-migration-');
    addTearDown(() => root.delete(recursive: true));
    final skill = _skill(id, root.path);
    final inspector = FileSystemUpdateSlotMigrationInspector(
      repositoryCopyPathForSlot: (slotKey) => path.join(root.path, slotKey),
    );

    final result = await inspector.inspect(
      snapshot: RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        managedSkills: [skill],
      ),
      skill: skill,
      newSlotKey: 'new-slot',
      cancellationToken: CancellationToken.none(),
    );

    expect(result, isA<UpdateSlotMigrationInspectionFailure>());
    expect(
      (result as UpdateSlotMigrationInspectionFailure).reason,
      'duplicateMigrationDestination',
    );
  });

  test('cancellation stops destination inspection', () async {
    final root = await Directory.systemTemp.createTemp('slot-migration-');
    addTearDown(() => root.delete(recursive: true));
    final source = CancellationSource();
    await source.cancel();
    final skill = _skill(id, root.path);

    final result = await _inspector(root.path).inspect(
      snapshot: RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        managedSkills: [skill],
      ),
      skill: skill,
      newSlotKey: 'new-slot',
      cancellationToken: source.token,
    );

    expect(result, isA<UpdateSlotMigrationInspectionFailure>());
    expect(
      (result as UpdateSlotMigrationInspectionFailure).reason,
      'operationCancelled',
    );
  });
}

FileSystemUpdateSlotMigrationInspector _inspector(String workspaceRoot) =>
    FileSystemUpdateSlotMigrationInspector(
      repositoryCopyPathForSlot: (slotKey) =>
          path.join(workspaceRoot, 'repository-copies', slotKey),
    );

ManagedSkill _skill(ManagedSkillId id, String location) => ManagedSkill(
  id: id,
  slotKey: 'old-slot',
  declaredName: 'old-slot',
  displayName: 'Old Slot',
  description: 'Description',
  source: LocalSourceDescriptor(locator: location),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    fileCount: 1,
    byteSize: 1,
    publishedAt: DateTime.fromMicrosecondsSinceEpoch(1, isUtc: true),
  ),
  activations: [
    SkillActivation(
      location: location,
      scope: ActivationScope.global,
      mode: ActivationMode.copy,
      agentIds: const ['agent'],
    ),
  ],
);
