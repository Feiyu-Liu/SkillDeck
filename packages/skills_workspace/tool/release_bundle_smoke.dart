import 'dart:io';

enum ReleaseBundlePlatform { macOS, linux, windows }

final class ReleaseBundleSmokeOptions {
  const ReleaseBundleSmokeOptions({required this.bundlePath});

  final String bundlePath;

  static ReleaseBundleSmokeOptions parse(List<String> arguments) {
    if (arguments.length != 2 || arguments.first != '--bundle') {
      throw const FormatException('--bundle <path> is required.');
    }
    if (arguments[1].isEmpty) {
      throw const FormatException('The release bundle path cannot be empty.');
    }
    return ReleaseBundleSmokeOptions(bundlePath: arguments[1]);
  }
}

File releaseBundleExecutable(Directory bundle, ReleaseBundlePlatform platform) {
  final separator = Platform.pathSeparator;
  return switch (platform) {
    ReleaseBundlePlatform.macOS => File(
      '${bundle.path}${separator}Contents${separator}MacOS$separator'
      'skills_workspace_example',
    ),
    ReleaseBundlePlatform.windows => File(
      '${bundle.path}${separator}skills_workspace_example.exe',
    ),
    ReleaseBundlePlatform.linux => File(
      '${bundle.path}${separator}skills_workspace_example',
    ),
  };
}

const expectedReleaseBundleSmokeOutput =
    'Native revision engine ready · libgit2 1.9.7';

void validateReleaseBundleSmokeResult({
  required int exitCode,
  required String output,
  required String diagnostic,
}) {
  if (exitCode != 0) {
    // The child owns its diagnostics. Keep raw process output out of release
    // logs even if a future harness accidentally emits sensitive context.
    throw StateError('Release bundle smoke exited with $exitCode.');
  }
  if (!output.contains(expectedReleaseBundleSmokeOutput)) {
    throw StateError(
      'Release bundle smoke did not report the expected runtime.',
    );
  }
}
