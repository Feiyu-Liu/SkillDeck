import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final candidate = Directory(options.candidatePath).absolute;
  final baseline = Directory(options.baselinePath).absolute;
  if (!await candidate.exists()) {
    _fail('Candidate release bundle does not exist: ${candidate.path}', 66);
  }
  if (!await baseline.exists()) {
    _fail('Baseline release bundle does not exist: ${baseline.path}', 66);
  }

  final rawCandidateBytes = await _directorySize(candidate);
  final baselineBytes = await _directorySize(baseline);
  final nativeAssets = await _measureStrippedNativeAssets(candidate);
  final originalNativeBytes = nativeAssets.original.values.fold<int>(
    0,
    (sum, bytes) => sum + bytes,
  );
  final explainedNativeBytes = nativeAssets.stripped.values.fold<int>(
    0,
    (sum, bytes) => sum + bytes,
  );
  final candidateBytes =
      rawCandidateBytes - originalNativeBytes + explainedNativeBytes;
  final delta = candidateBytes - baselineBytes;
  final unexplained = delta - explainedNativeBytes;
  if (unexplained > options.maximumUnexplainedBytes) {
    _fail(
      'Release bundle has $unexplained unexplained bytes above the package-'
      'loading baseline; maximum is ${options.maximumUnexplainedBytes}.',
      1,
    );
  }

  final report = <String, Object>{
    'schemaVersion': 2,
    'measurement':
        'Flutter release bundle regular-file bytes with package native '
        'assets stripped',
    'rawCandidateBytes': rawCandidateBytes,
    'candidateBytes': candidateBytes,
    'baselineBytes': baselineBytes,
    'deltaBytes': delta,
    'nativeAssetsOriginal': nativeAssets.original,
    'nativeAssetsStripped': nativeAssets.stripped,
    'strippedBytesRemoved': originalNativeBytes - explainedNativeBytes,
    'explainedNativeBytes': explainedNativeBytes,
    'unexplainedBytes': unexplained,
    'maximumUnexplainedBytes': options.maximumUnexplainedBytes,
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(report);
  stdout.writeln(encoded);
  if (options.reportPath case final reportPath?) {
    final reportFile = File(reportPath);
    await reportFile.parent.create(recursive: true);
    await reportFile.writeAsString('$encoded\n', flush: true);
  }
}

Future<int> _directorySize(Directory root) async {
  var bytes = 0;
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File) bytes += await entity.length();
  }
  return bytes;
}

Future<_NativeAssetMeasurement> _measureStrippedNativeAssets(
  Directory root,
) async {
  final assets = <File>[];
  final debugCompanions = <String>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last.toLowerCase();
    if (name == 'skills_workspace_native.pdb' || name == 'sqlite3.pdb') {
      debugCompanions.add(entity.path);
      continue;
    }
    if (_isSkillsWorkspaceNative(name) || _isSQLite(name)) {
      assets.add(entity);
    }
  }
  if (debugCompanions.isNotEmpty) {
    _fail('Release bundle contains native debug companion files.', 65);
  }
  if (!assets.any(
    (asset) =>
        _isSkillsWorkspaceNative(asset.uri.pathSegments.last.toLowerCase()),
  )) {
    _fail(
      'Candidate bundle does not contain the Skills Workspace Native Asset.',
      65,
    );
  }
  if (!assets.any(
    (asset) => _isSQLite(asset.uri.pathSegments.last.toLowerCase()),
  )) {
    _fail(
      'Candidate bundle does not contain the package-owned SQLite asset.',
      65,
    );
  }

  assets.sort((left, right) => left.path.compareTo(right.path));
  final temporary = await Directory.systemTemp.createTemp(
    'skills-workspace-stripped-size-',
  );
  try {
    final original = <String, int>{};
    final stripped = <String, int>{};
    for (var index = 0; index < assets.length; index += 1) {
      final asset = assets[index];
      final name = asset.uri.pathSegments.last.toLowerCase();
      final key = original.containsKey(name) ? '$name#$index' : name;
      original[key] = await asset.length();
      final copy = await asset.copy(
        '${temporary.path}${Platform.pathSeparator}$index-$name',
      );
      await _strip(copy);
      stripped[key] = await copy.length();
    }
    return _NativeAssetMeasurement(
      original: Map<String, int>.unmodifiable(original),
      stripped: Map<String, int>.unmodifiable(stripped),
    );
  } finally {
    await temporary.delete(recursive: true);
  }
}

bool _isSkillsWorkspaceNative(String name) =>
    name == 'skills_workspace_native' ||
    name == 'libskills_workspace_native.dylib' ||
    name == 'libskills_workspace_native.so' ||
    name == 'skills_workspace_native.dll';

bool _isSQLite(String name) =>
    name == 'sqlite3' ||
    name == 'libsqlite3.dylib' ||
    name == 'libsqlite3.so' ||
    name == 'sqlite3.dll';

Future<void> _strip(File artifact) async {
  if (Platform.isWindows) return;
  final arguments = Platform.isMacOS
      ? <String>['-S', '-x', artifact.path]
      : <String>['--strip-unneeded', artifact.path];
  final result = await Process.run('strip', arguments);
  if (result.exitCode != 0) {
    _fail('Unable to strip package native asset for size evidence.', 69);
  }
}

final class _NativeAssetMeasurement {
  const _NativeAssetMeasurement({
    required this.original,
    required this.stripped,
  });

  final Map<String, int> original;
  final Map<String, int> stripped;
}

Never _fail(String message, int code) {
  stderr.writeln(message);
  exit(code);
}

final class _Options {
  const _Options({
    required this.candidatePath,
    required this.baselinePath,
    required this.maximumUnexplainedBytes,
    this.reportPath,
  });

  final String candidatePath;
  final String baselinePath;
  final int maximumUnexplainedBytes;
  final String? reportPath;

  static _Options parse(List<String> arguments) {
    String? candidate;
    String? baseline;
    String? report;
    var maximumUnexplainedBytes = 5 * 1024 * 1024;
    for (var index = 0; index < arguments.length; index += 1) {
      if (index + 1 >= arguments.length) _usage();
      final name = arguments[index];
      final value = arguments[++index];
      switch (name) {
        case '--candidate':
          candidate = value;
        case '--baseline':
          baseline = value;
        case '--report':
          report = value;
        case '--maximum-unexplained-bytes':
          maximumUnexplainedBytes = int.tryParse(value) ?? _usage();
        default:
          _usage();
      }
    }
    if (candidate == null || baseline == null || maximumUnexplainedBytes < 0) {
      _usage();
    }
    return _Options(
      candidatePath: candidate,
      baselinePath: baseline,
      maximumUnexplainedBytes: maximumUnexplainedBytes,
      reportPath: report,
    );
  }

  static Never _usage() => _fail(
    'usage: dart run tool/measure_release_size.dart '
    '--candidate <bundle> --baseline <bundle> '
    '[--maximum-unexplained-bytes <bytes>] [--report <path>]',
    64,
  );
}
