import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/backup/control_plane_backup_codec.dart';
import 'package:skills_workspace/src/application/backup/control_plane_backup_models.dart';
import 'package:skills_workspace/src/application/ports/control_plane_backup_ports.dart';
import 'package:skills_workspace/src/platform/filesystem/control_plane_backup_durability.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late PlatformControlPlaneBackupDurability durability;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-control-plane-durability-',
    );
    durability = PlatformControlPlaneBackupDurability(
      PlatformDurableWorkspaceFilesystem(),
    );
  });

  tearDown(() => temporary.delete(recursive: true));

  test(
    'durably writes and publishes a file without changing its bytes',
    () async {
      final destination = path.join(temporary.path, 'eligibility.json');
      final staging = await durability.createSiblingStagingPath(
        destination,
        kind: ControlPlaneStagingKind.file,
      );
      final bytes = List<int>.generate(257, (index) => index % 251);
      await durability.writeDurableFile(staging, bytes);
      expect(await durability.readFile(staging), bytes);

      await durability.publish(
        candidatePath: staging,
        destinationPath: destination,
        kind: ControlPlaneStagingKind.file,
        verify: (target) async {
          expect(await durability.readFile(target), bytes);
        },
      );

      expect(await durability.readFile(destination), bytes);
      expect(
        await durability.sha256File(destination),
        sha256.convert(bytes).toString(),
      );
    },
  );

  test('eligibility remains canonical through file publication', () async {
    const codec = ControlPlaneBackupCodec();
    const eligibility = SteadyBackupEligibility(
      destructionEpoch: 0,
      establishedAtRepositoryRevision: 0,
    );
    final destination = path.join(temporary.path, 'eligibility.json');
    final staging = await durability.createSiblingStagingPath(
      destination,
      kind: ControlPlaneStagingKind.file,
    );
    final encoded = codec.encodeEligibility(eligibility);
    codec.decodeEligibility(encoded);
    await durability.writeDurableFile(staging, encoded);
    codec.decodeEligibility(encoded);
    final reopened = await durability.readFile(staging);
    expect(reopened, encoded);
    codec.decodeEligibility(reopened);

    await durability.publish(
      candidatePath: staging,
      destinationPath: destination,
      kind: ControlPlaneStagingKind.file,
      verify: (target) async {
        codec.decodeEligibility(await durability.readFile(target));
      },
    );

    expect(
      codec.decodeEligibility(await durability.readFile(destination)),
      isA<SteadyBackupEligibility>(),
    );
  });

  test(
    'streams a database copy and removes the displaced generation',
    () async {
      final source = path.join(temporary.path, 'backup.sqlite');
      final destination = path.join(temporary.path, 'workspace.sqlite');
      await File(source).writeAsBytes(List<int>.filled(2 * 1024 * 1024 + 3, 7));
      await File(destination).writeAsString('old');
      final staging = await durability.createSiblingStagingPath(
        destination,
        kind: ControlPlaneStagingKind.file,
      );
      await durability.copyDurableFile(
        sourcePath: source,
        destinationPath: staging,
      );

      await durability.publish(
        candidatePath: staging,
        destinationPath: destination,
        kind: ControlPlaneStagingKind.file,
        verify: (target) async {
          expect(await durability.fileSize(target), 2 * 1024 * 1024 + 3);
        },
      );

      expect(await durability.fileSize(destination), 2 * 1024 * 1024 + 3);
      expect(await File(staging).exists(), isFalse);
      expect(
        await Directory(temporary.path)
            .list(followLinks: false)
            .where((entry) => path.basename(entry.path).contains('rollback'))
            .toList(),
        isEmpty,
      );
    },
  );
}
