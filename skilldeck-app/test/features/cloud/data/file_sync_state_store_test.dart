import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/data/cloud_device_identity.dart';
import 'package:skills_manager/features/cloud/data/file_sync_state_store.dart';

void main() {
  late Directory support;
  late List<FileSyncStateDiagnostic> diagnostics;
  const account = 'opaque-account-value';
  const device = 'opaque-device-value';
  late CloudServiceOrigin origin;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('file-sync-state-');
    addTearDown(() => support.delete(recursive: true));
    diagnostics = [];
    origin = CloudServiceOrigin.parse('https://cloud.example.com');
  });

  FileSyncStateStore store({
    String accountId = account,
    String deviceId = device,
    CloudServiceOrigin? serviceOrigin,
  }) => FileSyncStateStore(
    supportDirectory: support.path,
    origin: serviceOrigin ?? origin,
    accountId: accountId,
    deviceId: deviceId,
    onDiagnostic: diagnostics.add,
  );

  test(
    'derives stable opaque source IDs across opens and separates installations',
    () async {
      final identities = await Future.wait([
        CloudDeviceIdentity.load(support.path),
        CloudDeviceIdentity.load(support.path),
      ]);
      final reopened = await CloudDeviceIdentity.load(support.path);
      final other = await Directory.systemTemp.createTemp(
        'other-cloud-device-',
      );
      addTearDown(() => other.delete(recursive: true));
      final isolated = await CloudDeviceIdentity.load(other.path);
      final source = ['local', '/private/project/skills'];
      final id = identities.first.sourceIdFor(source);
      expect(id, matches('^[0-9a-f]{64}\$'));
      expect(identities.last.sourceIdFor(source), id);
      expect(reopened.sourceIdFor(source), id);
      expect(isolated.sourceIdFor(source), isNot(id));
      expect(
        reopened.sourceIdFor(['local', '/other/project/skills']),
        isNot(id),
      );
    },
  );

  test('persists complete state atomically and isolates origin, account and Device', () async {
    final writer = store();
    const link = SyncLink(
      managedSkillId: 'managed',
      lineageId: 'lineage',
      clientKey: 'pending-key',
      version: 8,
      generation: 3,
      effective: 'last-synced-effective',
      sourceEpoch: 'local-source-epoch',
      uploadBlockedByQuota: true,
      attentionAttempt: (
        version: 9,
        effective: 'blocked-effective',
        outcome: SyncNeedsAttention(
          AttentionReason.slotOccupied,
          deviceName: 'Studio Mac',
          occupant: 'other-local-skill',
        ),
      ),
    );
    await Future.wait([
      writer.put(link),
      writer.setFeedCursor('server-position'),
      writer.setWorkspaceCursor('41'),
      writer.setExcluded('excluded-lineage', true),
    ]);
    final reader = store();
    final restored = (await reader.links()).single;
    expect(restored.managedSkillId, link.managedSkillId);
    expect(restored.lineageId, link.lineageId);
    expect(restored.clientKey, link.clientKey);
    expect(restored.version, link.version);
    expect(restored.generation, link.generation);
    expect(restored.effective, link.effective);
    expect(restored.sourceEpoch, link.sourceEpoch);
    expect(restored.uploadBlockedByQuota, isTrue);
    expect(restored.attentionAttempt!.version, 9);
    expect(restored.attentionAttempt!.effective, 'blocked-effective');
    expect(
      restored.attentionAttempt!.outcome.reason,
      AttentionReason.slotOccupied,
    );
    expect(restored.attentionAttempt!.outcome.deviceName, 'Studio Mac');
    expect(restored.attentionAttempt!.outcome.occupant, 'other-local-skill');
    expect(await reader.feedCursor(), 'server-position');
    expect(await reader.workspaceCursor(), '41');
    expect(await reader.exclusions(), {'excluded-lineage'});
    expect(await store(accountId: 'other-account').links(), isEmpty);
    expect(await store(deviceId: 'other-device').links(), isEmpty);
    expect(
      await store(
        serviceOrigin: CloudServiceOrigin.parse('https://other.example.com'),
      ).links(),
      isEmpty,
    );
    expect(diagnostics, isEmpty);
    final file = support.listSync(recursive: true).whereType<File>().single;
    final stored = await file.readAsString();
    for (final value in [
      account,
      device,
      origin.toString(),
      'token',
      'email',
    ]) {
      expect(file.path, isNot(contains(value)));
      expect(stored, isNot(contains(value)));
    }

    await reader.unlink('managed');
    await reader.setFeedCursor(null);
    await reader.setExcluded('excluded-lineage', false);
    expect(await store().links(), isEmpty);
    expect(await store().feedCursor(), isNull);
    expect(await store().exclusions(), isEmpty);
    expect(support.listSync(recursive: true).whereType<File>(), hasLength(1));
  });

  test(
    'quarantines a truncated file and reopens with no upload candidates',
    () async {
      await store().put(
        const SyncLink(managedSkillId: 'managed', clientKey: 'pending'),
      );
      final original = support
          .listSync(recursive: true)
          .whereType<File>()
          .single;
      await original.writeAsString('{"version":1,"links":[');
      final recovered = store();
      expect(await recovered.links(), isEmpty);
      expect(await recovered.feedCursor(), isNull);
      expect(await recovered.workspaceCursor(), isNull);
      expect(await recovered.exclusions(), isEmpty);
      expect(diagnostics, [FileSyncStateDiagnostic.corrupt]);
      expect(await original.exists(), isFalse);
      final moved = support.listSync(recursive: true).whereType<File>().single;
      expect(moved.path, endsWith('.invalid'));
      expect(await moved.readAsString(), '{"version":1,"links":[');
      await recovered.setFeedCursor('fresh-from-bootstrap');
      expect(await store().feedCursor(), 'fresh-from-bootstrap');
    },
  );
}
