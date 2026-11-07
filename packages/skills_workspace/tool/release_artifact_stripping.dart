import 'dart:convert';
import 'dart:typed_data';

enum ReleaseArtifactPlatform { macOS, linux, windows }

final class ReleaseArtifactStrippingException implements Exception {
  const ReleaseArtifactStrippingException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class ReleaseArtifactStrippingOptions {
  const ReleaseArtifactStrippingOptions({
    required this.artifactPath,
    this.bundlePath,
    this.reportPath,
  });

  final String artifactPath;
  final String? bundlePath;
  final String? reportPath;

  static ReleaseArtifactStrippingOptions parse(List<String> arguments) {
    String? artifact;
    String? bundle;
    String? report;
    for (var index = 0; index < arguments.length; index += 2) {
      if (index + 1 >= arguments.length) {
        throw const FormatException('Every option requires a value.');
      }
      final value = arguments[index + 1];
      switch (arguments[index]) {
        case '--artifact':
          artifact = value;
        case '--bundle':
          bundle = value;
        case '--report':
          report = value;
        default:
          throw FormatException('Unknown option: ${arguments[index]}');
      }
    }
    if (artifact == null || artifact.isEmpty) {
      throw const FormatException('--artifact is required.');
    }
    return ReleaseArtifactStrippingOptions(
      artifactPath: artifact,
      bundlePath: bundle,
      reportPath: report,
    );
  }
}

final class PeCoffSymbolTable {
  const PeCoffSymbolTable({required this.pointer, required this.symbolCount});

  final int pointer;
  final int symbolCount;

  bool get isAbsent => pointer == 0 && symbolCount == 0;
}

final class ReleaseArtifactStrippingFacts {
  const ReleaseArtifactStrippingFacts({
    this.debugSections = const <String>{},
    this.localSymbols = const <String>[],
    this.peCoffSymbolTable,
    this.debugCompanions = const <String>[],
  });

  final Set<String> debugSections;
  final List<String> localSymbols;
  final PeCoffSymbolTable? peCoffSymbolTable;
  final List<String> debugCompanions;
}

Set<String> parseMachODebugSections(String loadCommands) => RegExp(
  r'^\s*sectname\s+((?:__|\.)?(?:z?debug)[A-Za-z0-9_.-]*)\s*$',
  caseSensitive: false,
  multiLine: true,
).allMatches(loadCommands).map((match) => match.group(1)!).toSet();

List<String> parseMachOLocalSymbols(String symbols) => symbols
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.contains(' non-external'))
    .toList(growable: false);

Set<String> parseElfDebugOrStaticSymbolSections(String sectionHeaders) {
  final sections = <String>{};
  for (final match in RegExp(
    r'^\s*\[\s*\d+\]\s+(\S+)',
    multiLine: true,
  ).allMatches(sectionHeaders)) {
    final name = match.group(1)!;
    final lower = name.toLowerCase();
    if (lower == '.symtab' ||
        lower == '.gnu_debuglink' ||
        lower.startsWith('.debug') ||
        lower.startsWith('.zdebug')) {
      sections.add(name);
    }
  }
  return sections;
}

PeCoffSymbolTable parsePeCoffSymbolTable(Uint8List bytes) {
  if (bytes.length < 0x40 || bytes[0] != 0x4d || bytes[1] != 0x5a) {
    throw const ReleaseArtifactStrippingException(
      'Windows artifact is not a valid DOS/PE image.',
    );
  }
  final data = ByteData.sublistView(bytes);
  final peOffset = data.getUint32(0x3c, Endian.little);
  final coffOffset = peOffset + 4;
  if (peOffset < 0 || coffOffset + 20 > bytes.length) {
    throw const ReleaseArtifactStrippingException(
      'Windows artifact has an invalid PE header offset.',
    );
  }
  if (bytes[peOffset] != 0x50 ||
      bytes[peOffset + 1] != 0x45 ||
      bytes[peOffset + 2] != 0 ||
      bytes[peOffset + 3] != 0) {
    throw const ReleaseArtifactStrippingException(
      'Windows artifact is missing the PE signature.',
    );
  }
  return PeCoffSymbolTable(
    pointer: data.getUint32(coffOffset + 8, Endian.little),
    symbolCount: data.getUint32(coffOffset + 12, Endian.little),
  );
}

bool isNativeDebugCompanionPath(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  final segments = normalized.split('/');
  return segments.any((segment) => segment.endsWith('.dsym')) ||
      normalized.endsWith('.pdb') ||
      normalized.endsWith('.debug') ||
      normalized.endsWith('.dwo') ||
      normalized.endsWith('.dwp');
}

void validateStrippedReleaseArtifact({
  required ReleaseArtifactPlatform platform,
  required String artifactPath,
  required ReleaseArtifactStrippingFacts facts,
}) {
  if (facts.debugCompanions.isNotEmpty) {
    throw ReleaseArtifactStrippingException(
      'Release bundle contains native debug companions: '
      '${facts.debugCompanions.join(', ')}',
    );
  }
  switch (platform) {
    case ReleaseArtifactPlatform.macOS:
      if (facts.debugSections.isNotEmpty) {
        throw ReleaseArtifactStrippingException(
          '$artifactPath contains Mach-O debug sections: '
          '${facts.debugSections.join(', ')}',
        );
      }
      if (facts.localSymbols.isNotEmpty) {
        throw ReleaseArtifactStrippingException(
          '$artifactPath contains ${facts.localSymbols.length} local Mach-O '
          'symbols; package native assets must be stripped with strip -S -x.',
        );
      }
    case ReleaseArtifactPlatform.linux:
      if (facts.debugSections.isNotEmpty) {
        throw ReleaseArtifactStrippingException(
          '$artifactPath contains ELF debug or static-symbol sections: '
          '${facts.debugSections.join(', ')}',
        );
      }
    case ReleaseArtifactPlatform.windows:
      final table = facts.peCoffSymbolTable;
      if (table == null || !table.isAbsent) {
        throw ReleaseArtifactStrippingException(
          '$artifactPath contains a PE/COFF symbol table.',
        );
      }
  }
}

String encodeStrippedReleaseEvidence({
  required String artifactPath,
  required ReleaseArtifactPlatform platform,
  required int byteSize,
  required ReleaseArtifactStrippingFacts facts,
}) => const JsonEncoder.withIndent('  ').convert(<String, Object?>{
  'schemaVersion': 1,
  'artifact': artifactPath,
  'platform': platform.name,
  'byteSize': byteSize,
  'stripped': true,
  'debugSections': facts.debugSections.toList()..sort(),
  'localSymbolCount': facts.localSymbols.length,
  'peCoffSymbolTablePointer': facts.peCoffSymbolTable?.pointer,
  'peCoffSymbolCount': facts.peCoffSymbolTable?.symbolCount,
  'debugCompanions': facts.debugCompanions,
});
