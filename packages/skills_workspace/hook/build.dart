import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

import '../tool/native_build_policy.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final logger = Logger('skills_workspace.native');
    final logSubscription = logger.onRecord.listen(
      (record) => stderr.writeln(record.message),
    );
    try {
      final packageName = input.packageName;
      final targetOS = input.config.code.targetOS;
      final policy = NativeBuildPolicy(
        packageRoot: Directory.fromUri(input.packageRoot),
        outputDirectory: Directory.fromUri(input.outputDirectory),
        targetOS: _targetOS(targetOS),
        targetArchitecture: _targetArchitecture(
          input.config.code.targetArchitecture,
        ),
        sanitizers: NativeSanitizerConfiguration.read(
          File.fromUri(input.packageRoot.resolve('native/sanitizers.config')),
        ),
      );
      const assetName =
          'src/native/generated/skills_workspace_bindings_generated.dart';
      final nativeBuilder = NativeLibraryBuilder(policy);
      if (targetOS == OS.windows) {
        final dynamicLibrary = await nativeBuilder.buildWindowsDynamicLibrary(
          onOutput: logger.info,
          onError: logger.warning,
        );
        output.assets.code.add(
          CodeAsset(
            package: packageName,
            name: assetName,
            file: dynamicLibrary.uri,
            linkMode: DynamicLoadingBundled(),
          ),
          routing: const ToAppBundle(),
        );
        output.dependencies.addAll(policy.shimSources.map((file) => file.uri));
        output.dependencies.add(policy.nativeIncludeDirectory.uri);
      } else {
        final libgit2Archive = await nativeBuilder.buildLibgit2(
          onOutput: logger.info,
          onError: logger.warning,
        );
        final cbuilder = CBuilder.library(
          name: '${packageName}_native',
          assetName: assetName,
          sources: const [
            'native/src/native_ping.c',
            'native/src/revision_engine.c',
            'native/src/skills_workspace_runtime.c',
            'native/src/source_transport.c',
          ],
          includes: const [
            'native/include',
            'native/third_party/libgit2/include',
          ],
          libraries: ['git2', ...policy.shimSystemLibraries],
          libraryDirectories: [libgit2Archive.parent.path],
          flags: [...policy.shimFlags],
        );
        await cbuilder.run(input: input, output: output, logger: logger);
      }

      output.dependencies.add(
        input.packageRoot.resolve('native/libgit2.lock.json'),
      );
      output.dependencies.add(
        input.packageRoot.resolve('native/sanitizers.config'),
      );
      output.dependencies.add(
        input.packageRoot.resolve('native/third_party/libgit2/'),
      );
      output.dependencies.add(
        input.packageRoot.resolve('native/exports/macos.exports'),
      );
      output.dependencies.add(
        input.packageRoot.resolve('native/exports/linux.map'),
      );
    } finally {
      await logSubscription.cancel();
    }
  });
}

NativeBuildTargetOS _targetOS(OS targetOS) => switch (targetOS) {
  OS.macOS => NativeBuildTargetOS.macOS,
  OS.linux => NativeBuildTargetOS.linux,
  OS.windows => NativeBuildTargetOS.windows,
  _ => throw UnsupportedError('Unsupported native target OS: $targetOS'),
};

NativeBuildArchitecture _targetArchitecture(Architecture architecture) =>
    switch (architecture) {
      Architecture.arm64 => NativeBuildArchitecture.arm64,
      Architecture.x64 => NativeBuildArchitecture.x64,
      _ => throw UnsupportedError(
        'Unsupported Revision Engine architecture: $architecture',
      ),
    };
