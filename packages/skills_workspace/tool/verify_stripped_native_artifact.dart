import 'dart:io';

import 'release_artifact_stripping.dart';

Future<void> main(List<String> arguments) async {
  try {
    final options = ReleaseArtifactStrippingOptions.parse(arguments);
    final artifact = File(options.artifactPath).absolute;
    if (!await artifact.exists()) {
      _fail('Native artifact does not exist: ${artifact.path}', 66);
    }
    final debugCompanions = options.bundlePath == null
        ? const <String>[]
        : await _debugCompanions(Directory(options.bundlePath!).absolute);
    final platform = _hostPlatform();
    final facts = switch (platform) {
      ReleaseArtifactPlatform.macOS => ReleaseArtifactStrippingFacts(
        debugSections: parseMachODebugSections(
          await _run('otool', <String>['-l', artifact.path]),
        ),
        localSymbols: parseMachOLocalSymbols(
          await _run('nm', <String>['-m', artifact.path]),
        ),
        debugCompanions: debugCompanions,
      ),
      ReleaseArtifactPlatform.linux => ReleaseArtifactStrippingFacts(
        debugSections: parseElfDebugOrStaticSymbolSections(
          await _run('readelf', <String>['-W', '-S', artifact.path]),
        ),
        debugCompanions: debugCompanions,
      ),
      ReleaseArtifactPlatform.windows => ReleaseArtifactStrippingFacts(
        peCoffSymbolTable: parsePeCoffSymbolTable(await artifact.readAsBytes()),
        debugCompanions: debugCompanions,
      ),
    };
    validateStrippedReleaseArtifact(
      platform: platform,
      artifactPath: artifact.path,
      facts: facts,
    );
    final evidence = encodeStrippedReleaseEvidence(
      artifactPath: artifact.path,
      platform: platform,
      byteSize: await artifact.length(),
      facts: facts,
    );
    stdout.writeln(evidence);
    if (options.reportPath case final reportPath?) {
      final report = File(reportPath);
      await report.parent.create(recursive: true);
      await report.writeAsString('$evidence\n', flush: true);
    }
  } on FormatException catch (error) {
    _fail('${error.message}\n${_usage()}', 64);
  } on ReleaseArtifactStrippingException catch (error) {
    _fail(error.message, 1);
  }
}

ReleaseArtifactPlatform _hostPlatform() {
  if (Platform.isMacOS) return ReleaseArtifactPlatform.macOS;
  if (Platform.isLinux) return ReleaseArtifactPlatform.linux;
  if (Platform.isWindows) return ReleaseArtifactPlatform.windows;
  throw UnsupportedError('Release artifact stripping supports desktop hosts.');
}

Future<List<String>> _debugCompanions(Directory bundle) async {
  if (!await bundle.exists()) {
    throw ReleaseArtifactStrippingException(
      'Release bundle does not exist: ${bundle.path}',
    );
  }
  final paths = <String>[];
  await for (final entity in bundle.list(recursive: true, followLinks: false)) {
    if (isNativeDebugCompanionPath(entity.path)) paths.add(entity.path);
  }
  paths.sort();
  return paths;
}

Future<String> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    final diagnostic = (result.stderr as String).trim();
    throw ReleaseArtifactStrippingException(
      '$executable failed with exit code ${result.exitCode}'
      '${diagnostic.isEmpty ? '.' : ': $diagnostic'}',
    );
  }
  return result.stdout as String;
}

String _usage() =>
    'usage: dart run tool/verify_stripped_native_artifact.dart '
    '--artifact <path> [--bundle <path>] [--report <path>]';

Never _fail(String message, int code) {
  stderr.writeln(message);
  exit(code);
}
