import 'package:skills_workspace/src/application/source/source_acquisition_coordinator.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../../support/source/source_acquisition_fakes.dart';

void main() {
  test(
    'routes each supported Source to exactly one matching adapter',
    () async {
      final ports = FakeSourceAcquisitionPorts(
        (source, selection, options, cancellationToken) async =>
            SourceAcquisitionSuccess<AcquiredSource>(
              value: _acquired(source, [_skill(source, slotKey: 'one')]),
            ),
      );
      final coordinator = SourceAcquisitionCoordinator(
        local: ports,
        git: ports,
        wellKnown: ports,
      );
      final sources = <SourceDescriptor>[
        LocalSourceDescriptor(locator: '/source'),
        GitSourceDescriptor(locator: 'https://example.test/source.git'),
        WellKnownSourceDescriptor(locator: 'https://example.test'),
      ];

      for (final source in sources) {
        final result = await coordinator.acquire(
          source: source,
          selectedSkillNames: const {'one'},
          options: const SourceAcquisitionOptions(),
        );
        expect(result.valueOrNull?.skills.single.slotKey, 'one');
      }

      expect(ports.calls, sources);
      expect(ports.lastSelection, const {'one'});
    },
  );

  test('Local and Well-known paths never call the system-Git port', () async {
    var gitCalls = 0;
    final regular = FakeSourceAcquisitionPorts(
      (source, selection, options, cancellationToken) async =>
          SourceAcquisitionSuccess<AcquiredSource>(
            value: _acquired(source, [_skill(source, slotKey: 'one')]),
          ),
    );
    final git = FakeSourceAcquisitionPorts((
      source,
      selection,
      options,
      cancellationToken,
    ) async {
      gitCalls += 1;
      return SourceAcquisitionFailure<AcquiredSource>(
        code: SourceAcquisitionFailureCode.gitUnavailable,
      );
    });
    final coordinator = SourceAcquisitionCoordinator(
      local: regular,
      git: git,
      wellKnown: regular,
    );

    for (final source in <SourceDescriptor>[
      LocalSourceDescriptor(locator: '/source'),
      WellKnownSourceDescriptor(locator: 'https://example.test'),
    ]) {
      expect(
        (await coordinator.acquire(
          source: source,
          selectedSkillNames: const {},
          options: const SourceAcquisitionOptions(),
        )).valueOrNull,
        isNotNull,
      );
    }

    expect(gitCalls, 0);
  });

  test('inspection maps normalized trees without workspace writes', () async {
    final source = LocalSourceDescriptor(locator: '/canonical/source');
    final ports = FakeSourceAcquisitionPorts(
      (source, selection, options, cancellationToken) async =>
          SourceAcquisitionSuccess<AcquiredSource>(
            value: _acquired(source, [
              _skill(source, slotKey: 'one', byteSize: 3),
              _skill(source, slotKey: 'two', byteSize: 5),
            ]),
          ),
    );
    final coordinator = SourceAcquisitionCoordinator(
      local: ports,
      git: ports,
      wellKnown: ports,
    );

    final result = await coordinator.inspect(
      source: source,
      options: const SourceAcquisitionOptions(fullDepth: true),
    );

    expect(result.valueOrNull?.source, source);
    expect(
      result.valueOrNull?.candidates.map((candidate) => candidate.slotKey),
      ['one', 'two'],
    );
    expect(
      result.valueOrNull?.candidates.map((candidate) => candidate.byteSize),
      [3, 5],
    );
  });

  test('duplicate derived Slots fail at the shared boundary', () async {
    final source = LocalSourceDescriptor(locator: '/source');
    final ports = FakeSourceAcquisitionPorts(
      (source, selection, options, cancellationToken) async =>
          SourceAcquisitionSuccess<AcquiredSource>(
            value: _acquired(source, [
              _skill(source, slotKey: 'duplicate'),
              _skill(source, slotKey: 'duplicate'),
            ]),
          ),
    );
    final coordinator = SourceAcquisitionCoordinator(
      local: ports,
      git: ports,
      wellKnown: ports,
    );

    final result = await coordinator.acquire(
      source: source,
      selectedSkillNames: const {},
      options: const SourceAcquisitionOptions(),
    );

    expect(
      result.failureOrNull?.code,
      SourceAcquisitionFailureCode.duplicateSkillSlot,
    );
    expect(result.failureOrNull?.context['slotKey'], 'duplicate');
  });

  test('pre-cancelled acquisition calls no adapter', () async {
    final cancellation = CancellationSource();
    await cancellation.cancel();
    final ports = FakeSourceAcquisitionPorts(
      (source, selection, options, cancellationToken) async =>
          throw StateError('must not be called'),
    );
    final coordinator = SourceAcquisitionCoordinator(
      local: ports,
      git: ports,
      wellKnown: ports,
    );

    final result = await coordinator.acquire(
      source: LocalSourceDescriptor(locator: '/source'),
      selectedSkillNames: const {},
      options: const SourceAcquisitionOptions(),
      cancellationToken: cancellation.token,
    );

    expect(
      result.failureOrNull?.code,
      SourceAcquisitionFailureCode.operationCancelled,
    );
    expect(ports.calls, isEmpty);
  });

  test(
    'Adopted Snapshot provenance is never reacquired as an update Source',
    () async {
      final ports = FakeSourceAcquisitionPorts(
        (source, selection, options, cancellationToken) async =>
            throw StateError('must not be called'),
      );
      final coordinator = SourceAcquisitionCoordinator(
        local: ports,
        git: ports,
        wellKnown: ports,
      );

      final result = await coordinator.acquire(
        source: AdoptedSnapshotSourceDescriptor(
          authoritativeLocation: '/agent/skills/one',
          contentHash: _hash('a'),
        ),
        selectedSkillNames: const {},
        options: const SourceAcquisitionOptions(),
      );

      expect(
        result.failureOrNull?.code,
        SourceAcquisitionFailureCode.updateUnsupported,
      );
      expect(ports.calls, isEmpty);
    },
  );
}

AcquiredSource _acquired(
  SourceDescriptor canonicalSource,
  List<AcquiredSourceSkill> skills,
) => AcquiredSource(canonicalSource: canonicalSource, skills: skills);

AcquiredSourceSkill _skill(
  SourceDescriptor source, {
  required String slotKey,
  int byteSize = 1,
}) => AcquiredSourceSkill(
  provenance: source,
  declaredName: slotKey,
  description: '$slotKey description',
  slotKey: slotKey,
  skillPath: slotKey,
  frontmatter: <String, Object?>{
    'name': slotKey,
    'description': '$slotKey description',
  },
  tree: NormalizedSkillTree(
    files: [
      NormalizedSkillFile(
        relativePath: 'SKILL.md',
        bytes: List<int>.filled(byteSize, 1),
        isExecutable: false,
      ),
    ],
    contentHash: _hash(slotKey == 'two' ? 'b' : 'a'),
    byteSize: byteSize,
  ),
);

String _hash(String character) => List.filled(64, character).join();
