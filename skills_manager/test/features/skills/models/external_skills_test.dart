import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/external_skills.dart';

void main() {
  test('external discovery owns immutable collections and counts slots', () {
    final locations = ['/one/skill'];
    final agentIds = ['agent-one'];
    final hashes = {'/two/skill': 'hash-two'};
    final candidates = [
      ExternalSkillCandidate(
        slotKey: 'shared',
        declaredName: 'Shared',
        description: 'Shared candidate',
        contentHash: 'hash-one',
        locations: locations,
        agentIds: agentIds,
      ),
    ];
    final conflicts = [
      ExternalSkillConflict(slotKey: 'shared', contentHashByLocation: hashes),
      ExternalSkillConflict(
        slotKey: 'conflict-only',
        contentHashByLocation: const {'/three/skill': 'hash-three'},
      ),
    ];

    final discovery = ExternalSkillsDiscovery(
      candidates: candidates,
      conflicts: conflicts,
    );
    locations.add('/mutated');
    agentIds.add('mutated');
    hashes['/mutated'] = 'mutated';
    candidates.clear();
    conflicts.clear();

    expect(discovery.candidates.single.locations, ['/one/skill']);
    expect(discovery.candidates.single.agentIds, ['agent-one']);
    expect(discovery.conflicts.first.locations, ['/two/skill']);
    expect(discovery.uniqueSlotCount, 2);
    expect(discovery.isEmpty, isFalse);
    expect(() => discovery.candidates.clear(), throwsUnsupportedError);
    expect(
      () => discovery.conflicts.first.contentHashByLocation.clear(),
      throwsUnsupportedError,
    );
  });

  test('empty discovery reports no external skills', () {
    final discovery = ExternalSkillsDiscovery.empty();

    expect(discovery.isEmpty, isTrue);
    expect(discovery.uniqueSlotCount, 0);
  });
}
