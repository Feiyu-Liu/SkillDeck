import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/analytics/app_analytics.dart';

void main() {
  test('a missing failure has no analytics error code', () {
    expect(appAnalyticsErrorCode(null), isNull);
  });

  group('operationFailed reason dimensions', () {
    final cases = <({String name, Map<String, Object?> context, String code})>[
      (
        name: 'allowlisted reason',
        context: const {'reason': 'businessCommitFailed'},
        code: 'operationFailed:businessCommitFailed',
      ),
      (
        name: 'allowlisted revision code',
        context: const {'revisionCode': 'ioFailure'},
        code: 'operationFailed:ioFailure',
      ),
      (
        name: 'reason takes precedence over revision code',
        context: const {
          'reason': 'businessCommitFailed',
          'revisionCode': 'ioFailure',
        },
        code: 'operationFailed:businessCommitFailed',
      ),
      (
        name: 'non-string reason falls back to revision code',
        context: const {'reason': 42, 'revisionCode': 'ioFailure'},
        code: 'operationFailed:ioFailure',
      ),
      (
        name: 'unknown reason',
        context: const {'reason': 'somethingNew'},
        code: 'operationFailed:other',
      ),
      (
        name: 'unknown reason takes precedence over revision code',
        context: const {'reason': 'somethingNew', 'revisionCode': 'ioFailure'},
        code: 'operationFailed:other',
      ),
      (
        name: 'unknown revision code',
        context: const {'revisionCode': 'somethingNew'},
        code: 'operationFailed:other',
      ),
      (
        name: 'operation-only catch-all',
        context: const {'operation': 'adopt'},
        code: 'operationFailed:uncaught',
      ),
      (
        name: 'present null reason prevents uncaught fallback',
        context: const {'reason': null, 'operation': 'adopt'},
        code: 'operationFailed:other',
      ),
      (
        name: 'present non-string revision code prevents uncaught fallback',
        context: const {'revisionCode': 42, 'operation': 'adopt'},
        code: 'operationFailed:other',
      ),
      (
        name: 'missing reason',
        context: const {},
        code: 'operationFailed:other',
      ),
      (
        name: 'slash in reason',
        context: const {'reason': 'businessCommitFailed/ioFailure'},
        code: 'operationFailed:other',
      ),
      (
        name: 'path in reason',
        context: const {'reason': '/Users/me/private'},
        code: 'operationFailed:other',
      ),
      (
        name: 'classified preparation detail',
        context: const {
          'reason': 'preparationFailed',
          'detail': 'recoveryConflict',
        },
        code: 'operationFailed:preparationFailed_recoveryConflict',
      ),
      (
        name: 'classified apply detail',
        context: const {'reason': 'applyFailed', 'detail': 'filesystem'},
        code: 'operationFailed:applyFailed_filesystem',
      ),
      (
        name: 'unknown detail is dropped',
        context: const {
          'reason': 'preparationFailed',
          'detail': '/Users/me/private',
        },
        code: 'operationFailed:preparationFailed',
      ),
      (
        name: 'detail on a reason that carries none is ignored',
        context: const {'reason': 'ioFailure', 'detail': 'filesystem'},
        code: 'operationFailed:ioFailure',
      ),
    ];
    for (final testCase in cases) {
      test(testCase.name, () {
        final failure = WorkspaceException(
          code: WorkspaceErrorCode.operationFailed,
          operation: WorkspaceOperationKind.adopt,
          context: testCase.context,
        );
        final event = AppAnalyticsEvent.externalAdoption(
          outcome: ExternalAdoptionAnalyticsOutcome.failed,
          duration: Duration.zero,
          itemCount: 1,
          errorCode: appAnalyticsErrorCode(failure),
        );

        expect(
          event.dimensions(platform: 'macos', appVersion: '1'),
          containsPair('dimension7', testCase.code),
        );
      });
    }
  });

  test('revision failures report only allowlisted engine details', () {
    for (final key in ['reason', 'revisionCode']) {
      for (final detail in [
        'invalidInput',
        'storeUnavailable',
        'objectUnavailable',
        'verificationFailed',
        'bundleInvalid',
        'unexpectedFailure',
        '/private/path',
        'native diagnostic',
        'a' * 40,
        'filesystem',
        null,
      ]) {
        final known = const {
          'invalidInput',
          'storeUnavailable',
          'objectUnavailable',
          'verificationFailed',
          'bundleInvalid',
          'unexpectedFailure',
        }.contains(detail);
        final failure = WorkspaceException(
          code: WorkspaceErrorCode.operationFailed,
          operation: WorkspaceOperationKind.adopt,
          context: {key: 'revisionStoreUnavailable', 'detail': detail},
        );
        expect(
          appAnalyticsErrorCode(failure),
          known
              ? 'operationFailed:revisionStoreUnavailable_$detail'
              : 'operationFailed:revisionStoreUnavailable',
        );
      }
    }
  });

  test('an occupied adoption target reports what holds it', () {
    String? code(Map<String, Object?> context) => appAnalyticsErrorCode(
      WorkspaceException(
        code: WorkspaceErrorCode.activationUnavailable,
        operation: WorkspaceOperationKind.adopt,
        context: {'reason': 'adoptionTargetOccupied', ...context},
      ),
    );
    for (final occupant in [
      'emptyDirectory',
      'danglingLink',
      'file',
      'invalidSkill',
      'directoryWithContent',
      'otherSkill',
      'sameSlotSkill',
      'link',
      'unknown',
    ]) {
      expect(
        code({
          'occupant': occupant,
          'targetPaths': ['/home/x'],
        }),
        'activationUnavailable:adoptionTargetOccupied_$occupant',
      );
    }
    expect(
      code({'occupant': '/home/secret'}),
      'activationUnavailable:adoptionTargetOccupied_other',
    );
    expect(code({}), 'activationUnavailable:adoptionTargetOccupied');
  });

  test(
    'invalid adoption diagnostics are classified without leaking context',
    () {
      const cases = <(String?, String?, String)>[
        ('contentInvalid', 'invalidFrontmatter', 'frontmatter'),
        ('contentInvalid', 'missingName', 'frontmatter'),
        ('contentInvalid', 'missingDescription', 'frontmatter'),
        ('contentInvalid', 'unsupportedSkillName', 'unsupportedName'),
        ('contentInvalid', 'symbolicLinkEscapesSkillRoot', 'externalLink'),
        ('contentInvalid', 'directoryEscapesSkillRoot', 'externalLink'),
        ('contentInvalid', 'brokenOrCyclicSymbolicLink', 'brokenOrCyclicLink'),
        ('contentInvalid', 'cyclicSymbolicLink', 'brokenOrCyclicLink'),
        ('contentLimitExceeded', null, 'contentLimit'),
        ('unavailable', 'filesystemReadFailed', 'filesystem'),
        ('ioFailure', null, 'filesystem'),
        ('contentInvalid', 'unsupportedFilesystemEntry', 'invalidContent'),
        ('notFound', 'noValidSkills', 'noRootSkill'),
        (null, 'noRootSkill', 'noRootSkill'),
        ('/private/token', '/private/skill-name', 'other'),
        ('contentInvalid', '/private/skill-name', 'invalidContent'),
        (null, null, 'other'),
      ];
      for (final (code, reason, detail) in cases) {
        for (final occupant in ['invalidSkill', 'file', '/private/occupant']) {
          final failure = WorkspaceException(
            code: WorkspaceErrorCode.activationUnavailable,
            operation: WorkspaceOperationKind.adopt,
            context: {
              'reason': 'adoptionTargetOccupied',
              'occupant': occupant,
              'occupantFailureCode': code,
              'occupantFailureReason': reason,
              'targetPaths': ['/private/path'],
              'occupants': [
                {'occupantFailureReason': 'missingName'},
              ],
            },
          );
          final value = appAnalyticsErrorCode(failure);
          expect(
            value,
            'activationUnavailable:adoptionTargetOccupied_${occupant == 'invalidSkill'
                ? 'invalidSkill_$detail'
                : occupant == 'file'
                ? 'file'
                : 'other'}',
          );
          final event = AppAnalyticsEvent.externalAdoption(
            outcome: ExternalAdoptionAnalyticsOutcome.partial,
            duration: Duration.zero,
            itemCount: 13,
            adoptedCount: 12,
            errorCode: value,
          );
          final dimensions = event.dimensions(
            platform: 'macos',
            appVersion: 'test',
          );
          expect(dimensions['dimension7'], value);
          expect(dimensions.toString(), isNot(contains('/private')));
        }
      }
    },
  );

  test('a partial adoption reports selected and adopted buckets', () {
    final event = AppAnalyticsEvent.externalAdoption(
      outcome: ExternalAdoptionAnalyticsOutcome.partial,
      duration: Duration.zero,
      itemCount: 13,
      adoptedCount: 1,
      errorCode: 'activationUnavailable:adoptionTargetOccupied',
    );

    expect(event.name, 'partial');
    expect(
      event.dimensions(platform: 'macos', appVersion: '1'),
      allOf(
        containsPair('dimension5', '11_plus'),
        containsPair('dimension6', '1'),
        containsPair(
          'dimension7',
          'activationUnavailable:adoptionTargetOccupied',
        ),
      ),
    );
  });

  test('other failure codes ignore reason context', () {
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.ioFailure,
      operation: WorkspaceOperationKind.install,
      context: const {'reason': 'businessCommitFailed'},
    );

    expect(appAnalyticsErrorCode(failure), 'ioFailure');
  });

  group('activationUnavailable reason dimensions', () {
    final cases = <({String name, Map<String, Object?> context, String code})>[
      (
        name: 'allowlisted reason',
        context: const {'reason': 'activationTargetsCollide'},
        code: 'activationUnavailable:activationTargetsCollide',
      ),
      (
        name: 'occupied destination',
        context: const {
          'reason': 'adoptionTargetOccupied',
          'targetPaths': ['/Users/me/private'],
        },
        code: 'activationUnavailable:adoptionTargetOccupied',
      ),
      (
        name: 'unknown reason keeps the bare code',
        context: const {'reason': '/Users/me/private'},
        code: 'activationUnavailable',
      ),
      (
        name: 'missing reason',
        context: const {},
        code: 'activationUnavailable',
      ),
    ];
    for (final testCase in cases) {
      test(testCase.name, () {
        final failure = WorkspaceException(
          code: WorkspaceErrorCode.activationUnavailable,
          operation: WorkspaceOperationKind.adopt,
          context: testCase.context,
        );
        expect(appAnalyticsErrorCode(failure), testCase.code);
      });
    }
  });

  for (final code in ['a:b:c', 'a:', ':b', 'a b', 'operationFailed:other']) {
    test('event constructors sanitize the error code $code', () {
      final events = [
        AppAnalyticsEvent.workspaceBootstrap(
          outcome: WorkspaceBootstrapAnalyticsOutcome.failed,
          duration: Duration.zero,
          errorCode: code,
        ),
        AppAnalyticsEvent.sourceInspection(
          sourceKind: AppAnalyticsSourceKind.git,
          outcome: SourceInspectionAnalyticsOutcome.failed,
          duration: Duration.zero,
          errorCode: code,
        ),
        AppAnalyticsEvent.skillInstall(
          sourceKind: AppAnalyticsSourceKind.git,
          scope: AppAnalyticsScope.global,
          outcome: SkillInstallAnalyticsOutcome.failed,
          duration: Duration.zero,
          itemCount: 1,
          targetCount: 0,
          errorCode: code,
        ),
        AppAnalyticsEvent.externalAdoption(
          outcome: ExternalAdoptionAnalyticsOutcome.failed,
          duration: Duration.zero,
          itemCount: 1,
          errorCode: code,
        ),
      ];

      for (final event in events) {
        expect(
          event.dimensions(platform: 'macos', appVersion: '1'),
          containsPair(
            'dimension7',
            code == 'operationFailed:other' ? code : 'unexpected',
          ),
        );
      }
    });
  }

  test('uses the five-event allowlist and bucketed dimensions', () {
    final events = [
      const AppAnalyticsEvent.appStarted(),
      AppAnalyticsEvent.workspaceBootstrap(
        outcome: WorkspaceBootstrapAnalyticsOutcome.recovered,
        duration: const Duration(milliseconds: 12),
      ),
      AppAnalyticsEvent.sourceInspection(
        sourceKind: AppAnalyticsSourceKind.wellKnown,
        outcome: SourceInspectionAnalyticsOutcome.success,
        duration: const Duration(milliseconds: 20),
        itemCount: 7,
      ),
      AppAnalyticsEvent.skillInstall(
        sourceKind: AppAnalyticsSourceKind.git,
        scope: AppAnalyticsScope.project,
        outcome: SkillInstallAnalyticsOutcome.takeoverRequired,
        duration: const Duration(milliseconds: 30),
        itemCount: 2,
        targetCount: 11,
      ),
      AppAnalyticsEvent.externalAdoption(
        outcome: ExternalAdoptionAnalyticsOutcome.failed,
        duration: const Duration(milliseconds: 40),
        itemCount: 1,
        errorCode: 'externalConflict',
      ),
    ];

    expect(events.map((event) => event.action), {
      'app_started',
      'workspace_bootstrap',
      'source_inspection',
      'skill_install',
      'external_adoption',
    });
    expect(events[2].name, 'success');
    expect(events[2].dimensions(platform: 'macos', appVersion: '1.0.0'), {
      'dimension1': 'macos',
      'dimension2': '1.0.0',
      'dimension3': 'well_known',
      'dimension5': '6_10',
    });
    expect(
      events[3].dimensions(platform: 'windows', appVersion: '1.0.0'),
      containsPair('dimension6', '11_plus'),
    );
  });

  test('sanitizes error codes and defines stable count buckets', () {
    final event = AppAnalyticsEvent.workspaceBootstrap(
      outcome: WorkspaceBootstrapAnalyticsOutcome.failed,
      duration: Duration.zero,
      errorCode: '/Users/me/private',
    );

    expect(
      event.dimensions(platform: 'macos', appVersion: '1'),
      containsPair('dimension7', 'unexpected'),
    );
    expect([0, 1, 2, 5, 6, 10, 11].map(appAnalyticsCountBucket), [
      '0',
      '1',
      '2_5',
      '2_5',
      '6_10',
      '6_10',
      '11_plus',
    ]);
  });
}
