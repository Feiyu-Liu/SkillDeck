import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/activation/activation_result.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/infrastructure/activation/file_system_activation_update_validator.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';

void main() {
  late Directory temporaryDirectory;
  late FileSystemActivationUpdateValidator validator;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-update-validator-',
    );
    validator = FileSystemActivationUpdateValidator(
      locationIdentity: const PosixActivationLocationIdentity(),
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('missing Activation location is unavailable', () async {
    final location = path.join(temporaryDirectory.path, 'missing');
    final result = await validator.validateCopyTarget(
      activation: _activation(location, ActivationMode.copy),
      targetPath: path.join(location, 'example'),
    );

    expect(
      result.failureOrNull?.code,
      ActivationFailureCode.activationUnavailable,
    );
    expect(result.failureOrNull?.context['reason'], 'locationUnavailable');
  });

  test('copy validation probes writability and removes its probe', () async {
    final location = Directory(path.join(temporaryDirectory.path, 'copy'));
    await location.create();

    final result = await validator.validateCopyTarget(
      activation: _activation(location.path, ActivationMode.copy),
      targetPath: path.join(location.path, 'example'),
    );

    expect(result.isSuccess, isTrue);
    expect(await location.list().toList(), isEmpty);
  });

  test('matching symbolic link and repository directory are valid', () async {
    if (Platform.isWindows) {
      return;
    }
    final location = Directory(path.join(temporaryDirectory.path, 'links'));
    final repository = Directory(
      path.join(temporaryDirectory.path, 'repository', 'example'),
    );
    await location.create();
    await repository.create(recursive: true);
    final targetPath = path.join(location.path, 'example');
    await Link(targetPath).create(repository.path);

    final result = await validator.validateSymbolicLink(
      activation: _activation(location.path, ActivationMode.symbolicLink),
      targetPath: targetPath,
      expectedLinkTarget: repository.path,
    );

    expect(result.isSuccess, isTrue);
  });

  test(
    'missing or redirected symbolic links fail with stable reasons',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final location = Directory(path.join(temporaryDirectory.path, 'links'));
      final repository = Directory(
        path.join(temporaryDirectory.path, 'repository', 'example'),
      );
      final other = Directory(path.join(temporaryDirectory.path, 'other'));
      await location.create();
      await repository.create(recursive: true);
      await other.create();
      final targetPath = path.join(location.path, 'example');

      final missing = await validator.validateSymbolicLink(
        activation: _activation(location.path, ActivationMode.symbolicLink),
        targetPath: targetPath,
        expectedLinkTarget: repository.path,
      );
      expect(missing.failureOrNull?.context['reason'], 'symbolicLinkMissing');

      await Link(targetPath).create(other.path);
      final redirected = await validator.validateSymbolicLink(
        activation: _activation(location.path, ActivationMode.symbolicLink),
        targetPath: targetPath,
        expectedLinkTarget: repository.path,
      );
      expect(
        redirected.failureOrNull?.context['reason'],
        'symbolicLinkTargetMismatch',
      );
    },
  );

  test('link to missing Repository Copy is rejected', () async {
    if (Platform.isWindows) {
      return;
    }
    final location = Directory(path.join(temporaryDirectory.path, 'links'));
    await location.create();
    final missingRepository = path.join(
      temporaryDirectory.path,
      'missing-repository',
    );
    final targetPath = path.join(location.path, 'example');
    await Link(targetPath).create(missingRepository);

    final result = await validator.validateSymbolicLink(
      activation: _activation(location.path, ActivationMode.symbolicLink),
      targetPath: targetPath,
      expectedLinkTarget: missingRepository,
    );

    expect(
      result.failureOrNull?.context['reason'],
      'repositoryCopyUnavailable',
    );
  });
}

SkillActivation _activation(String location, ActivationMode mode) =>
    SkillActivation(
      location: location,
      scope: ActivationScope.global,
      mode: mode,
      agentIds: const <String>['agent'],
    );
