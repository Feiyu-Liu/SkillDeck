import 'dart:io';

import 'package:test/test.dart';

import '../../tool/release_bundle_smoke.dart';

void main() {
  test('parses the release bundle option', () {
    final options = ReleaseBundleSmokeOptions.parse(const <String>[
      '--bundle',
      '/release/app',
    ]);

    expect(options.bundlePath, '/release/app');
    expect(
      () => ReleaseBundleSmokeOptions.parse(const <String>[]),
      throwsFormatException,
    );
  });

  test('resolves every desktop release executable shape', () {
    final bundle = Directory('/release/app');

    expect(
      releaseBundleExecutable(bundle, ReleaseBundlePlatform.macOS).path,
      contains('Contents${Platform.pathSeparator}MacOS'),
    );
    expect(
      releaseBundleExecutable(bundle, ReleaseBundlePlatform.windows).path,
      endsWith('skills_workspace_example.exe'),
    );
    expect(
      releaseBundleExecutable(bundle, ReleaseBundlePlatform.linux).path,
      endsWith('skills_workspace_example'),
    );
  });

  test('accepts only a successful smoke result with the pinned runtime', () {
    validateReleaseBundleSmokeResult(
      exitCode: 0,
      output: '$expectedReleaseBundleSmokeOutput\n',
      diagnostic: '',
    );

    expect(
      () => validateReleaseBundleSmokeResult(
        exitCode: 1,
        output: '',
        diagnostic: 'load failed',
      ),
      throwsStateError,
    );
    expect(
      () => validateReleaseBundleSmokeResult(
        exitCode: 0,
        output: 'wrong runtime',
        diagnostic: '',
      ),
      throwsStateError,
    );
  });
}
